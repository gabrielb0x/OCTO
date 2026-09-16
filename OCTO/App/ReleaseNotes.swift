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
        ReleaseNotes(version: "1.5.0", changes: [
            Change(
                systemImage: "eye.slash",
                title: String(localized: "Your email stays yours"),
                detail: String(localized: "In Settings, the email address and the phone number hide behind dots: on a tap, only while the screen is recorded, or for good.")
            ),
            Change(
                systemImage: "sparkle",
                title: String(localized: "The upgrade button"),
                detail: String(localized: "Accounts without a subscription get ChatGPT's Upgrade in the top bar, and Appearance takes it away in one tap.")
            ),
            Change(
                systemImage: "list.bullet",
                title: String(localized: "The ChatGPT home screen"),
                detail: String(localized: "Suggestions are listed like in the app, and the + button joins the message bar.")
            ),
            Change(
                systemImage: "hand.wave",
                title: String(localized: "Your home screen"),
                detail: String(localized: "The greeting, the suggestions and their style are yours to choose in Appearance.")
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
