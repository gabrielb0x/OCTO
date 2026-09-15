import Foundation
import OCTOCore

/// Failures developer mode can simulate, to see how OCTO copes with them.
enum SimulatedFailure: String, CaseIterable, Identifiable, Sendable {
    case none
    case offline
    case accountBlocked
    case accountServerError
    case repliesConnectionLost
    case signInTimeout

    var id: String { rawValue }
}

/// One HTTP exchange in the developer network log. Only redacted copies are kept.
struct NetworkEntry: Identifiable, Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case auth
        case account
        case codex
        case other
    }

    enum Phase: Equatable, Sendable {
        case pending
        case streaming
        case finished
        case failed(String)
    }

    let id: UUID
    let startedAt: Date
    let method: String
    let url: URL
    let category: Category
    let requestHeaders: [String: String]
    let requestBody: String?
    var phase: Phase = .pending
    var statusCode: Int?
    var responseHeaders: [String: String] = [:]
    var responseBody: String?
    var responseBytes = 0
    var duration: TimeInterval?
    var streamEvents = 0
    var eventCounts: [String: Int] = [:]
    var isSimulated = false
    /// Grows with every update, so an update arriving late never replaces a newer one.
    var revision = 0

    var displayURL: String { HTTPLogRedactor.url(url) }

    var isFailure: Bool {
        if case .failed = phase { return true }
        return (statusCode ?? 0) >= 400
    }

    var curlCommand: String {
        HTTPLogRedactor.curlCommand(method: method, url: url, headers: requestHeaders, body: requestBody)
    }

    static func category(for url: URL) -> Category {
        let host = url.host?.lowercased() ?? ""
        if host == "auth.openai.com" { return .auth }
        guard host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") else { return .other }
        let path = url.path
        return path.hasPrefix("/backend-api/codex/") || path.hasPrefix("/backend-api/wham/") ? .codex : .account
    }
}

/// Records HTTP exchanges for developer mode and simulates failures on request.
/// Does nothing while developer mode is off.
final class NetworkRecorder: @unchecked Sendable {
    static let shared = NetworkRecorder()

    enum Simulation {
        case error(Error)
        case response(Data, HTTPURLResponse)
    }

    private let lock = NSLock()
    private var isRecording = false
    private var failure = SimulatedFailure.none
    private var sink: (@Sendable (NetworkEntry) -> Void)?

    func configure(recording: Bool, failure: SimulatedFailure, sink: (@Sendable (NetworkEntry) -> Void)?) {
        lock.withLock {
            isRecording = recording
            self.failure = failure
            self.sink = sink
        }
    }

    func begin(_ request: URLRequest) -> NetworkRecording? {
        let sink: (@Sendable (NetworkEntry) -> Void)? = lock.withLock { isRecording ? self.sink : nil }
        guard let sink, let url = request.url else { return nil }
        let headers = request.allHTTPHeaderFields ?? [:]
        let contentType = headers.first { $0.key.lowercased() == "content-type" }?.value
        let entry = NetworkEntry(
            id: UUID(),
            startedAt: Date(),
            method: request.httpMethod ?? "GET",
            url: url,
            category: NetworkEntry.category(for: url),
            requestHeaders: HTTPLogRedactor.headers(headers),
            requestBody: Self.preview(request.httpBody, contentType: contentType)
        )
        return NetworkRecording(entry: entry, sink: sink)
    }

    func simulation(for request: URLRequest, streaming: Bool) -> Simulation? {
        let failure = lock.withLock { self.failure }
        guard failure != .none, let url = request.url else { return nil }
        let category = NetworkEntry.category(for: url)
        switch failure {
        case .offline:
            return .error(URLError(.notConnectedToInternet))
        case .accountBlocked where category == .account:
            let body = Data("<!DOCTYPE html><html><head><title>Just a moment...</title></head><body></body></html>".utf8)
            let headers = ["Content-Type": "text/html; charset=UTF-8", "cf-mitigated": "challenge"]
            return HTTPURLResponse(url: url, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: headers).map { Simulation.response(body, $0) }
        case .accountServerError where category == .account:
            let body = Data(#"{"detail":"Simulated server error"}"#.utf8)
            let headers = ["Content-Type": "application/json"]
            return HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: headers).map { Simulation.response(body, $0) }
        case .repliesConnectionLost where category == .codex && streaming:
            return .error(URLError(.networkConnectionLost))
        case .signInTimeout where category == .auth:
            return .error(URLError(.timedOut))
        default:
            return nil
        }
    }

    static func preview(_ data: Data?, contentType: String?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        guard data.count <= 2_000_000 else { return "<\(data.count) bytes>" }
        return HTTPLogRedactor.body(data, contentType: contentType)
    }
}

/// The log entry of one request, updated as its response arrives.
final class NetworkRecording: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: NetworkEntry
    private let sink: @Sendable (NetworkEntry) -> Void

    init(entry: NetworkEntry, sink: @escaping @Sendable (NetworkEntry) -> Void) {
        self.entry = entry
        self.sink = sink
        sink(entry)
    }

    func receive(_ response: URLResponse, data: Data, simulated: Bool = false) {
        update { entry in
            let http = response as? HTTPURLResponse
            entry.statusCode = http?.statusCode
            entry.responseHeaders = Self.headers(of: http)
            entry.responseBody = NetworkRecorder.preview(data, contentType: http?.value(forHTTPHeaderField: "Content-Type"))
            entry.responseBytes = data.count
            entry.isSimulated = simulated
            entry.phase = .finished
        }
    }

    func receiveStreamHead(_ response: URLResponse) {
        update { entry in
            let http = response as? HTTPURLResponse
            entry.statusCode = http?.statusCode
            entry.responseHeaders = Self.headers(of: http)
            entry.phase = .streaming
        }
    }

    /// `preview` holds the first events of the stream, or the error body of a refused request.
    func finishStream(bytes: Int, events: Int, eventCounts: [String: Int], preview: String?, error: Error?) {
        update { entry in
            entry.responseBytes = bytes
            entry.streamEvents = events
            entry.eventCounts = eventCounts
            if let preview {
                let type = entry.responseHeaders.first { $0.key.lowercased() == "content-type" }?.value
                entry.responseBody = HTTPLogRedactor.body(Data(preview.utf8), contentType: type ?? "text/event-stream")
            }
            entry.phase = error.map { NetworkEntry.Phase.failed(DevLog.describe($0)) } ?? .finished
        }
    }

    func fail(_ error: Error, simulated: Bool = false) {
        update { entry in
            entry.isSimulated = simulated
            entry.phase = .failed(DevLog.describe(error))
        }
    }

    private func update(_ change: (inout NetworkEntry) -> Void) {
        let snapshot: NetworkEntry = lock.withLock {
            change(&entry)
            entry.duration = Date().timeIntervalSince(entry.startedAt)
            entry.revision += 1
            return entry
        }
        sink(snapshot)
    }

    private static func headers(of response: HTTPURLResponse?) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response?.allHeaderFields ?? [:] {
            result[String(describing: key)] = String(describing: value)
        }
        return HTTPLogRedactor.headers(result)
    }
}

extension URLSession {
    /// `data(for:)`, recorded in developer mode's network log.
    func recordedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let recorder = NetworkRecorder.shared
        let recording = recorder.begin(request)
        switch recorder.simulation(for: request, streaming: false) {
        case .error(let error)?:
            recording?.fail(error, simulated: true)
            throw error
        case .response(let data, let response)?:
            try await Task.sleep(for: .milliseconds(300))
            recording?.receive(response, data: data, simulated: true)
            return (data, response as URLResponse)
        case nil:
            break
        }
        do {
            let (data, response) = try await self.data(for: request)
            recording?.receive(response, data: data)
            return (data, response)
        } catch {
            recording?.fail(error)
            throw error
        }
    }

    /// `bytes(for:)`, recorded in the network log. The caller reports how the stream ends.
    func recordedBytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse, NetworkRecording?) {
        let recorder = NetworkRecorder.shared
        let recording = recorder.begin(request)
        if case .error(let error)? = recorder.simulation(for: request, streaming: true) {
            recording?.fail(error, simulated: true)
            throw error
        }
        do {
            let (bytes, response) = try await self.bytes(for: request)
            recording?.receiveStreamHead(response)
            return (bytes, response, recording)
        } catch {
            recording?.fail(error)
            throw error
        }
    }
}
