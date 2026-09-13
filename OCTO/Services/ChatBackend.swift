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
    var cacheKey: String
    /// Set after the backend refused top-level instructions: they are sent as a developer message instead.
    var instructionsAsDeveloperMessage = false
}

enum ChatBackendError: LocalizedError {
    case failure(ChatFailureKind)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "OpenAI returned an unexpected response.")
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
                return String(localized: "Your ChatGPT plan doesn't include this. Upgrade your plan or use an API key.")
            case .insufficientQuota:
                return String(localized: "Your OpenAI API quota is used up. Check your billing settings.")
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

/// Talks directly to OpenAI: the ChatGPT backend when signed in with ChatGPT,
/// or the public API with an API key. No proxy, no analytics.
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
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ChatBackendError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 65_536 { break }
            }
            let payload = APIErrorPayload.parse(body)

            if http.statusCode == 401, attempt == 0, case .chatGPT = credential {
                return try await run(request, continuation: continuation, attempt: attempt + 1)
            }
            if http.statusCode == 400, !request.instructionsAsDeveloperMessage,
               (payload.message ?? "").lowercased().contains("instruction") {
                var fallback = request
                fallback.instructionsAsDeveloperMessage = true
                return try await run(fallback, continuation: continuation, attempt: attempt + 1)
            }
            throw ChatBackendError.failure(ChatFailureKind.classify(status: http.statusCode, payload: payload))
        }

        var parser = ServerSentEventParser()
        for try await byte in bytes {
            guard let event = parser.consume(byte) else { continue }
            try forward(event, to: continuation)
        }
        if let event = parser.finish() {
            try forward(event, to: continuation)
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
        var urlRequest: URLRequest
        let isChatGPT: Bool
        switch credential {
        case .chatGPT(let accessToken, let accountID):
            urlRequest = URLRequest(url: CodexBackend.responsesURL)
            let headers = CodexBackend.headers(accessToken: accessToken, accountID: accountID, userAgent: AppInfo.userAgent, sessionID: request.cacheKey)
            for (name, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
            isChatGPT = true
        case .apiKey(let key):
            urlRequest = URLRequest(url: OpenAIPlatform.responsesURL)
            for (name, value) in OpenAIPlatform.headers(apiKey: key, userAgent: AppInfo.userAgent) {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
            isChatGPT = false
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

        let body = ResponsesRequest(
            model: request.modelID,
            instructions: instructions,
            input: input,
            tools: request.webSearch ? [.webSearch(externalWebAccess: isChatGPT ? true : nil)] : [],
            reasoning: request.reasoningEffort.map { ResponsesReasoning(effort: $0, summary: request.reasoningSummaries ? "auto" : nil) },
            promptCacheKey: request.cacheKey,
            text: request.verbosity.map { ResponsesTextOptions(verbosity: $0) }
        )
        urlRequest.httpBody = try body.encoded()
        return urlRequest
    }

    // MARK: Models & usage

    func fetchModels() async throws -> [ModelDescriptor] {
        let credential = try await vault.credential()
        var request: URLRequest
        switch credential {
        case .chatGPT(let accessToken, let accountID):
            request = URLRequest(url: CodexBackend.modelsURL)
            for (name, value) in CodexBackend.headers(accessToken: accessToken, accountID: accountID, userAgent: AppInfo.userAgent) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        case .apiKey(let key):
            request = URLRequest(url: OpenAIPlatform.modelsURL)
            for (name, value) in OpenAIPlatform.headers(apiKey: key, userAgent: AppInfo.userAgent) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ChatBackendError.failure(ChatFailureKind.classify(status: status, payload: APIErrorPayload.parse(data)))
        }
        let models: [ModelDescriptor]?
        switch credential {
        case .chatGPT: models = ModelCatalog.parseCodexModels(data)
        case .apiKey: models = ModelCatalog.parsePlatformModels(data)
        }
        guard let models, !models.isEmpty else { throw ChatBackendError.invalidResponse }
        return models
    }

    /// ChatGPT plan usage windows; nil when signed in with an API key.
    func fetchUsage() async throws -> UsageSnapshot? {
        guard case .chatGPT(let accessToken, let accountID) = try await vault.credential() else { return nil }
        var request = URLRequest(url: CodexBackend.usageURL)
        request.timeoutInterval = 30
        for (name, value) in CodexBackend.headers(accessToken: accessToken, accountID: accountID, userAgent: AppInfo.userAgent) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ChatBackendError.failure(ChatFailureKind.classify(status: status, payload: APIErrorPayload.parse(data)))
        }
        return UsageSnapshot.parse(data)
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
