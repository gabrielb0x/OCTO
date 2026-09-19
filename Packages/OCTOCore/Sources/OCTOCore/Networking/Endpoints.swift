import Foundation

/// The ChatGPT-plan backend used by the Codex CLI when signed in with ChatGPT.
/// Requests are billed against the plan's Codex usage limits, not the API.
public enum CodexBackend {
    public static let responsesURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    /// The tokens of each day and of all time (`stats`), as the Codex CLI reads them.
    public static let tokenActivityURL = URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!

    /// The backend rejects requests whose `originator` is not a first-party
    /// Codex client, so OCTO presents itself as the open-source Codex CLI and
    /// appends its own name to the User-Agent.
    public static let originator = "codex_cli_rs"
    public static let clientVersion = "0.155.0"

    public static var modelsURL: URL {
        var components = URLComponents(string: "https://chatgpt.com/backend-api/codex/models")!
        components.queryItems = [URLQueryItem(name: "client_version", value: clientVersion)]
        return components.url!
    }

    public static func userAgent(systemName: String, systemVersion: String, architecture: String, appVersion: String) -> String {
        "\(originator)/\(clientVersion) (\(systemName) \(systemVersion); \(architecture)) OCTO/\(appVersion)"
    }

    public static func headers(accessToken: String, accountID: String?, userAgent: String, sessionID: String? = nil) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "originator": originator,
            "User-Agent": userAgent,
        ]
        if let accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-ID"] = accountID
        }
        if let sessionID, !sessionID.isEmpty {
            headers["session-id"] = sessionID
        }
        return headers
    }
}

/// The public OpenAI Platform API, used when signed in with an API key.
public enum OpenAIPlatform {
    public static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    public static let modelsURL = URL(string: "https://api.openai.com/v1/models")!

    public static func headers(apiKey: String, userAgent: String) -> [String: String] {
        ["Authorization": "Bearer \(apiKey)", "User-Agent": userAgent]
    }
}
