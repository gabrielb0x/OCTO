import Foundation
import Observation

/// User preferences persisted in UserDefaults (nothing here is sensitive).
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

    var aboutUser: String {
        didSet { defaults.set(aboutUser, forKey: Keys.aboutUser) }
    }

    var responseStyle: String {
        didSet { defaults.set(responseStyle, forKey: Keys.responseStyle) }
    }

    var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Keys.speechRate) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultModelID = defaults.string(forKey: Keys.defaultModelID)
        defaultReasoningEffort = defaults.string(forKey: Keys.defaultReasoningEffort)
        webSearchByDefault = defaults.object(forKey: Keys.webSearchByDefault) as? Bool ?? false
        autoGenerateTitles = defaults.object(forKey: Keys.autoGenerateTitles) as? Bool ?? true
        showReasoning = defaults.object(forKey: Keys.showReasoning) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        aboutUser = defaults.string(forKey: Keys.aboutUser) ?? ""
        responseStyle = defaults.string(forKey: Keys.responseStyle) ?? ""
        speechRate = defaults.object(forKey: Keys.speechRate) as? Double ?? 0.5
    }

    private enum Keys {
        static let defaultModelID = "settings.defaultModelID"
        static let defaultReasoningEffort = "settings.defaultReasoningEffort"
        static let webSearchByDefault = "settings.webSearchByDefault"
        static let autoGenerateTitles = "settings.autoGenerateTitles"
        static let showReasoning = "settings.showReasoning"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let aboutUser = "settings.aboutUser"
        static let responseStyle = "settings.responseStyle"
        static let speechRate = "settings.speechRate"
    }
}
