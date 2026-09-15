import Foundation
import OCTOCore

enum AccountAPIError: LocalizedError, Equatable {
    /// Cloudflare answered with a challenge meant for web browsers.
    case blocked
    case unauthorized
    case notFound
    case server(Int)
    case http(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .blocked:
            return String(localized: "ChatGPT blocked the request for your account data. Try again later.")
        case .unauthorized:
            return String(localized: "ChatGPT refused access to your account data. Try signing out and in again.")
        case .notFound:
            return String(localized: "This chat no longer exists in your ChatGPT account.")
        case .server:
            return String(localized: "ChatGPT is having trouble right now. Try again in a moment.")
        case .http(let status, let message):
            return message ?? String(localized: "ChatGPT returned an error (HTTP \(status)).")
        case .invalidResponse:
            return String(localized: "ChatGPT returned an unexpected response.")
        }
    }
}

/// The raw answer to a request typed in the developer console.
struct ConsoleResponse: Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let body: String
    let byteCount: Int
    let duration: TimeInterval
}

/// Reads and edits the ChatGPT account (profile, settings, chats) with the signed-in session.
/// Requests go straight from the device to chatgpt.com.
final class AccountService: Sendable {
    let vault: CredentialVault
    let session: URLSession

    init(vault: CredentialVault, session: URLSession) {
        self.vault = vault
        self.session = session
    }

    // MARK: Profile & settings

    func profile() async throws -> AccountProfile {
        try await fetch(ChatGPTAccountAPI.profileURL, parse: AccountProfile.parse)
    }

    func settings() async throws -> AccountSettings {
        try await fetch(ChatGPTAccountAPI.settingsURL, parse: AccountSettings.parse)
    }

    func subscription() async throws -> AccountSubscription {
        let accountID = try await vault.credential().accountID
        return try await fetch(ChatGPTAccountAPI.accountCheckURL) { AccountSubscription.parse($0, accountID: accountID) }
    }

    func customInstructions() async throws -> CustomInstructions {
        try await fetch(ChatGPTAccountAPI.customInstructionsURL, parse: CustomInstructions.parse)
    }

    func saveCustomInstructions(_ instructions: CustomInstructions) async throws -> CustomInstructions {
        let data = try await send(ChatGPTAccountAPI.customInstructionsURL, method: "POST", body: instructions.requestBody())
        // The response is normally the saved instructions; anything else keeps what was sent.
        if let object = JSONValue.object(data),
           object["traits_model_message"] != nil || object["about_model_message"] != nil,
           let saved = CustomInstructions.parse(data) {
            return saved
        }
        return instructions
    }

    func personalityTypes() async throws -> [PersonalityOption] {
        try await fetch(ChatGPTAccountAPI.personalityTypesURL, parse: PersonalityCatalog.parseTypes)
    }

    func personalityTraits() async throws -> [PersonalityTrait] {
        try await fetch(ChatGPTAccountAPI.personalityTraitsURL, parse: PersonalityCatalog.parseTraits)
    }

    func memories() async throws -> MemoriesSnapshot {
        try await fetch(ChatGPTAccountAPI.memoriesURL, parse: MemoriesSnapshot.parse)
    }

    func trainingPreference() async throws -> Bool {
        try await fetch(ChatGPTAccountAPI.trainingPreferenceURL, parse: TrainingPreference.parse)
    }

    /// The account's live feature limits, read from `POST /conversation/init` like the website does.
    func featureLimits() async throws -> FeatureLimits {
        let timezone = TimeZone.current
        let body = ChatGPTAccountAPI.conversationInitBody(
            timezone: timezone.identifier,
            offsetMinutes: -timezone.secondsFromGMT() / 60
        )
        let data = try await send(ChatGPTAccountAPI.conversationInitURL, method: "POST", body: body)
        guard let value = FeatureLimits.parse(data) else {
            DevLog.log("account", "Unexpected response from conversation/init", level: .warning)
            throw AccountAPIError.invalidResponse
        }
        return value
    }

    // MARK: Chats

    func conversations(offset: Int, limit: Int, archived: Bool = false) async throws -> RemoteConversationPage {
        try await fetch(ChatGPTAccountAPI.conversationsURL(offset: offset, limit: limit, archived: archived), parse: RemoteConversationPage.parse)
    }

    func projects() async throws -> [RemoteProject] {
        try await fetch(ChatGPTAccountAPI.projectsURL(), parse: RemoteProjectList.parse)
    }

    func projectConversations(projectID: String, cursor: String?) async throws -> RemoteConversationPage {
        try await fetch(ChatGPTAccountAPI.projectConversationsURL(projectID: projectID, cursor: cursor), parse: RemoteConversationPage.parse)
    }

    func conversation(id: String) async throws -> RemoteConversation {
        try await fetch(ChatGPTAccountAPI.conversationURL(id: id)) { RemoteConversationParser.parse($0, id: id) }
    }

    func rename(conversationID: String, to title: String) async throws {
        _ = try await send(ChatGPTAccountAPI.conversationURL(id: conversationID), method: "PATCH", body: ChatGPTAccountAPI.conversationUpdateBody(title: title))
    }

    func delete(conversationID: String) async throws {
        _ = try await send(ChatGPTAccountAPI.conversationURL(id: conversationID), method: "PATCH", body: ChatGPTAccountAPI.conversationUpdateBody(isVisible: false))
    }

    func setArchived(_ isArchived: Bool, conversationID: String) async throws {
        _ = try await send(ChatGPTAccountAPI.conversationURL(id: conversationID), method: "PATCH", body: ChatGPTAccountAPI.conversationUpdateBody(isArchived: isArchived))
    }

    func deleteAllConversations() async throws {
        _ = try await send(ChatGPTAccountAPI.allConversationsURL, method: "PATCH", body: ChatGPTAccountAPI.conversationUpdateBody(isVisible: false))
    }

    /// Pictures hosted on chatgpt.com need the session; pictures hosted elsewhere never get the token.
    func imageData(at url: URL) async throws -> Data {
        if url.scheme == "https", let host = url.host?.lowercased(), host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") {
            return try await send(url, accept: "image/*")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.recordedData(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountAPIError.invalidResponse
        }
        return data
    }

    // MARK: Developer console

    /// A GET request typed in the developer console, returned whatever its status.
    func consoleGET(_ url: URL) async throws -> ConsoleResponse {
        let request = try await makeRequest(url)
        let started = Date()
        let (data, response) = try await session.recordedData(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            headers[String(describing: key)] = String(describing: value)
        }
        return ConsoleResponse(
            url: url,
            statusCode: http?.statusCode ?? 0,
            headers: HTTPLogRedactor.headers(headers),
            body: HTTPLogRedactor.body(data, contentType: http?.value(forHTTPHeaderField: "Content-Type"), limit: 400_000) ?? "",
            byteCount: data.count,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: Requests

    private func fetch<Value>(_ url: URL, parse: (Data) -> Value?) async throws -> Value {
        let data = try await send(url)
        guard let value = parse(data) else {
            DevLog.log("account", "Unexpected response from \(url.path)", level: .warning)
            throw AccountAPIError.invalidResponse
        }
        return value
    }

    private func makeRequest(_ url: URL, method: String = "GET", body: Data? = nil, accept: String? = nil) async throws -> URLRequest {
        let credential = try await vault.credential()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        let headers = ChatGPTAccountAPI.headers(
            accessToken: credential.accessToken,
            accountID: credential.accountID,
            userAgent: AppInfo.userAgent,
            language: AppInfo.languageTag
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ url: URL, method: String = "GET", body: Data? = nil, accept: String? = nil) async throws -> Data {
        let request = try await makeRequest(url, method: method, body: body, accept: accept)
        let (data, response) = try await session.recordedData(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            DevLog.log("account", "\(method) \(url.path) → HTTP \(http.statusCode)", level: .warning)
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw AccountAPIError.unauthorized
        case 403 where http.value(forHTTPHeaderField: "cf-mitigated") != nil || Self.isHTML(http):
            throw AccountAPIError.blocked
        case 404:
            throw AccountAPIError.notFound
        case 500...599:
            throw AccountAPIError.server(http.statusCode)
        default:
            throw AccountAPIError.http(http.statusCode, APIErrorPayload.parse(data).message)
        }
    }

    private static func isHTML(_ response: HTTPURLResponse) -> Bool {
        (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("text/html")
    }
}
