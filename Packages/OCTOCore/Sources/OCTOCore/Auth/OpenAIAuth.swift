import Foundation

/// "Sign in with ChatGPT": the public OAuth 2.0 + PKCE client used by the
/// open-source Codex CLI (github.com/openai/codex, codex-rs/login).
public enum OpenAIAuth {
    public static let issuer = URL(string: "https://auth.openai.com")!
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let scopes = "openid profile email offline_access"

    /// The redirect URI registered for this client is a loopback address, so
    /// the app briefly listens on this port while the browser sheet is open.
    public static let loopbackPort: UInt16 = 1455
    public static let callbackPath = "/auth/callback"
    public static let redirectURI = "http://localhost:1455/auth/callback"

    public static let authorizeURLBase = URL(string: "https://auth.openai.com/oauth/authorize")!
    public static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    public static let revokeURL = URL(string: "https://auth.openai.com/oauth/revoke")!

    public static let deviceUserCodeURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
    public static let deviceTokenURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    public static let deviceVerificationURL = URL(string: "https://auth.openai.com/codex/device")!
    public static let deviceRedirectURI = "https://auth.openai.com/deviceauth/callback"

    public static func authorizeURL(codeChallenge: String, state: String, originator: String = CodexBackend.originator) -> URL {
        var components = URLComponents(url: authorizeURLBase, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = FormEncoding.encode([
            ("response_type", "code"),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("scope", scopes),
            ("code_challenge", codeChallenge),
            ("code_challenge_method", "S256"),
            ("id_token_add_organizations", "true"),
            ("codex_cli_simplified_flow", "true"),
            ("state", state),
            ("originator", originator),
        ])
        return components.url!
    }

    public static func authorizationCodeBody(code: String, codeVerifier: String, redirectURI: String = redirectURI) -> Data {
        Data(FormEncoding.encode([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", codeVerifier),
        ]).utf8)
    }

    public static func refreshBody(refreshToken: String) -> Data {
        jsonBody(["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    public static func revokeBody(refreshToken: String) -> Data {
        jsonBody(["token": refreshToken, "token_type_hint": "refresh_token", "client_id": clientID])
    }

    public static func deviceUserCodeBody() -> Data {
        jsonBody(["client_id": clientID])
    }

    public static func deviceTokenPollBody(deviceAuthID: String, userCode: String) -> Data {
        jsonBody(["device_auth_id": deviceAuthID, "user_code": userCode])
    }

    private static func jsonBody(_ object: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

/// Result of parsing the loopback redirect (`/auth/callback?code=…&state=…`).
public enum OAuthCallback: Equatable, Sendable {
    case code(String)
    case failure(String)

    /// Returns nil when the URL does not belong to the expected flow (state mismatch).
    public static func parse(query: String?, expectedState: String) -> OAuthCallback? {
        var components = URLComponents()
        components.percentEncodedQuery = query
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == expectedState else { return nil }
        if let code = value("code"), !code.isEmpty {
            return .code(code)
        }
        let message = value("error_description") ?? value("error") ?? "Authorization was not completed."
        return .failure(message)
    }
}

public struct OAuthTokenResponse: Equatable, Sendable {
    public var idToken: String?
    public var accessToken: String?
    public var refreshToken: String?

    public init(idToken: String?, accessToken: String?, refreshToken: String?) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public static func parse(_ data: Data) -> OAuthTokenResponse? {
        guard let object = JSONValue.object(data) else { return nil }
        let response = OAuthTokenResponse(
            idToken: JSONValue.string(object["id_token"]),
            accessToken: JSONValue.string(object["access_token"]),
            refreshToken: JSONValue.string(object["refresh_token"])
        )
        guard response.idToken != nil || response.accessToken != nil || response.refreshToken != nil else { return nil }
        return response
    }
}

public struct DeviceCodeChallenge: Equatable, Sendable {
    public var deviceAuthID: String
    public var userCode: String
    public var pollInterval: TimeInterval
    public var verificationURL: URL

    public init(deviceAuthID: String, userCode: String, pollInterval: TimeInterval, verificationURL: URL = OpenAIAuth.deviceVerificationURL) {
        self.deviceAuthID = deviceAuthID
        self.userCode = userCode
        self.pollInterval = pollInterval
        self.verificationURL = verificationURL
    }

    public static func parse(_ data: Data) -> DeviceCodeChallenge? {
        guard let object = JSONValue.object(data),
              let deviceAuthID = JSONValue.string(object["device_auth_id"]),
              let userCode = JSONValue.string(object["user_code"]) ?? JSONValue.string(object["usercode"])
        else { return nil }
        let interval = JSONValue.double(object["interval"]).map { max(1, $0) } ?? 5
        return DeviceCodeChallenge(deviceAuthID: deviceAuthID, userCode: userCode, pollInterval: interval)
    }
}

public struct DeviceCodeGrant: Equatable, Sendable {
    public var authorizationCode: String
    public var codeChallenge: String
    public var codeVerifier: String

    public static func parse(_ data: Data) -> DeviceCodeGrant? {
        guard let object = JSONValue.object(data),
              let code = JSONValue.string(object["authorization_code"]),
              let verifier = JSONValue.string(object["code_verifier"])
        else { return nil }
        return DeviceCodeGrant(
            authorizationCode: code,
            codeChallenge: JSONValue.string(object["code_challenge"]) ?? "",
            codeVerifier: verifier
        )
    }
}

/// Error body returned by the OAuth endpoints (`{"error": "..."}` or `{"error": {"code": ...}}`).
public struct OAuthErrorBody: Equatable, Sendable {
    public var code: String?
    public var message: String?

    public static func parse(_ data: Data) -> OAuthErrorBody {
        guard let object = JSONValue.object(data) else {
            let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return OAuthErrorBody(code: nil, message: text.isEmpty ? nil : text)
        }
        if let error = object["error"] as? [String: Any] {
            return OAuthErrorBody(
                code: JSONValue.string(error["code"]) ?? JSONValue.string(error["type"]),
                message: JSONValue.string(error["message"])
            )
        }
        return OAuthErrorBody(
            code: JSONValue.string(object["error"]) ?? JSONValue.string(object["code"]),
            message: JSONValue.string(object["error_description"]) ?? JSONValue.string(object["message"])
        )
    }

    /// True when the refresh token can never be used again and the user must sign in.
    public var isPermanentRefreshFailure: Bool {
        guard let code = code?.lowercased() else { return false }
        return ["invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"].contains(code)
    }
}

public enum FormEncoding {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    public static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }
}
