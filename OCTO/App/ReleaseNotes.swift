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
    private static let lastSeenVersionKey = "app.lastSeenVersion"

    /// Notes of the version being shipped. Keep in sync with CHANGELOG.md.
    static var current: ReleaseNotes {
        ReleaseNotes(version: "1.1.0", changes: [
            Change(
                systemImage: "person.crop.circle.badge.checkmark",
                title: String(localized: "Your ChatGPT account"),
                detail: String(localized: "Your chats, projects, custom instructions, personality, memory and profile picture now come from your ChatGPT account.")
            ),
            Change(
                systemImage: "bubble.left.and.text.bubble.right",
                title: String(localized: "Simply ChatGPT"),
                detail: String(localized: "The assistant now presents itself as ChatGPT.")
            ),
            Change(
                systemImage: "text.alignleft",
                title: String(localized: "Smoother replies"),
                detail: String(localized: "Replies flow in smoothly, and the chat no longer scrolls by itself while ChatGPT writes.")
            ),
            Change(
                systemImage: "character.cursor.ibeam",
                title: String(localized: "Liquid Glass message bar"),
                detail: String(localized: "The message bar and its + button are now made of Liquid Glass.")
            ),
            Change(
                systemImage: "sparkles",
                title: String(localized: "Smoother welcome screen"),
                detail: String(localized: "The typing animation on the sign-in screen is smoother.")
            ),
            Change(
                systemImage: "key",
                title: String(localized: "No more API keys"),
                detail: String(localized: "Signing in with an OpenAI API key isn't offered anymore for now.")
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
