import Foundation

/// What changed in a version, presented once after updating to it.
struct ReleaseNotes: Identifiable, Equatable {
    struct Change: Identifiable, Equatable {
        let systemImage: String
        let title: String
        let detail: String

        var id: String { title }
    }

    let version: String
    let changes: [Change]

    var id: String { version }

    static let launchedBeforeKey = "app.hasLaunchedBefore"
    static let lastSeenVersionKey = "app.lastSeenVersion"

    /// Notes of the version being shipped. Keep in sync with CHANGELOG.md.
    static var current: ReleaseNotes {
        ReleaseNotes(version: "1.6.1", changes: [
            Change(
                systemImage: "magnifyingglass",
                title: String(localized: "Search finds every chat"),
                detail: String(localized: "The sidebar asks ChatGPT too, which searches inside your messages: chats this iPhone never opened show up, with the passage that matched.")
            ),
            Change(
                systemImage: "laptopcomputer.and.iphone",
                title: String(localized: "Every device signed in"),
                detail: String(localized: "Security and login lists the devices on your ChatGPT account, where they last connected from, and how your account is protected.")
            ),
            Change(
                systemImage: "externaldrive",
                title: String(localized: "What your files take up"),
                detail: String(localized: "Storage now shows what the files of your chats take in your ChatGPT account, next to what OCTO takes on this iPhone.")
            ),
        ])
    }

    /// The notes to present at launch: once per version, after an update but not on a fresh install.
    static func notesToShowAfterUpdate(defaults: UserDefaults = .standard, version: String = AppInfo.version) -> ReleaseNotes? {
        let lastSeen = defaults.string(forKey: lastSeenVersionKey)
        // Version 1.0 didn't record its version, but it did record its first launch.
        let isUpdate = lastSeen.map { $0 != version } ?? defaults.bool(forKey: launchedBeforeKey)
        defaults.set(version, forKey: lastSeenVersionKey)
        let notes = current
        return isUpdate && notes.version == version ? notes : nil
    }
}
