import Foundation
import Observation

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

/// The accent colors of ChatGPT. The default keeps the monochrome look.
enum AccentChoice: String, CaseIterable, Identifiable {
    case `default`
    case blue
    case green
    case yellow
    case pink
    case orange

    var id: String { rawValue }
}

/// How long OCTO can stay in the background before it asks for Face ID again.
enum LockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3_600

    var id: Int { rawValue }
}

/// The silence after which voice mode sends what was said.
enum VoicePause: String, CaseIterable, Identifiable {
    case short
    case normal
    case long

    var id: String { rawValue }

    var seconds: Double {
        switch self {
        case .short: return 0.8
        case .normal: return 1.3
        case .long: return 2.2
        }
    }
}

/// Preferences of this device, persisted in UserDefaults (nothing here is sensitive).
/// Custom instructions and personality come from the ChatGPT account instead.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var defaultModelID: String? {
        didSet { defaults.set(defaultModelID, forKey: Keys.defaultModelID) }
    }

    var defaultReasoningEffort: String? {
        didSet { defaults.set(defaultReasoningEffort, forKey: Keys.defaultReasoningEffort) }
    }

    var webSearchByDefault: Bool {
        didSet { defaults.set(webSearchByDefault, forKey: Keys.webSearchByDefault) }
    }

    var autoGenerateTitles: Bool {
        didSet { defaults.set(autoGenerateTitles, forKey: Keys.autoGenerateTitles) }
    }

    var showReasoning: Bool {
        didSet { defaults.set(showReasoning, forKey: Keys.showReasoning) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Keys.speechRate) }
    }

    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }

    var correctsSpelling: Bool {
        didSet { defaults.set(correctsSpelling, forKey: Keys.correctsSpelling) }
    }

    var showsSuggestions: Bool {
        didSet { defaults.set(showsSuggestions, forKey: Keys.showsSuggestions) }
    }

    /// System voice used to read replies aloud; nil picks one matching the language of the reply.
    var voiceIdentifier: String? {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier) }
    }

    var voicePause: VoicePause {
        didSet { defaults.set(voicePause.rawValue, forKey: Keys.voicePause) }
    }

    var notifiesReplies: Bool {
        didSet { defaults.set(notifiesReplies, forKey: Keys.notifiesReplies) }
    }

    var showsNotificationPreviews: Bool {
        didSet { defaults.set(showsNotificationPreviews, forKey: Keys.showsNotificationPreviews) }
    }

    var locksWithFaceID: Bool {
        didSet { defaults.set(locksWithFaceID, forKey: Keys.locksWithFaceID) }
    }

    var lockTimeout: LockTimeout {
        didSet { defaults.set(lockTimeout.rawValue, forKey: Keys.lockTimeout) }
    }

    var hidesContentInAppSwitcher: Bool {
        didSet { defaults.set(hidesContentInAppSwitcher, forKey: Keys.hidesContentInAppSwitcher) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultModelID = defaults.string(forKey: Keys.defaultModelID)
        defaultReasoningEffort = defaults.string(forKey: Keys.defaultReasoningEffort)
        webSearchByDefault = defaults.object(forKey: Keys.webSearchByDefault) as? Bool ?? false
        autoGenerateTitles = defaults.object(forKey: Keys.autoGenerateTitles) as? Bool ?? true
        showReasoning = defaults.object(forKey: Keys.showReasoning) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        speechRate = defaults.object(forKey: Keys.speechRate) as? Double ?? 0.5
        theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        accent = defaults.string(forKey: Keys.accent).flatMap(AccentChoice.init(rawValue:)) ?? .default
        correctsSpelling = defaults.object(forKey: Keys.correctsSpelling) as? Bool ?? true
        showsSuggestions = defaults.object(forKey: Keys.showsSuggestions) as? Bool ?? true
        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier)
        voicePause = defaults.string(forKey: Keys.voicePause).flatMap(VoicePause.init(rawValue:)) ?? .normal
        notifiesReplies = defaults.bool(forKey: Keys.notifiesReplies)
        showsNotificationPreviews = defaults.object(forKey: Keys.showsNotificationPreviews) as? Bool ?? true
        locksWithFaceID = defaults.bool(forKey: Keys.locksWithFaceID)
        lockTimeout = LockTimeout(rawValue: defaults.integer(forKey: Keys.lockTimeout)) ?? .immediately
        hidesContentInAppSwitcher = defaults.bool(forKey: Keys.hidesContentInAppSwitcher)
    }

    /// Every key OCTO writes, for the developer tools.
    static let keyPrefixes = ["settings.", "app.", "models.", "developer.", "auth."]

    private enum Keys {
        static let defaultModelID = "settings.defaultModelID"
        static let defaultReasoningEffort = "settings.defaultReasoningEffort"
        static let webSearchByDefault = "settings.webSearchByDefault"
        static let autoGenerateTitles = "settings.autoGenerateTitles"
        static let showReasoning = "settings.showReasoning"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let speechRate = "settings.speechRate"
        static let theme = "settings.theme"
        static let accent = "settings.accent"
        static let correctsSpelling = "settings.correctsSpelling"
        static let showsSuggestions = "settings.showsSuggestions"
        static let voiceIdentifier = "settings.voiceIdentifier"
        static let voicePause = "settings.voicePause"
        static let notifiesReplies = "settings.notifiesReplies"
        static let showsNotificationPreviews = "settings.showsNotificationPreviews"
        static let locksWithFaceID = "settings.locksWithFaceID"
        static let lockTimeout = "settings.lockTimeout"
        static let hidesContentInAppSwitcher = "settings.hidesContentInAppSwitcher"
    }
}
