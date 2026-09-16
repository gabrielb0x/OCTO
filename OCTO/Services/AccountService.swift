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
    /// The account accepted a change, but reading it back shows it wasn't kept.
    case settingNotSaved

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
        case .settingNotSaved:
            return String(localized: "ChatGPT didn't keep this change. Try again, or change it in ChatGPT.")
        }
    }
}

enum TranscriptionError: LocalizedError, Equatable {
    /// ChatGPT heard nothing it could write down.
    case tooShort

    var errorDescription: String? {
        String(localized: "ChatGPT didn't quite catch that. Try again and speak a little longer.")
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

    /// Saves one setting of the account, the way ChatGPT's own settings do.
    func updateSetting(_ feature: AccountSettingFeature, value: Bool) async throws {
        _ = try await send(ChatGPTAccountAPI.accountUserSettingURL(feature, value: value), method: "PATCH")
    }

    func subscription() async throws -> AccountSubscription {
        let accountID = try await vault.credential().accountID
        return try await fetch(ChatGPTAccountAPI.accountCheckURL) { AccountSubscription.parse($0, accountID: accountID) }
    }

    /// What ChatGPT charges where this device is, for the plans shown by Upgrade.
    func checkoutPricing() async throws -> CheckoutPricing {
        let url = ChatGPTAccountAPI.checkoutPricingURL(countryCode: Locale.current.region?.identifier ?? "")
        return try await fetch(url, parse: CheckoutPricing.parse)
    }

    func ageStatus() async throws -> AgeStatus {
        try await fetch(ChatGPTAccountAPI.ageStatusURL, parse: AgeStatus.parse)
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

    /// Forgets one saved memory of the account, like ChatGPT's own Memory screen.
    func deleteMemory(id: String) async throws {
        do {
            _ = try await send(ChatGPTAccountAPI.memoryURL(id: id), method: "DELETE")
        } catch AccountAPIError.notFound {
            // Already gone from the account, which ChatGPT's own screen also counts as deleted.
        }
    }

    /// Whether the account's policy lets its data be used for training at all.
    func dataUsagePolicy() async throws -> Bool {
        try await fetch(ChatGPTAccountAPI.dataUsagePolicyURL, parse: TrainingPolicy.parse)
    }

    /// Clears the advertising profile ChatGPT keeps for the account, the call its own ads screen
    /// makes. It answers `204 No Content`, and an account with nothing kept answers `404`.
    func deleteAdsProfile() async throws {
        do {
            _ = try await send(ChatGPTAccountAPI.adsProfileURL, method: "DELETE")
        } catch AccountAPIError.notFound {
            // Nothing was kept for this account, which is what deleting it aims for.
        }
    }

    // MARK: Devices & protection

    /// The devices signed into the ChatGPT account, as its own "Devices" screen lists them.
    func devices() async throws -> AccountDevices {
        try await fetch(ChatGPTAccountAPI.devicesURL, parse: AccountDevices.parse)
    }

    /// How the account is protected. The two calls are asked for together, and whichever answers
    /// is shown: an account without multi-factor still has sign-in alerts to report, and vice versa.
    func security() async throws -> AccountSecurity {
        async let settingsRequest = send(ChatGPTAccountAPI.securitySettingsURL)
        async let multiFactorRequest = send(ChatGPTAccountAPI.multiFactorURL)
        let settings = try? await settingsRequest
        let multiFactor = try? await multiFactorRequest
        guard let value = AccountSecurity.parse(settings: settings, multiFactor: multiFactor) else {
            DevLog.log("account", "Unexpected response from the security settings", level: .warning)
            throw AccountAPIError.invalidResponse
        }
        return value
    }

    /// Space the files of the account's chats take on ChatGPT's side.
    func fileStorage() async throws -> AccountFileStorage {
        try await fetch(ChatGPTAccountAPI.fileStorageURL, parse: AccountFileStorage.parse)
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

    // MARK: Dictation

    /// Has ChatGPT write down a dictation recording, like the dictation of its apps (`POST /transcribe`).
    func transcribe(audio: Data, durationMilliseconds: Int) async throws -> String {
        let form = ChatGPTTranscription.form(audio: audio, durationMilliseconds: durationMilliseconds)
        var request = try await makeRequest(ChatGPTTranscription.url, method: "POST", body: form.encoded(), contentType: form.contentType)
        request.timeoutInterval = 120
        let (data, response) = try await session.recordedData(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            DevLog.log("dictation", "POST /transcribe → HTTP \(http.statusCode)", level: .warning)
            let payload = APIErrorPayload.parse(data)
            if payload.code == "audio_too_short" || payload.message?.lowercased() == "audio too short" {
                throw TranscriptionError.tooShort
            }
            throw Self.error(for: http, data: data)
        }
        guard let text = ChatGPTTranscription.parse(data) else {
            DevLog.log("dictation", "Unexpected response from /transcribe", level: .warning)
            throw AccountAPIError.invalidResponse
        }
        return text
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

    /// Searches every chat of the account, inside the messages, like ChatGPT's own search.
    func searchConversations(query: String) async throws -> [RemoteSearchHit] {
        try await fetch(ChatGPTAccountAPI.conversationSearchURL(query: query), parse: RemoteSearchResults.parse)
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

    private func makeRequest(_ url: URL, method: String = "GET", body: Data? = nil, contentType: String? = nil, accept: String? = nil) async throws -> URLRequest {
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
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ url: URL, method: String = "GET", body: Data? = nil, accept: String? = nil) async throws -> Data {
        let request = try await makeRequest(url, method: method, body: body, accept: accept)
        let (data, response) = try await session.recordedData(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            DevLog.log("account", "\(method) \(url.path) → HTTP \(http.statusCode)", level: .warning)
            throw Self.error(for: http, data: data)
        }
        return data
    }

    private static func error(for response: HTTPURLResponse, data: Data) -> AccountAPIError {
        switch response.statusCode {
        case 401:
            return .unauthorized
        case 403 where response.value(forHTTPHeaderField: "cf-mitigated") != nil || isHTML(response):
            return .blocked
        case 404:
            return .notFound
        case 500...599:
            return .server(response.statusCode)
        default:
            return .http(response.statusCode, APIErrorPayload.parse(data).message)
        }
    }

    private static func isHTML(_ response: HTTPURLResponse) -> Bool {
        (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("text/html")
    }
}
