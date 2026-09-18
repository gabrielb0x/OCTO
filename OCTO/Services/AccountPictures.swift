import Foundation
import Observation
import OCTOCore
import UIKit

/// The profile pictures of the other accounts signed in on this device, for the account list.
/// The account in use has its own, kept by `AccountStore`. The others first show the picture their
/// folder kept from the last time they were used, then download it again once a day: straight from
/// where it lives, with no token at all, or — for a picture hosted on chatgpt.com — with that
/// account's own session. These requests go through a session of their own that keeps no cookie,
/// so nothing the account in use received ties the two accounts together.
@MainActor
@Observable
final class AccountPictures {
    private(set) var images: [String: UIImage] = [:]

    @ObservationIgnored private let isDemo: Bool
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var checkedAt: [String: Date] = [:]

    init(isDemo: Bool) {
        self.isDemo = isDemo
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    func image(for key: String) -> UIImage? {
        images[key]
    }

    /// Shows the pictures kept in the folders of the accounts not in use, then downloads again
    /// those that haven't been for a day.
    func refresh(_ accounts: [StoredAccount], except currentKey: String?) async {
        guard !isDemo else { return }
        let others = accounts.filter { $0.key != currentKey }
        for account in others where images[account.key] == nil {
            if let data = Self.cache(for: account.key).loadAvatar(), let image = UIImage(data: data) {
                images[account.key] = image
            }
        }
        for account in others {
            await download(account)
        }
    }

    /// Forgets the picture of an account signed out of this device.
    func forget(_ key: String) {
        images[key] = nil
        checkedAt[key] = nil
    }

    #if OCTO_DEMO
    func useDemo(_ pictures: [String: UIImage]) {
        images = pictures
    }
    #endif

    // MARK: Private

    private func download(_ account: StoredAccount) async {
        let key = account.key
        let cache = Self.cache(for: key)
        if let checked = checkedAt[key], Date().timeIntervalSince(checked) < 3_600 { return }
        if images[key] != nil, let saved = cache.avatarSavedAt, Date().timeIntervalSince(saved) < 86_400 { return }
        checkedAt[key] = Date()

        let credentials = Self.usableCredentials(for: key)
        var address = account.pictureURL
        if address == nil, let snapshot = cache.loadSnapshot() {
            // A profile read without a picture: there's nothing to download.
            if let profile = snapshot.profile, profile.pictureURL == nil, snapshot.avatarURL == nil { return }
            address = snapshot.avatarURL ?? snapshot.profile?.pictureURL
        }
        if address == nil, let credentials {
            address = await pictureAddress(with: credentials)
        }
        guard let address,
              let data = await imageData(at: address, credentials: credentials),
              let image = UIImage(data: data)
        else { return }
        images[key] = image
        cache.saveAvatar(data)
        DevLog.log("account", "Loaded the picture of another account signed in on this device")
    }

    /// That account's own tokens, while its access token is still valid. They're never refreshed
    /// from here: refreshing an account that isn't in use could race its own refresh when you
    /// switch to it, and a refresh token used twice signs the account out.
    private static func usableCredentials(for key: String) -> StoredChatGPTCredentials? {
        guard let credentials = Keychain.value(StoredChatGPTCredentials.self, for: CredentialVault.keychainAccount(for: key)),
              let expiresAt = JWT.expirationDate(of: credentials.accessToken),
              expiresAt.timeIntervalSinceNow > 120
        else { return nil }
        return credentials
    }

    /// Where the account's picture lives, read from its profile (`GET /me`) with its own session.
    private func pictureAddress(with credentials: StoredChatGPTCredentials) async -> URL? {
        var request = URLRequest(url: ChatGPTAccountAPI.profileURL)
        request.timeoutInterval = 30
        for (name, value) in Self.headers(credentials) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await session.recordedData(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return AccountProfile.parse(data)?.pictureURL
        } catch {
            return nil
        }
    }

    /// A picture hosted outside chatgpt.com never gets a token; one on chatgpt.com gets the
    /// session of the account it belongs to, never the one in use.
    private func imageData(at url: URL, credentials: StoredChatGPTCredentials?) async -> Data? {
        guard url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let host = url.host?.lowercased() ?? ""
        if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") {
            guard let credentials else { return nil }
            for (name, value) in Self.headers(credentials) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.setValue("image/*", forHTTPHeaderField: "Accept")
        }
        do {
            let (data, response) = try await session.recordedData(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func headers(_ credentials: StoredChatGPTCredentials) -> [String: String] {
        ChatGPTAccountAPI.headers(
            accessToken: credentials.accessToken,
            accountID: credentials.accountID,
            userAgent: AppInfo.userAgent,
            language: AppInfo.languageTag
        )
    }

    private static func cache(for key: String) -> AccountCache {
        AccountCache(directory: AccountStorage.directory(forAccount: key))
    }
}
