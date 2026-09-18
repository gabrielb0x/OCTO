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
        ReleaseNotes(version: "1.10.0", changes: [
            Change(
                systemImage: "rectangle.3.group",
                title: String(localized: "A tab bar, if you like"),
                detail: String(localized: "Settings → Layout puts your chats, Home and Settings in a Liquid Glass bar at the bottom of the screen, with the tabs you choose. The sidebar stays the default.")
            ),
            Change(
                systemImage: "cpu",
                title: String(localized: "The models Codex offers you"),
                detail: String(localized: "The picker lists the models Codex gives your plan, free included, with what they're for and how fast they can answer. A model Codex turns down leaves it.")
            ),
            Change(
                systemImage: "terminal",
                title: String(localized: "ChatGPT or Codex"),
                detail: String(localized: "A mark tells the chats of your ChatGPT account from those written with Codex in OCTO, and the filter of the list can keep only one kind.")
            ),
            Change(
                systemImage: "person.2",
                title: String(localized: "Every account's picture"),
                detail: String(localized: "The account list shows the profile pictures of your other accounts too.")
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
