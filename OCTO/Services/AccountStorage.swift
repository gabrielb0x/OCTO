import Foundation
import OCTOCore

/// Where each signed-in ChatGPT account keeps its chats and its cached account data.
///
/// Every account gets its own folder, so switching accounts never mixes two histories:
///
///     Application Support/OCTO/Accounts/<account key>/{Conversations, Attachments, Account}
///
/// OCTO before 1.9 knew one account and kept those three folders directly under `OCTO/`.
/// The first launch after updating moves them into the folder of the account that was signed in.
enum AccountStorage {
    static let folderName = "OCTO"

    /// `Application Support/OCTO`, holding every account's folder.
    static func root(folderName: String = AccountStorage.folderName) -> URL {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The folder of one account. Without an account — signed out — the root is used, where
    /// nothing is written until someone signs in.
    static func directory(forAccount key: String?, folderName: String = AccountStorage.folderName) -> URL {
        let root = root(folderName: folderName)
        guard let key, !key.isEmpty else { return root }
        return root
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    /// The folders the chats and the account cache live in, under an account's folder.
    private static let contents = ["Conversations", "Attachments", "Account"]

    /// Moves the layout of OCTO 1.8 and earlier into the folder of `key`, once. Returns whether
    /// anything moved. Best effort: a folder that can't be moved is left where it is, and the
    /// account simply starts with an empty history rather than losing it.
    @discardableResult
    static func migrateLegacyLayout(to key: String, folderName: String = AccountStorage.folderName) -> Bool {
        let fileManager = FileManager.default
        let root = root(folderName: folderName)
        let destination = directory(forAccount: key, folderName: folderName)
        // An account that already has a folder has nothing to take over.
        guard !fileManager.fileExists(atPath: destination.path) else { return false }
        let present = contents.filter { fileManager.fileExists(atPath: root.appendingPathComponent($0, isDirectory: true).path) }
        guard !present.isEmpty else { return false }

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            DevLog.log("storage", "Couldn't make the folder of \(key): \(DevLog.describe(error))", level: .error)
            return false
        }
        var moved = 0
        for name in present {
            do {
                try fileManager.moveItem(
                    at: root.appendingPathComponent(name, isDirectory: true),
                    to: destination.appendingPathComponent(name, isDirectory: true)
                )
                moved += 1
            } catch {
                DevLog.log("storage", "Couldn't move \(name) to \(key): \(DevLog.describe(error))", level: .error)
            }
        }
        DevLog.log("storage", "Moved \(moved) folders of the previous layout into the folder of \(key)")
        return moved > 0
    }

    /// Forgets what was downloaded about an account — its profile, settings and picture — when it
    /// is signed out. The chats stay: those written in OCTO exist nowhere else.
    static func removeAccountCache(for key: String, folderName: String = AccountStorage.folderName) {
        let cache = directory(forAccount: key, folderName: folderName).appendingPathComponent("Account", isDirectory: true)
        try? FileManager.default.removeItem(at: cache)
    }
}
