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
        ReleaseNotes(version: "1.7.0", changes: [
            Change(
                systemImage: "hand.draw",
                title: String(localized: "Slide to your chats"),
                detail: String(localized: "Sliding right anywhere on a chat brings out your chats, like in the ChatGPT app. No need to aim for the edge or the button.")
            ),
            Change(
                systemImage: "photo",
                title: String(localized: "Ask for an image"),
                detail: String(localized: "“Create an image” asks the Codex backend of your plan to draw one, and it lands in the chat. When your plan doesn't offer it, ChatGPT answers in words and says so.")
            ),
            Change(
                systemImage: "list.bullet.indent",
                title: String(localized: "Settings without the maze"),
                detail: String(localized: "Rows that only led to another page are gone: each setting is in one place, and a red row now has a red icon too.")
            ),
            Change(
                systemImage: "mic.slash",
                title: String(localized: "Dictation says when it's off"),
                detail: String(localized: "OCTO asks iOS whether dictation is turned off on this iPhone, and shows where to turn it back on instead of writing nothing down.")
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
