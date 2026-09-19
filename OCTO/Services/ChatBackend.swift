import Foundation
import OCTOCore

struct ChatStreamRequest: Sendable {
    var modelID: String
    var instructions: String
    var input: [ResponsesInputMessage]
    var reasoningEffort: String?
    var reasoningSummaries: Bool
    var verbosity: String?
    var webSearch: Bool
    /// Asks for the hosted image generation tool, which the Codex backend may not offer.
    var imageGeneration = false
    /// A faster tier such as `priority` (Codex's "Fast"); nil answers at the usual speed.
    var serviceTier: String?
    var cacheKey: String
    /// Set after the backend refused top-level instructions: they are sent as a developer message instead.
    var instructionsAsDeveloperMessage = false
    /// Set after the backend refused image generation: the reply is written without it.
    var imageGenerationRefused = false
    /// Set after the backend refused the service tier: the reply comes at the usual speed.
    var serviceTierRefused = false
}

enum ChatBackendError: LocalizedError {
    case failure(ChatFailureKind)
    case invalidResponse
    /// Codex listed the model, but won't let this account use it.
    case modelUnavailable(modelID: String, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "OpenAI returned an unexpected response.")
        case .modelUnavailable(_, let message):
            return message ?? String(localized: "Codex doesn't offer this model to your plan.")
        case .failure(let kind):
            switch kind {
            case .unauthorized:
                return String(localized: "Your session has expired. Please sign in again.")
            case .usageLimitReached(let resetsAt):
                guard let resetsAt else {
                    return String(localized: "You've reached your ChatGPT usage limit. Try again later.")
                }
                let time = resetsAt.formatted(date: .omitted, time: .shortened)
                return String(localized: "You've reached your ChatGPT usage limit. It resets at \(time).")
            case .usageNotIncluded:
                return String(localized: "Your ChatGPT plan doesn't include this. Upgrade your plan to continue.")
            case .insufficientQuota:
                return String(localized: "Your OpenAI quota is used up.")
            case .rateLimited:
                return String(localized: "Too many requests right now. Wait a moment and try again.")
            case .contextTooLong:
                return String(localized: "This conversation is too long for the model. Start a new chat.")
            case .blocked(let message):
                return message ?? String(localized: "OpenAI refused the request.")
            case .invalidRequest(let message):
                return message ?? String(localized: "OpenAI rejected the request.")
            case .server:
                return String(localized: "OpenAI is having trouble right now. Try again in a moment.")
            case .other(let message):
                return message ?? String(localized: "Something went wrong.")
            }
        }
    }

    var requiresSignIn: Bool {
        if case .failure(.unauthorized) = self { return true }
        return false
    }
}

/// Generates replies through the Codex backend of the ChatGPT plan, straight from the device.
/// No proxy, no analytics.
final class ChatBackend: Sendable {
    let vault: CredentialVault
    let session: URLSession

    init(vault: CredentialVault, session: URLSession) {
        self.vault = vault
        self.session = session
    }

    func stream(_ request: ChatStreamRequest) -> AsyncThrowingStream<ResponseStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request, continuation: continuation, attempt: 0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: ChatStreamRequest,
        continuation: AsyncThrowingStream<ResponseStreamUpdate, Error>.Continuation,
        attempt: Int
    ) async throws {
        let credential = try await vault.credential(forceRefresh: attempt > 0)
        let urlRequest = try makeURLRequest(for: request, credential: credential)
        let (bytes, response, recording) = try await session.recordedBytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            recording?.finishStream(bytes: 0, events: 0, eventCounts: [:], preview: nil, error: ChatBackendError.invalidResponse)
            throw ChatBackendError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 65_536 { break }
            }
            let payload = APIErrorPayload.parse(body)
            recording?.finishStream(bytes: body.count, events: 0, eventCounts: [:], preview: String(decoding: body, as: UTF8.self), error: nil)
            DevLog.log("codex", "Responses HTTP \(http.statusCode) for \(request.modelID): \(payload.message ?? "no message")", level: .error)

            if http.statusCode == 401, attempt == 0 {
                return try await run(request, continuation: continuation, attempt: attempt + 1)
            }
            // The Codex backend only offers the tools of the Codex clients. When it turns image
            // generation down, the question still deserves an answer: it's asked again without it.
            if http.statusCode == 400, request.imageGeneration, !request.imageGenerationRefused,
               ResponsesTool.isUnsupported(ResponsesTool.imageGeneration.type, message: payload.message) {
                DevLog.log("codex", "Image generation isn't offered by the backend: replying without it", level: .warning)
                continuation.yield(.imageGenerationUnsupported)
                var fallback = request
                fallback.imageGenerationRefused = true
                return try await run(fallback, continuation: continuation, attempt: attempt + 1)
            }
            if http.statusCode == 400, !request.instructionsAsDeveloperMessage,
               (payload.message ?? "").lowercased().contains("instruction") {
                var fallback = request
                fallback.instructionsAsDeveloperMessage = true
                return try await run(fallback, continuation: continuation, attempt: attempt + 1)
            }
            // A faster tier the plan doesn't include: the question still deserves an answer, at
            // the usual speed.
            if http.statusCode == 400, let tier = request.serviceTier, !request.serviceTierRefused,
               ResponsesRequest.isServiceTierRefusal(tier, message: payload.message) {
                DevLog.log("codex", "The \(tier) tier isn't offered to this plan: replying at the usual speed", level: .warning)
                continuation.yield(.serviceTierUnsupported)
                var fallback = request
                fallback.serviceTierRefused = true
                // Same session: nothing about the tokens changed.
                return try await run(fallback, continuation: continuation, attempt: attempt)
            }
            if ModelAvailability.isRefusal(status: http.statusCode, payload: payload, modelID: request.modelID) {
                throw ChatBackendError.modelUnavailable(modelID: request.modelID, message: payload.message)
            }
            throw ChatBackendError.failure(ChatFailureKind.classify(status: http.statusCode, payload: payload))
        }

        // Where the plan's limits stand comes with the headers of the reply.
        if let limits = CodexRateLimits.parse(headers: Self.headers(of: http)) {
            continuation.yield(.rateLimits(limits))
        }

        var parser = ServerSentEventParser()
        var stats = StreamStats(isRecording: recording != nil)
        do {
            for try await byte in bytes {
                stats.bytes += 1
                guard let event = parser.consume(byte) else { continue }
                stats.record(event)
                try forward(event, to: continuation)
            }
            if let event = parser.finish() {
                stats.record(event)
                try forward(event, to: continuation)
            }
            recording?.finishStream(bytes: stats.bytes, events: stats.events, eventCounts: stats.counts, preview: stats.preview, error: nil)
        } catch {
            recording?.finishStream(bytes: stats.bytes, events: stats.events, eventCounts: stats.counts, preview: stats.preview, error: error)
            throw error
        }
    }

    private func forward(_ event: ServerSentEvent, to continuation: AsyncThrowingStream<ResponseStreamUpdate, Error>.Continuation) throws {
        for update in ResponseStreamDecoder.updates(fromEventData: event.data) {
            if case .failed(let failure) = update {
                throw ChatBackendError.failure(ChatFailureKind.classify(failure))
            }
            continuation.yield(update)
        }
    }

    private func makeURLRequest(for request: ChatStreamRequest, credential: CredentialVault.Credential) throws -> URLRequest {
        var urlRequest = URLRequest(url: CodexBackend.responsesURL)
        let headers = CodexBackend.headers(accessToken: credential.accessToken, accountID: credential.accountID, userAgent: AppInfo.userAgent, sessionID: request.cacheKey)
        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var input = request.input
        var instructions: String? = request.instructions
        if request.instructionsAsDeveloperMessage {
            input.insert(ResponsesInputMessage(role: .developer, content: [.inputText(request.instructions)]), at: 0)
            instructions = nil
        }

        var tools: [ResponsesTool] = []
        if request.webSearch {
            tools.append(.webSearch(externalWebAccess: true))
        }
        if request.imageGeneration, !request.imageGenerationRefused {
            tools.append(.imageGeneration)
        }

        let body = ResponsesRequest(
            model: request.modelID,
            instructions: instructions,
            input: input,
            tools: tools,
            reasoning: request.reasoningEffort.map { ResponsesReasoning(effort: $0, summary: request.reasoningSummaries ? "auto" : nil) },
            serviceTier: request.serviceTierRefused ? nil : request.serviceTier,
            promptCacheKey: request.cacheKey,
            text: request.verbosity.map { ResponsesTextOptions(verbosity: $0) }
        )
        urlRequest.httpBody = try body.encoded()
        return urlRequest
    }

    // MARK: Models & usage

    func fetchModels() async throws -> [ModelDescriptor] {
        let credential = try await vault.credential()
        var request = URLRequest(url: CodexBackend.modelsURL)
        for (name, value) in CodexBackend.headers(accessToken: credential.accessToken, accountID: credential.accountID, userAgent: AppInfo.userAgent) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.timeoutInterval = 30

        let (data, response) = try await session.recordedData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ChatBackendError.failure(ChatFailureKind.classify(status: status, payload: APIErrorPayload.parse(data)))
        }
        guard let models = ModelCatalog.parseCodexModels(data), !models.isEmpty else { throw ChatBackendError.invalidResponse }
        return models
    }

    /// Usage windows of the ChatGPT plan.
    func fetchUsage() async throws -> UsageSnapshot? {
        let credential = try await vault.credential()
        var request = URLRequest(url: CodexBackend.usageURL)
        request.timeoutInterval = 30
        for (name, value) in CodexBackend.headers(accessToken: credential.accessToken, accountID: credential.accountID, userAgent: AppInfo.userAgent) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.recordedData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ChatBackendError.failure(ChatFailureKind.classify(status: status, payload: APIErrorPayload.parse(data)))
        }
        return UsageSnapshot.parse(data)
    }

    /// The tokens the account's Codex usage went through, day by day and in all.
    func fetchTokenActivity() async throws -> CodexTokenActivity {
        let credential = try await vault.credential()
        var request = URLRequest(url: CodexBackend.tokenActivityURL)
        request.timeoutInterval = 30
        for (name, value) in CodexBackend.headers(accessToken: credential.accessToken, accountID: credential.accountID, userAgent: AppInfo.userAgent) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.recordedData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ChatBackendError.failure(ChatFailureKind.classify(status: status, payload: APIErrorPayload.parse(data)))
        }
        guard let activity = CodexTokenActivity.parse(data) else { throw ChatBackendError.invalidResponse }
        return activity
    }

    private static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            headers[String(describing: name)] = String(describing: value)
        }
        return headers
    }

    func generateTitle(model: ModelDescriptor, userText: String, assistantText: String) async throws -> String? {
        let request = ChatStreamRequest(
            modelID: model.id,
            instructions: TitlePrompt.instructions,
            input: TitlePrompt.input(userText: userText, assistantText: assistantText),
            reasoningEffort: model.lightestEffort,
            reasoningSummaries: false,
            verbosity: model.supportsVerbosity ? "low" : nil,
            webSearch: false,
            cacheKey: "octo-title-\(UUID().uuidString)"
        )
        var text = ""
        for try await update in stream(request) {
            if case .textDelta(let delta) = update {
                text += delta
            }
        }
        return TitlePrompt.sanitize(text)
    }
}

/// What the network log shows about a streamed reply: size, events by type and the first events.
private struct StreamStats {
    let isRecording: Bool
    var bytes = 0
    var events = 0
    var counts: [String: Int] = [:]
    var preview = ""

    mutating func record(_ event: ServerSentEvent) {
        guard isRecording else { return }
        events += 1
        let name = event.event ?? Self.type(in: event.data) ?? "message"
        counts[name, default: 0] += 1
        if preview.utf8.count < 24_000 {
            preview += "event: \(name)\ndata: \(event.data)\n\n"
        }
    }

    /// The `"type"` of a Responses event, read without decoding the whole JSON.
    static func type(in data: String) -> String? {
        guard let range = data.range(of: "\"type\":\"") else { return nil }
        let rest = data[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
