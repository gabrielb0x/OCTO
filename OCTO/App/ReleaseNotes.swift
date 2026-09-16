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
        ReleaseNotes(version: "1.8.0", changes: [
            Change(
                systemImage: "sparkles",
                title: String(localized: "The plans, like in ChatGPT"),
                detail: String(localized: "“Upgrade” now lays out ChatGPT's plans: the Go and Plus picker, and what each one adds to a free account.")
            ),
            Change(
                systemImage: "tag",
                title: String(localized: "The real prices"),
                detail: String(localized: "The prices come from ChatGPT for the country you're in, in your currency. OCTO sells nothing: the button opens ChatGPT, which takes the payment.")
            ),
            Change(
                systemImage: "trash",
                title: String(localized: "Delete what you'd rather not keep"),
                detail: String(localized: "Swipe to delete a saved memory in Memory, or an archived chat in Data controls: both leave your ChatGPT account.")
            ),
            Change(
                systemImage: "person.crop.circle",
                title: String(localized: "Settings without the pill"),
                detail: String(localized: "The glass “Upgrade” button under your account is gone. The offer stays where ChatGPT puts it: above a chat, and in the Subscription page.")
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
