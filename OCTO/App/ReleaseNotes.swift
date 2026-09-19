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
        ReleaseNotes(version: "1.11.0", changes: [
            Change(
                systemImage: "chart.bar.xaxis",
                title: String(localized: "Your Codex usage, in charts"),
                detail: String(localized: "Settings → Codex usage shows the tokens used each day and what's left of your limit, with the tokens and messages left, estimated from your chats.")
            ),
            Change(
                systemImage: "pencil.circle",
                title: String(localized: "Edit your profile"),
                detail: String(localized: "The pencil on your picture in Settings changes your photo, display name and username in ChatGPT.")
            ),
            Change(
                systemImage: "hand.raised.slash",
                title: String(localized: "Telemetry blocked"),
                detail: String(localized: "OCTO refuses any request to the telemetry addresses of ChatGPT and Codex, such as Statsig, whatever would try.")
            ),
            Change(
                systemImage: "eye.slash",
                title: String(localized: "Email and phone out of sight"),
                detail: String(localized: "Privacy can take their rows out of Settings altogether.")
            ),
            Change(
                systemImage: "keyboard.chevron.compact.down",
                title: String(localized: "Smoother chats"),
                detail: String(localized: "The button that goes back down sits above the message bar, and a slide down on a new chat puts the keyboard away, tab bar included.")
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
