import AuthenticationServices
import Foundation
import Observation
import OCTOCore
import UIKit

struct Account: Equatable, Sendable {
    var email: String?
    var planType: String?
    var userID: String?
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

/// Owns the ChatGPT credentials of the account in use and refreshes them, coalescing concurrent
/// refreshes. Each account has its own keychain item, so signing into a second one leaves the
/// first one's tokens untouched; switching accounts points the vault at another item.
actor CredentialVault {
    struct Credential: Sendable {
        let accessToken: String
        let accountID: String?
    }

    /// The current session, for Settings and the developer tools.
    struct SessionInfo: Sendable {
        let idToken: String
        let accessToken: String
        let accountID: String?
        let lastRefresh: Date
        let accessTokenExpiresAt: Date?
    }

    /// Written by OCTO 1.8 and earlier, which knew a single account.
    static let legacyAccount = "chatgpt.credentials"
    /// Written by OCTO 1.0 when signed in with an OpenAI API key, which is no longer offered.
    static let legacyAPIKeyAccount = "openai.apikey"

    /// The keychain item holding one account's tokens.
    static func keychainAccount(for key: String) -> String {
        "chatgpt.credentials.\(key)"
    }

    private let session: URLSession
    /// The keychain item in use; nil when no account is signed in.
    private var keychainAccount: String?
    private var chatGPT: StoredChatGPTCredentials?
    private var refreshTask: Task<StoredChatGPTCredentials, Error>?

    init(session: URLSession, accountKey: String?) {
        self.session = session
        if let accountKey {
            let item = Self.keychainAccount(for: accountKey)
            keychainAccount = item
            chatGPT = Keychain.value(StoredChatGPTCredentials.self, for: item)
        }
    }

    /// Switches to another account's tokens, or to none at all.
    func use(accountKey: String?) {
        refreshTask?.cancel()
        refreshTask = nil
        guard let accountKey else {
            keychainAccount = nil
            chatGPT = nil
            return
        }
        let item = Self.keychainAccount(for: accountKey)
        keychainAccount = item
        chatGPT = Keychain.value(StoredChatGPTCredentials.self, for: item)
    }

    func credential(forceRefresh: Bool = false) async throws -> Credential {
        guard let current = chatGPT else { throw AuthError.notSignedIn }

        let expiresAt = JWT.expirationDate(of: current.accessToken)
        let expiresSoon = expiresAt.map { $0.timeIntervalSinceNow < 5 * 60 } ?? false
        let isStale = Date().timeIntervalSince(current.lastRefresh) > 7 * 24 * 3600
        guard forceRefresh || expiresSoon || isStale else {
            return Credential(accessToken: current.accessToken, accountID: current.accountID)
        }
        let refreshed = try await refresh()
        return Credential(accessToken: refreshed.accessToken, accountID: refreshed.accountID)
    }

    func store(_ credentials: StoredChatGPTCredentials) {
        guard let keychainAccount else { return }
        chatGPT = credentials
        Keychain.setValue(credentials, for: keychainAccount)
    }

    /// Clears the account in use and returns its refresh token so it can be revoked.
    func clear() -> String? {
        let refreshToken = chatGPT?.refreshToken
        refreshTask?.cancel()
        refreshTask = nil
        chatGPT = nil
        if let keychainAccount {
            Keychain.remove(keychainAccount)
        }
        keychainAccount = nil
        return refreshToken
    }

    func sessionInfo() -> SessionInfo? {
        guard let current = chatGPT else { return nil }
        return SessionInfo(
            idToken: current.idToken,
            accessToken: current.accessToken,
            accountID: current.accountID,
            lastRefresh: current.lastRefresh,
            accessTokenExpiresAt: JWT.expirationDate(of: current.accessToken)
        )
    }

    /// Makes the next request refresh the tokens, to try the refresh from the developer tools.
    func markStale() {
        guard var current = chatGPT, let keychainAccount else { return }
        current.lastRefresh = .distantPast
        chatGPT = current
        Keychain.setValue(current, for: keychainAccount)
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
            // The account may have been switched or signed out while the refresh was in flight:
            // the answer then belongs to an account that is no longer the one in use.
            if chatGPT != nil, let keychainAccount {
                chatGPT = updated
                Keychain.setValue(updated, for: keychainAccount)
            }
            DevLog.log("auth", "Tokens refreshed")
            return updated
        } catch AuthError.sessionExpired {
            DevLog.log("auth", "Refresh token refused: session expired", level: .error)
            if let keychainAccount {
                Keychain.remove(keychainAccount)
            }
            chatGPT = nil
            throw AuthError.sessionExpired
        }
    }

    private static func performRefresh(_ credentials: StoredChatGPTCredentials, session: URLSession) async throws -> StoredChatGPTCredentials {
        var request = URLRequest(url: OpenAIAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.refreshBody(refreshToken: credentials.refreshToken)

        let (data, response) = try await session.recordedData(for: request)
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

    enum SignInMethod: String {
        case browser
        case deviceCode
    }

    private(set) var state: State
    /// The ChatGPT accounts signed in on this device, and which one is in use.
    private(set) var roster: AccountRoster

    let vault: CredentialVault
    private let session: URLSession
    private let anchorProvider = PresentationAnchorProvider()

    private static let rosterKey = "auth.accounts"
    private static let legacySignInMethodKey = "auth.signInMethod"
    private static let legacySignedInAtKey = "auth.signedInAt"

    init(session: URLSession) {
        self.session = session
        // Signing in with an API key was removed: forget a key saved by an earlier version.
        Keychain.remove(CredentialVault.legacyAPIKeyAccount)

        let roster = Self.loadRoster()
        self.roster = roster
        vault = CredentialVault(session: session, accountKey: roster.currentKey)

        if let key = roster.currentKey,
           let credentials = Keychain.value(StoredChatGPTCredentials.self, for: CredentialVault.keychainAccount(for: key)) {
            state = .signedIn(Self.account(idToken: credentials.idToken, accessToken: credentials.accessToken))
        } else {
            state = .signedOut
        }
    }

    var account: Account? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    /// The accounts signed in on this device, in the order they were added.
    var accounts: [StoredAccount] { roster.ordered }

    var currentAccountKey: String? { roster.currentKey }

    var hasSeveralAccounts: Bool { roster.accounts.count > 1 }

    var signInMethod: SignInMethod? {
        guard let key = roster.currentKey else { return nil }
        return UserDefaults.standard.string(forKey: Self.signInMethodKey(key)).flatMap(SignInMethod.init(rawValue:))
    }

    var signedInAt: Date? {
        guard let key = roster.currentKey else { return nil }
        return UserDefaults.standard.object(forKey: Self.signedInAtKey(key)) as? Date
    }

    /// Refreshes the tokens now and picks up changes to the account they carry, such as a new plan.
    func refreshSession() async throws {
        do {
            _ = try await vault.credential(forceRefresh: true)
        } catch AuthError.sessionExpired {
            state = .signedOut
            throw AuthError.sessionExpired
        }
        if let info = await vault.sessionInfo() {
            let account = Self.account(idToken: info.idToken, accessToken: info.accessToken)
            state = .signedIn(account)
            describe(account)
        }
    }

    /// Keeps the account list in step with what the account itself says about it.
    func describe(_ account: Account, name: String? = nil) {
        guard let key = roster.currentKey else { return }
        roster.update(key, email: account.email, name: name, planType: account.planType)
        saveRoster()
    }

    /// Remembers where the picture of the account in use lives, so the account list can show it
    /// once another account is in use. Nil means the profile has no picture.
    func rememberPicture(_ url: URL?) {
        guard let key = roster.currentKey, roster.current?.pictureURL != url else { return }
        roster.setPicture(url, for: key)
        saveRoster()
    }

    #if OCTO_DEMO
    /// Screenshot builds show a fake account without touching the keychain.
    func useDemoAccount(_ account: Account?) {
        state = account.map { .signedIn($0) } ?? .signedOut
    }

    /// A few accounts for the account-switching screenshot.
    func useDemoAccounts(_ demoAccounts: [StoredAccount]) {
        var roster = AccountRoster()
        for account in demoAccounts {
            roster.add(account)
        }
        if let first = demoAccounts.first {
            roster.select(first.key)
        }
        self.roster = roster
    }
    #endif

    // MARK: Browser sign-in

    /// Signs in with ChatGPT. When another account is being added, the sign-in page opens without
    /// the Safari cookies of the account already signed in — otherwise ChatGPT would hand back the
    /// same account without ever asking which one you meant.
    func signInWithChatGPT(addingAccount: Bool = false) async throws {
        let pkce = PKCE.generate()
        let expectedState = PKCE.randomState()
        let url = OpenAIAuth.authorizeURL(codeChallenge: pkce.challenge, state: expectedState)
        let code = try await authorize(url: url, expectedState: expectedState, ephemeral: addingAccount)
        let tokens = try await exchange(code: code, verifier: pkce.verifier, redirectURI: OpenAIAuth.redirectURI)
        await complete(with: tokens, method: .browser)
    }

    private func authorize(url: URL, expectedState: String, ephemeral: Bool) async throws -> String {
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
            webSession.prefersEphemeralWebBrowserSession = ephemeral
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

        let (data, response) = try await session.recordedData(for: request)
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

            let (data, response) = try await session.recordedData(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), let grant = DeviceCodeGrant.parse(data) {
                let tokens = try await exchange(code: grant.authorizationCode, verifier: grant.codeVerifier, redirectURI: OpenAIAuth.deviceRedirectURI)
                await complete(with: tokens, method: .deviceCode)
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

    // MARK: Accounts

    /// Switches to another account already signed in on this device. False when it isn't one, or
    /// when it is already the one in use.
    @discardableResult
    func switchAccount(to key: String) async -> Bool {
        guard key != roster.currentKey, roster.contains(key) else { return false }
        guard Keychain.value(StoredChatGPTCredentials.self, for: CredentialVault.keychainAccount(for: key)) != nil else {
            // Its tokens are gone from the keychain: the account can't be used, so it leaves the list.
            DevLog.log("auth", "No tokens left for \(key): removing it from the account list", level: .warning)
            roster.remove(key)
            saveRoster()
            return false
        }
        roster.select(key)
        saveRoster()
        await vault.use(accountKey: key)
        if let info = await vault.sessionInfo() {
            state = .signedIn(Self.account(idToken: info.idToken, accessToken: info.accessToken))
        }
        DevLog.log("auth", "Switched to \(key)")
        return true
    }

    /// Signs one account out and revokes its session. Without a key it is the account in use.
    /// Returns the account now in use, or nil when that was the last one.
    @discardableResult
    func signOut(accountKey: String? = nil) async -> String? {
        guard let key = accountKey ?? roster.currentKey else { return nil }
        let isCurrent = key == roster.currentKey
        let refreshToken: String?
        if isCurrent {
            refreshToken = await vault.clear()
        } else {
            let item = CredentialVault.keychainAccount(for: key)
            refreshToken = Keychain.value(StoredChatGPTCredentials.self, for: item)?.refreshToken
            Keychain.remove(item)
        }
        UserDefaults.standard.removeObject(forKey: Self.signInMethodKey(key))
        UserDefaults.standard.removeObject(forKey: Self.signedInAtKey(key))

        let next = roster.remove(key)
        saveRoster()
        if isCurrent {
            await vault.use(accountKey: next)
            if let info = await vault.sessionInfo() {
                state = .signedIn(Self.account(idToken: info.idToken, accessToken: info.accessToken))
            } else {
                state = .signedOut
            }
        }
        DevLog.log("auth", "Signed \(key) out")
        await revoke(refreshToken)
        return next
    }

    /// Best effort: makes the refresh token unusable so the session can't be resumed.
    private func revoke(_ refreshToken: String?) async {
        guard let refreshToken else { return }
        var request = URLRequest(url: OpenAIAuth.revokeURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.revokeBody(refreshToken: refreshToken)
        _ = try? await session.recordedData(for: request)
    }

    // MARK: Private

    private func exchange(code: String, verifier: String, redirectURI: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: OpenAIAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = OpenAIAuth.authorizationCodeBody(code: code, codeVerifier: verifier, redirectURI: redirectURI)

        let (data, response) = try await session.recordedData(for: request)
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

    /// Files the tokens under the account they belong to, and makes it the account in use.
    /// Signing into an account already on this device updates it instead of adding it twice.
    private func complete(with tokens: OAuthTokenResponse, method: SignInMethod) async {
        guard let accessToken = tokens.accessToken, let refreshToken = tokens.refreshToken else { return }
        let idToken = tokens.idToken ?? ""
        let claims = ChatGPTAccountClaims(idToken: idToken, accessToken: accessToken)
        let key = AccountKey.make(userID: claims.userID, accountID: claims.accountID, email: claims.email)
        let credentials = StoredChatGPTCredentials(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountID: claims.accountID,
            lastRefresh: Date()
        )
        Keychain.setValue(credentials, for: CredentialVault.keychainAccount(for: key))
        await vault.use(accountKey: key)
        UserDefaults.standard.set(method.rawValue, forKey: Self.signInMethodKey(key))
        UserDefaults.standard.set(Date(), forKey: Self.signedInAtKey(key))
        roster.add(StoredAccount(
            key: key,
            userID: claims.userID,
            accountID: claims.accountID,
            email: claims.email,
            planType: claims.planType
        ))
        saveRoster()
        state = .signedIn(Account(email: claims.email, planType: claims.planType, userID: claims.userID))
    }

    private static func signInMethodKey(_ key: String) -> String { "auth.signInMethod.\(key)" }
    private static func signedInAtKey(_ key: String) -> String { "auth.signedInAt.\(key)" }

    private func saveRoster() {
        guard let data = try? JSONEncoder().encode(roster) else { return }
        UserDefaults.standard.set(data, forKey: Self.rosterKey)
    }

    /// The account list, or the single account of OCTO 1.8 and earlier moved into it.
    private static func loadRoster(defaults: UserDefaults = .standard) -> AccountRoster {
        if let data = defaults.data(forKey: rosterKey),
           let roster = try? JSONDecoder().decode(AccountRoster.self, from: data) {
            return roster
        }
        guard let legacy = Keychain.value(StoredChatGPTCredentials.self, for: CredentialVault.legacyAccount) else {
            return AccountRoster()
        }
        let claims = ChatGPTAccountClaims(idToken: legacy.idToken, accessToken: legacy.accessToken)
        let key = AccountKey.make(userID: claims.userID, accountID: claims.accountID, email: claims.email)
        // Its tokens, its chats and how it signed in move to the account's own place.
        Keychain.setValue(legacy, for: CredentialVault.keychainAccount(for: key))
        Keychain.remove(CredentialVault.legacyAccount)
        AccountStorage.migrateLegacyLayout(to: key)
        if let method = defaults.string(forKey: legacySignInMethodKey) {
            defaults.set(method, forKey: signInMethodKey(key))
            defaults.removeObject(forKey: legacySignInMethodKey)
        }
        if let date = defaults.object(forKey: legacySignedInAtKey) as? Date {
            defaults.set(date, forKey: signedInAtKey(key))
            defaults.removeObject(forKey: legacySignedInAtKey)
        }

        var roster = AccountRoster()
        roster.add(StoredAccount(
            key: key,
            userID: claims.userID,
            accountID: claims.accountID,
            email: claims.email,
            planType: claims.planType
        ))
        if let data = try? JSONEncoder().encode(roster) {
            defaults.set(data, forKey: rosterKey)
        }
        DevLog.log("auth", "Moved the account signed in before 1.9 into the account list")
        return roster
    }

    /// Forgets every account, for a fresh install.
    static func forgetEverything(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: rosterKey)
        defaults.removeObject(forKey: legacySignInMethodKey)
        defaults.removeObject(forKey: legacySignedInAtKey)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("auth.signInMethod.") || key.hasPrefix("auth.signedInAt.") {
            defaults.removeObject(forKey: key)
        }
        Keychain.removeAll()
    }

    private static func account(idToken: String?, accessToken: String?) -> Account {
        let claims = ChatGPTAccountClaims(idToken: idToken, accessToken: accessToken)
        return Account(email: claims.email, planType: claims.planType, userID: claims.userID)
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
        let windows = scenes.flatMap(\.windows).filter { $0.windowLevel == .normal }
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        return ASPresentationAnchor(windowScene: scenes[0])
    }
}
