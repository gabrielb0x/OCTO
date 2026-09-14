import AuthenticationServices
import Foundation
import Observation
import OCTOCore
import UIKit

enum AuthMethod: String, Codable, Sendable {
    case chatGPT
    case apiKey
}

struct Account: Equatable, Sendable {
    var method: AuthMethod
    var email: String?
    var planType: String?
}

struct StoredChatGPTCredentials: Codable, Equatable, Sendable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var accountID: String?
    var lastRefresh: Date
}

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case notSignedIn
    case sessionExpired
    case invalidAPIKey
    case loopbackUnavailable
    case deviceCodeUnavailable
    case deviceCodeExpired
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "Sign-in was cancelled.")
        case .notSignedIn:
            return String(localized: "You are not signed in.")
        case .sessionExpired:
            return String(localized: "Your session has expired. Please sign in again.")
        case .invalidAPIKey:
            return String(localized: "This API key was rejected by OpenAI.")
        case .loopbackUnavailable:
            return String(localized: "OCTO could not receive the sign-in response. Try signing in with a code instead.")
        case .deviceCodeUnavailable:
            return String(localized: "Sign-in with a code is not available right now.")
        case .deviceCodeExpired:
            return String(localized: "The code expired. Request a new one.")
        case .authorizationFailed(let message), .tokenExchangeFailed(let message), .network(let message):
            return message
        }
    }
}

/// Owns the credentials and refreshes ChatGPT tokens, coalescing concurrent refreshes.
actor CredentialVault {
    enum Credential: Sendable {
        case chatGPT(accessToken: String, accountID: String?)
        case apiKey(String)
    }

    static let chatGPTAccount = "chatgpt.credentials"
    static let apiKeyAccount = "openai.apikey"

    private let session: URLSession
    private var chatGPT: StoredChatGPTCredentials?
    private var apiKey: String?
    private var refreshTask: Task<StoredChatGPTCredentials, Error>?

    init(session: URLSession) {
        self.session = session
        chatGPT = Keychain.value(StoredChatGPTCredentials.self, for: Self.chatGPTAccount)
        apiKey = Keychain.data(for: Self.apiKeyAccount).map { String(decoding: $0, as: UTF8.self) }
    }

    func credential(forceRefresh: Bool = false) async throws -> Credential {
        if let apiKey {
            return .apiKey(apiKey)
        }
        guard let current = chatGPT else { throw AuthError.notSignedIn }

        let expiresAt = JWT.expirationDate(of: current.accessToken)
        let expiresSoon = expiresAt.map { $0.timeIntervalSinceNow < 5 * 60 } ?? false
        let isStale = Date().timeIntervalSince(current.lastRefresh) > 7 * 24 * 3600
        guard forceRefresh || expiresSoon || isStale else {
            return .chatGPT(accessToken: current.accessToken, accountID: current.accountID)
        }
        let refreshed = try await refresh()
        return .chatGPT(accessToken: refreshed.accessToken, accountID: refreshed.accountID)
    }

    func storeChatGPT(_ credentials: StoredChatGPTCredentials) {
        chatGPT = credentials
        apiKey = nil
        Keychain.remove(Self.apiKeyAccount)
        Keychain.setValue(credentials, for: Self.chatGPTAccount)
    }

    func storeAPIKey(_ key: String) {
        apiKey = key
        chatGPT = nil
        Keychain.remove(Self.chatGPTAccount)
        Keychain.set(Data(key.utf8), for: Self.apiKeyAccount)
    }

    /// Clears everything and returns the refresh token so it can be revoked.
    func clear() -> String? {
        let refreshToken = chatGPT?.refreshToken
        refreshTask?.cancel()
        refreshTask = nil
        chatGPT = nil
        apiKey = nil
        Keychain.remove(Self.chatGPTAccount)
        Keychain.remove(Self.apiKeyAccount)
        return refreshToken
    }

    private func refresh() async throws -> StoredChatGPTCredentials {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = chatGPT else { throw AuthError.notSignedIn }
        let session = self.session
        let task = Task { try await Self.performRefresh(current, session: session) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let updated = try await task.value
            if chatGPT != nil {
                chatGPT = updated
                Keychain.setValue(updated, for: Self.chatGPTAccount)
            }
            return updated
        } catch AuthError.sessionExpired {
            chatGPT = nil
            Keychain.remove(Self.chatGPTAccount)
            throw AuthError.sessionExpired
        }
    }

    private static func performRefresh(_ credentials: StoredChatGPTCredentials, session: URLSession) async throws -> StoredChatGPTCredentials {
        var request = URLRequest(url: OpenAIAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.refreshBody(refreshToken: credentials.refreshToken)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = OAuthErrorBody.parse(data)
            if status == 401 || error.isPermanentRefreshFailure {
                throw AuthError.sessionExpired
            }
            throw AuthError.network(error.message ?? String(localized: "Could not refresh your session (HTTP \(status))."))
        }
        guard let tokens = OAuthTokenResponse.parse(data), let accessToken = tokens.accessToken else {
            throw AuthError.network(String(localized: "OpenAI returned an unexpected response."))
        }

        var updated = credentials
        updated.accessToken = accessToken
        if let idToken = tokens.idToken { updated.idToken = idToken }
        if let refreshToken = tokens.refreshToken { updated.refreshToken = refreshToken }
        updated.accountID = ChatGPTAccountClaims(idToken: updated.idToken, accessToken: accessToken).accountID ?? credentials.accountID
        updated.lastRefresh = Date()
        return updated
    }
}

@MainActor
@Observable
final class AuthManager {
    enum State: Equatable {
        case signedOut
        case signedIn(Account)
    }

    private(set) var state: State

    let vault: CredentialVault
    private let session: URLSession
    private let anchorProvider = PresentationAnchorProvider()

    init(session: URLSession) {
        self.session = session
        vault = CredentialVault(session: session)

        if let credentials = Keychain.value(StoredChatGPTCredentials.self, for: CredentialVault.chatGPTAccount) {
            let claims = ChatGPTAccountClaims(idToken: credentials.idToken, accessToken: credentials.accessToken)
            state = .signedIn(Account(method: .chatGPT, email: claims.email, planType: claims.planType))
        } else if Keychain.data(for: CredentialVault.apiKeyAccount) != nil {
            state = .signedIn(Account(method: .apiKey))
        } else {
            state = .signedOut
        }
    }

    var account: Account? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    #if OCTO_DEMO
    /// Screenshot builds show a fake account without touching the keychain.
    func useDemoAccount(_ account: Account?) {
        state = account.map { .signedIn($0) } ?? .signedOut
    }
    #endif

    // MARK: Browser sign-in

    func signInWithChatGPT() async throws {
        let pkce = PKCE.generate()
        let expectedState = PKCE.randomState()
        let url = OpenAIAuth.authorizeURL(codeChallenge: pkce.challenge, state: expectedState)
        let code = try await authorize(url: url, expectedState: expectedState)
        let tokens = try await exchange(code: code, verifier: pkce.verifier, redirectURI: OpenAIAuth.redirectURI)
        await complete(with: tokens)
    }

    private func authorize(url: URL, expectedState: String) async throws -> String {
        let server = LoopbackCallbackServer()
        let sessionBox = WebAuthenticationSessionBox()
        defer { server.stop() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let resumer = OnceResumer(continuation)
            let handleQuery: @MainActor (String?) -> Void = { query in
                switch OAuthCallback.parse(query: query, expectedState: expectedState) {
                case .code(let code)?:
                    resumer.resume(returning: code)
                case .failure(let message)?:
                    resumer.resume(throwing: AuthError.authorizationFailed(message))
                case nil:
                    break
                }
            }

            do {
                try server.start(
                    port: OpenAIAuth.loopbackPort,
                    path: OpenAIAuth.callbackPath,
                    onCallback: { query in
                        Task { @MainActor in
                            handleQuery(query)
                            // The sheet normally closes itself by following the octo:// redirect;
                            // close it anyway once the code has arrived.
                            try? await Task.sleep(for: .seconds(1))
                            sessionBox.session?.cancel()
                        }
                    },
                    onFailure: {
                        Task { @MainActor in
                            resumer.resume(throwing: AuthError.loopbackUnavailable)
                            sessionBox.session?.cancel()
                        }
                    }
                )
            } catch {
                resumer.resume(throwing: AuthError.loopbackUnavailable)
                return
            }

            let webSession = ASWebAuthenticationSession(url: url, callback: .customScheme("octo")) { callbackURL, error in
                Task { @MainActor in
                    if let callbackURL {
                        handleQuery(URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        resumer.resume(throwing: AuthError.cancelled)
                    } else if let error {
                        resumer.resume(throwing: AuthError.authorizationFailed(error.localizedDescription))
                    }
                }
            }
            webSession.presentationContextProvider = anchorProvider
            webSession.prefersEphemeralWebBrowserSession = false
            sessionBox.session = webSession
            if !webSession.start() {
                resumer.resume(throwing: AuthError.authorizationFailed(String(localized: "Could not open the sign-in page.")))
            }
        }
    }

    /// Keeps the web session alive for the whole flow so it can be closed once the code arrives.
    @MainActor
    private final class WebAuthenticationSessionBox {
        var session: ASWebAuthenticationSession?
    }

    // MARK: Device code sign-in

    func requestDeviceCode() async throws -> DeviceCodeChallenge {
        var request = URLRequest(url: OpenAIAuth.deviceUserCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.deviceUserCodeBody()

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let challenge = DeviceCodeChallenge.parse(data) else {
            if status == 404 { throw AuthError.deviceCodeUnavailable }
            throw AuthError.authorizationFailed(OAuthErrorBody.parse(data).message ?? String(localized: "Could not get a sign-in code (HTTP \(status))."))
        }
        return challenge
    }

    func completeDeviceCode(_ challenge: DeviceCodeChallenge) async throws {
        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            try Task.checkCancellation()
            var request = URLRequest(url: OpenAIAuth.deviceTokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = OpenAIAuth.deviceTokenPollBody(deviceAuthID: challenge.deviceAuthID, userCode: challenge.userCode)

            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), let grant = DeviceCodeGrant.parse(data) {
                let tokens = try await exchange(code: grant.authorizationCode, verifier: grant.codeVerifier, redirectURI: OpenAIAuth.deviceRedirectURI)
                await complete(with: tokens)
                return
            }
            if status == 403 || status == 404 {
                try await Task.sleep(for: .seconds(challenge.pollInterval))
                continue
            }
            throw AuthError.authorizationFailed(OAuthErrorBody.parse(data).message ?? String(localized: "Sign-in failed (HTTP \(status))."))
        }
        throw AuthError.deviceCodeExpired
    }

    // MARK: API key

    func signIn(apiKey rawKey: String) async throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AuthError.invalidAPIKey }

        var request = URLRequest(url: OpenAIPlatform.modelsURL)
        for (name, value) in OpenAIPlatform.headers(apiKey: key, userAgent: AppInfo.userAgent) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw AuthError.invalidAPIKey }
        guard (200..<300).contains(status) else {
            throw AuthError.network(APIErrorPayload.parse(data).message ?? String(localized: "OpenAI could not be reached (HTTP \(status))."))
        }
        await vault.storeAPIKey(key)
        state = .signedIn(Account(method: .apiKey))
    }

    // MARK: Session

    func signOut() async {
        let refreshToken = await vault.clear()
        state = .signedOut
        guard let refreshToken else { return }
        // Best effort: revoke the refresh token so it cannot be reused.
        var request = URLRequest(url: OpenAIAuth.revokeURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.revokeBody(refreshToken: refreshToken)
        _ = try? await session.data(for: request)
    }

    private func exchange(code: String, verifier: String, redirectURI: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: OpenAIAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.authorizationCodeBody(code: code, codeVerifier: verifier, redirectURI: redirectURI)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let tokens = OAuthTokenResponse.parse(data),
              tokens.accessToken != nil,
              tokens.refreshToken != nil
        else {
            throw AuthError.tokenExchangeFailed(OAuthErrorBody.parse(data).message ?? String(localized: "Sign-in failed (HTTP \(status))."))
        }
        return tokens
    }

    private func complete(with tokens: OAuthTokenResponse) async {
        guard let accessToken = tokens.accessToken, let refreshToken = tokens.refreshToken else { return }
        let idToken = tokens.idToken ?? ""
        let claims = ChatGPTAccountClaims(idToken: idToken, accessToken: accessToken)
        await vault.storeChatGPT(StoredChatGPTCredentials(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountID: claims.accountID,
            lastRefresh: Date()
        ))
        state = .signedIn(Account(method: .chatGPT, email: claims.email, planType: claims.planType))
    }
}

/// Resumes a checked continuation at most once, from any thread.
final class OnceResumer<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let current = continuation
        continuation = nil
        return current
    }
}

final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        return ASPresentationAnchor(windowScene: scenes[0])
    }
}
