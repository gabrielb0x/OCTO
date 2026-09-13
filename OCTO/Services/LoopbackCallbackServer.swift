import Foundation
import Network

/// Tiny HTTP listener bound to the loopback interface that receives the OAuth
/// redirect (`http://localhost:1455/auth/callback`). It answers with a redirect
/// to `octo://auth/callback`, which closes the web authentication sheet.
final class LoopbackCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gabrielb0x.octo.loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var callbackPath = "/"
    private var onCallback: (@Sendable (String?) -> Void)?
    private let appScheme: String

    init(appScheme: String = "octo") {
        self.appScheme = appScheme
    }

    deinit {
        listener?.cancel()
    }

    /// `onFailure` fires if the port cannot be bound (for example when it is already in use).
    func start(
        port: UInt16,
        path: String,
        onCallback: @escaping @Sendable (String?) -> Void,
        onFailure: @escaping @Sendable () -> Void
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw URLError(.badURL)
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        let listener = try NWListener(using: parameters, on: endpointPort)
        lock.withLock {
            self.callbackPath = path
            self.onCallback = onCallback
            self.listener = listener
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.stop()
                onFailure()
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        let listener = lock.withLock { () -> NWListener? in
            let current = self.listener
            self.listener = nil
            self.onCallback = nil
            return current
        }
        listener?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(to: buffer[buffer.startIndex..<headerEnd.lowerBound], on: connection)
            } else if isComplete || error != nil || buffer.count > 32_768 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: Data, on connection: NWConnection) {
        let requestLine = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let target = parts.count >= 2 ? String(parts[1]) : "/"
        let components = URLComponents(string: "http://localhost\(target)")
        let (expectedPath, handler) = lock.withLock { (callbackPath, onCallback) }

        guard let components, components.path == expectedPath else {
            send(status: "404 Not Found", extraHeaders: [:], body: "Not found", on: connection)
            return
        }

        let query = components.percentEncodedQuery
        var location = "\(appScheme)://auth/callback"
        if let query, !query.isEmpty {
            location += "?\(query)"
        }
        let page = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">\
        <title>OCTO</title></head><body style="background:#050506;color:#fff;font-family:-apple-system;\
        display:flex;height:100vh;margin:0;align-items:center;justify-content:center;text-align:center">\
        <p>Signed in. You can return to OCTO.</p></body></html>
        """
        send(status: "302 Found", extraHeaders: ["Location": location], body: page, on: connection)
        handler?(query)
    }

    private func send(status: String, extraHeaders: [String: String], body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: text/html; charset=utf-8\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        for (name, value) in extraHeaders {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
