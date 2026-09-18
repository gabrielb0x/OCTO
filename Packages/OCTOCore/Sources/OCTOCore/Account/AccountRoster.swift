import Foundation

/// A ChatGPT account signed in on this device. Only what the account list needs to draw a row
/// before anything is downloaded; the tokens live in the keychain, under `key`.
public struct StoredAccount: Codable, Equatable, Sendable, Identifiable {
    /// Stable identifier of the account on this device: the name of its keychain item and of the
    /// folder holding its chats. Derived once from the account itself, so signing in again finds
    /// the same chats.
    public var key: String
    public var userID: String?
    public var accountID: String?
    public var email: String?
    public var name: String?
    public var planType: String?
    /// Where the account's profile picture lives, so the list can show it while another account
    /// is in use.
    public var pictureURL: URL?
    public var addedAt: Date
    public var lastUsedAt: Date

    public var id: String { key }

    public init(
        key: String,
        userID: String? = nil,
        accountID: String? = nil,
        email: String? = nil,
        name: String? = nil,
        planType: String? = nil,
        pictureURL: URL? = nil,
        addedAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.key = key
        self.userID = userID
        self.accountID = accountID
        self.email = email
        self.name = name
        self.planType = planType
        self.pictureURL = pictureURL
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
    }

    /// What the account list shows: the profile name, else the email address, else the plan.
    public var displayName: String {
        for candidate in [name, email] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return "ChatGPT"
    }
}

/// Turns a ChatGPT account into the name of its keychain item and of its folder.
public enum AccountKey {
    /// Characters kept as they are; everything else becomes "-". The identifiers ChatGPT hands out
    /// ("user-jVx2J6OrAoaK6OEsnCk8PyYy") already fit, and keeping their case keeps them distinct.
    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")

    /// The key of an account, from the most stable identifier it carries. Two sign-ins to the same
    /// account give the same key, so its chats and its tokens are found again.
    public static func make(userID: String?, accountID: String? = nil, email: String? = nil) -> String {
        for candidate in [userID, accountID, email] {
            guard let source = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { continue }
            let slug = self.slug(source)
            if !slug.isEmpty { return slug }
        }
        return "account-\(UUID().uuidString.lowercased())"
    }

    /// A single path and keychain component: no slash, no dot-dot, no surprise.
    static func slug(_ source: String) -> String {
        var result = ""
        var lastWasDash = false
        for character in source.prefix(120) {
            if allowed.contains(character) {
                result.append(character)
                lastWasDash = character == "-"
            } else if !lastWasDash, !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        // "." and ".." would point at a folder that isn't the account's own.
        return result == "." || result == ".." ? "" : String(result.prefix(64))
    }
}

/// The ChatGPT accounts signed in on this device and the one in use. Saved outside the keychain:
/// it holds no token, only what the account list shows.
public struct AccountRoster: Codable, Equatable, Sendable {
    public private(set) var accounts: [StoredAccount]
    public private(set) var currentKey: String?

    public init(accounts: [StoredAccount] = [], currentKey: String? = nil) {
        self.accounts = accounts
        self.currentKey = accounts.contains { $0.key == currentKey } ? currentKey : accounts.first?.key
    }

    public var current: StoredAccount? {
        accounts.first { $0.key == currentKey }
    }

    public var isEmpty: Bool { accounts.isEmpty }

    /// The accounts in the order they were added, so the list doesn't reshuffle as you switch.
    public var ordered: [StoredAccount] {
        accounts.sorted { $0.addedAt < $1.addedAt }
    }

    public func contains(_ key: String) -> Bool {
        accounts.contains { $0.key == key }
    }

    /// Adds an account, or updates the one already signed in with the same key, and makes it
    /// the current one. Signing in again to an account keeps the day it was added.
    public mutating func add(_ account: StoredAccount) {
        var account = account
        if let index = accounts.firstIndex(where: { $0.key == account.key }) {
            account.addedAt = accounts[index].addedAt
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        currentKey = account.key
    }

    /// Switches to an account already signed in. False when it isn't one.
    @discardableResult
    public mutating func select(_ key: String, at date: Date = Date()) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.key == key }) else { return false }
        accounts[index].lastUsedAt = date
        currentKey = key
        return true
    }

    /// Updates what the list shows about an account, without touching the current one.
    public mutating func update(_ key: String, email: String?, name: String?, planType: String?) {
        guard let index = accounts.firstIndex(where: { $0.key == key }) else { return }
        if let email, !email.isEmpty { accounts[index].email = email }
        if let name, !name.isEmpty { accounts[index].name = name }
        if let planType, !planType.isEmpty { accounts[index].planType = planType }
    }

    /// Remembers where an account's profile picture lives, or that it has none.
    public mutating func setPicture(_ url: URL?, for key: String) {
        guard let index = accounts.firstIndex(where: { $0.key == key }) else { return }
        accounts[index].pictureURL = url
    }

    /// Signs one account out. The one used most recently takes its place when it was the current
    /// one; nil means no account is left and the sign-in screen comes back.
    @discardableResult
    public mutating func remove(_ key: String) -> String? {
        accounts.removeAll { $0.key == key }
        guard currentKey == key else { return currentKey }
        currentKey = accounts.sorted { $0.lastUsedAt > $1.lastUsedAt }.first?.key
        return currentKey
    }

    public mutating func removeAll() {
        accounts = []
        currentKey = nil
    }
}
