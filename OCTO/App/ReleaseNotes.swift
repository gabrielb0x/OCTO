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
        ReleaseNotes(version: "1.4.0", changes: [
            Change(
                systemImage: "text.line.first.and.arrowtriangle.forward",
                title: String(localized: "Calmer replies"),
                detail: String(localized: "Replies now appear word by word, each word fading in. Pick the pace in Appearance.")
            ),
            Change(
                systemImage: "eye.slash",
                title: String(localized: "Much more private"),
                detail: String(localized: "Links without trackers, copies that stay on your iPhone, no third-party keyboards, chats hidden during screen recording and more, in Privacy.")
            ),
            Change(
                systemImage: "paintpalette",
                title: String(localized: "Make it yours"),
                detail: String(localized: "New accent colors and one of your own, text size, font and code wrapping.")
            ),
            Change(
                systemImage: "mic",
                title: String(localized: "Dictation by ChatGPT"),
                detail: String(localized: "Your voice is recorded, then written down by ChatGPT, like in its apps.")
            ),
            Change(
                systemImage: "hand.raised",
                title: String(localized: "Your real data controls"),
                detail: String(localized: "Improve the model for everyone shows the setting saved in your account, and turns off from OCTO.")
            ),
            Change(
                systemImage: "arrow.down.app",
                title: String(localized: "Updates"),
                detail: String(localized: "OCTO tells you when a new version is out and installs it with AltStore or SideStore.")
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
