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
        ReleaseNotes(version: "1.9.0", changes: [
            Change(
                systemImage: "person.2",
                title: String(localized: "Several ChatGPT accounts"),
                detail: String(localized: "Add your other accounts and switch between them from Settings → Accounts, or by holding your name in the chat list. Each one keeps its own chats on this device.")
            ),
            Change(
                systemImage: "megaphone",
                title: String(localized: "Ads, really managed"),
                detail: String(localized: "Ads management turns personalized ads and the ad history off in your account, deletes the advertising data ChatGPT keeps, and lets a free account trade its ads for fewer messages.")
            ),
            Change(
                systemImage: "brain",
                title: String(localized: "Memory switches that work"),
                detail: String(localized: "“Reference saved memories” and “Reference chat history” are switches now, saved straight to your ChatGPT account instead of only being shown.")
            ),
            Change(
                systemImage: "exclamationmark.triangle",
                title: String(localized: "Red means red"),
                detail: String(localized: "Signing out, deleting your chats and the other rows that undo something wear a stronger red, over the whole row.")
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
