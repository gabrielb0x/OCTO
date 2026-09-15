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
        ReleaseNotes(version: "1.2.0", changes: [
            Change(
                systemImage: "gearshape.2",
                title: String(localized: "Settings like ChatGPT's"),
                detail: String(localized: "Settings are organized like in the ChatGPT app: customization, account, theme, app settings and help.")
            ),
            Change(
                systemImage: "circle.lefthalf.filled",
                title: String(localized: "Theme and accent color"),
                detail: String(localized: "OCTO follows the appearance of your device or stays light or dark, with ChatGPT's accent colors.")
            ),
            Change(
                systemImage: "faceid",
                title: String(localized: "Face ID lock"),
                detail: String(localized: "Lock OCTO with Face ID and hide your chats in the app switcher.")
            ),
            Change(
                systemImage: "bell.badge",
                title: String(localized: "Reply notifications"),
                detail: String(localized: "Get notified when ChatGPT finishes replying while OCTO is in the background.")
            ),
            Change(
                systemImage: "checkmark.circle",
                title: String(localized: "Clearer feedback"),
                detail: String(localized: "A confirmation shows when a chat is deleted, and pulling to refresh the chat list no longer fails.")
            ),
            Change(
                systemImage: "cpu",
                title: String(localized: "Model picker for subscribers"),
                detail: String(localized: "Like in ChatGPT, the model picker only shows with a subscription.")
            ),
            Change(
                systemImage: "hammer",
                title: String(localized: "Developer mode"),
                detail: String(localized: "Tap the build number 8 times in About to inspect requests, logs, tokens and performance.")
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
