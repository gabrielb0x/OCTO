import Foundation
import Observation
import OCTOCore

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

/// The accent colors of ChatGPT, a few more and a color of your own. The default keeps the monochrome look.
enum AccentChoice: String, CaseIterable, Identifiable {
    case `default`
    case blue
    case green
    case yellow
    case pink
    case orange
    case purple
    case red
    case mint
    case custom

    var id: String { rawValue }
}

/// Size of the text of chats, a step or two away from the size chosen in iOS.
enum ChatTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    /// Steps along iOS's text sizes.
    var steps: Int {
        switch self {
        case .small: return -1
        case .standard: return 0
        case .large: return 1
        case .extraLarge: return 2
        }
    }
}

enum ChatFont: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }
}

/// How dictation turns your voice into text.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    /// Recorded, then written down by ChatGPT like in its apps.
    case chatGPT
    /// Apple's speech recognition, on the device.
    case onDevice

    var id: String { rawValue }
}

/// How long text copied from OCTO stays in the clipboard.
enum ClipboardExpiry: Int, CaseIterable, Identifiable {
    case never = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
}

/// How the email address and the phone number of the account show in Settings.
enum ContactVisibility: String, CaseIterable, Identifiable {
    /// Readable, like in the ChatGPT app.
    case always
    /// Behind dots until you tap them.
    case tapToReveal
    /// Readable, except while the screen is recorded, mirrored or shared.
    case whileNotRecording
    /// Never readable in OCTO.
    case never
    /// Left out of Settings altogether, rows included.
    case removed

    var id: String { rawValue }
}

/// Whether the email address and the phone number can be read right now.
struct ContactShield {
    let visibility: ContactVisibility
    /// The screen is being recorded, mirrored or shared.
    let isScreenCaptured: Bool

    /// True when the values show as dots until they're revealed.
    var isMasked: Bool {
        switch visibility {
        case .always: return false
        case .tapToReveal, .never, .removed: return true
        case .whileNotRecording: return isScreenCaptured
        }
    }

    /// True when a tap shows the real value. Never while the screen is captured.
    var canReveal: Bool {
        visibility == .tapToReveal && !isScreenCaptured
    }

    /// True when the value may leave OCTO, for the copy action.
    var allowsCopy: Bool {
        visibility != .never && visibility != .removed
    }

    /// False when the rows of the email address and the phone number leave Settings.
    var showsRows: Bool {
        visibility != .removed
    }
}

/// The starter prompts above the message bar of a new chat.
enum SuggestionStyle: String, CaseIterable, Identifiable {
    /// The list of the ChatGPT app: an icon and a few words, one per line.
    case list
    /// Glass chips that scroll sideways.
    case chips

    var id: String { rawValue }
}

/// How long chats stay on this device.
enum LocalRetention: Int, CaseIterable, Identifiable {
    case forever = 0
    case oneDay = 86_400
    case oneWeek = 604_800
    case oneMonth = 2_592_000

    var id: Int { rawValue }

    var interval: TimeInterval? {
        self == .forever ? nil : TimeInterval(rawValue)
    }
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

/// How OCTO lays out its screens: the sidebar of the ChatGPT app, or tabs in a bar at the bottom.
enum AppLayout: String, CaseIterable, Identifiable {
    case sidebar
    case tabBar

    var id: String { rawValue }
}

/// A tab of the tab bar layout.
enum AppTab: String, CaseIterable, Identifiable {
    /// The chat you're writing in: a new one, or the one opened from your chats.
    case home
    case chats
    case projects
    case accounts
    case settings
    /// The round glass button at the end of the bar, which searches every chat.
    case search

    var id: String { rawValue }

    /// The tabs that sit in the bar itself; search has its own button next to it.
    static let barTabs: [AppTab] = [.home, .chats, .projects, .accounts, .settings]
    static let defaultBar: [AppTab] = [.chats, .home, .settings]
    /// iOS shows five tabs on an iPhone before hiding the rest behind "More".
    static let maximumInBar = 5
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

    /// "#RRGGBB" of the custom accent color.
    var customAccentHex: String {
        didSet { defaults.set(customAccentHex, forKey: Keys.customAccentHex) }
    }

    var chatTextSize: ChatTextSize {
        didSet { defaults.set(chatTextSize.rawValue, forKey: Keys.chatTextSize) }
    }

    var chatFont: ChatFont {
        didSet { defaults.set(chatFont.rawValue, forKey: Keys.chatFont) }
    }

    /// How fast the words of a reply appear.
    var revealSpeed: RevealSpeed {
        didSet { defaults.set(revealSpeed.rawValue, forKey: Keys.revealSpeed) }
    }

    var wrapsCodeLines: Bool {
        didSet { defaults.set(wrapsCodeLines, forKey: Keys.wrapsCodeLines) }
    }

    /// Light taps while a reply is written.
    var streamingHaptics: Bool {
        didSet { defaults.set(streamingHaptics, forKey: Keys.streamingHaptics) }
    }

    var sendsWithReturn: Bool {
        didSet { defaults.set(sendsWithReturn, forKey: Keys.sendsWithReturn) }
    }

    var correctsSpelling: Bool {
        didSet { defaults.set(correctsSpelling, forKey: Keys.correctsSpelling) }
    }

    var showsSuggestions: Bool {
        didSet { defaults.set(showsSuggestions, forKey: Keys.showsSuggestions) }
    }

    var suggestionStyle: SuggestionStyle {
        didSet { defaults.set(suggestionStyle.rawValue, forKey: Keys.suggestionStyle) }
    }

    /// "Upgrade" in the top bar of a chat, shown to accounts without a subscription.
    var showsUpgradeButton: Bool {
        didSet { defaults.set(showsUpgradeButton, forKey: Keys.showsUpgradeButton) }
    }

    /// "What can I help with?" in the middle of a new chat. The ChatGPT app leaves it out.
    var showsGreeting: Bool {
        didSet { defaults.set(showsGreeting, forKey: Keys.showsGreeting) }
    }

    /// How the email address and the phone number show in Settings.
    var contactVisibility: ContactVisibility {
        didSet { defaults.set(contactVisibility.rawValue, forKey: Keys.contactVisibility) }
    }

    /// System voice used to read replies aloud; nil picks one matching the language of the reply.
    var voiceIdentifier: String? {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier) }
    }

    var voicePause: VoicePause {
        didSet { defaults.set(voicePause.rawValue, forKey: Keys.voicePause) }
    }

    var transcriptionEngine: TranscriptionEngine {
        didSet { defaults.set(transcriptionEngine.rawValue, forKey: Keys.transcriptionEngine) }
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

    /// A faster tier to ask replies for, such as `priority` (Codex's "Fast"); nil is the usual speed.
    var serviceTier: String? {
        didSet { defaults.set(serviceTier, forKey: Keys.serviceTier) }
    }

    // MARK: Layout

    var layout: AppLayout {
        didSet { defaults.set(layout.rawValue, forKey: Keys.layout) }
    }

    /// The tabs of the bar, in order. Home is always one of them: it's where you write.
    /// Changed through `setTabBarTabs(_:)`, which keeps the list valid.
    private(set) var tabBarTabs: [AppTab] {
        didSet { defaults.set(tabBarTabs.map(\.rawValue), forKey: Keys.tabBarTabs) }
    }

    func setTabBarTabs(_ tabs: [AppTab]) {
        tabBarTabs = Self.sanitizedTabs(tabs)
    }

    /// The round search button at the end of the tab bar.
    var showsSearchTab: Bool {
        didSet { defaults.set(showsSearchTab, forKey: Keys.showsSearchTab) }
    }

    /// The tab OCTO opens on.
    var startTab: AppTab {
        didSet { defaults.set(startTab.rawValue, forKey: Keys.startTab) }
    }

    /// The bar shrinks to a small button while you scroll down, like in Apple's apps.
    var tabBarMinimizesOnScroll: Bool {
        didSet { defaults.set(tabBarMinimizesOnScroll, forKey: Keys.tabBarMinimizesOnScroll) }
    }

    /// Every tab shown, in order, the search button last.
    var visibleTabs: [AppTab] {
        showsSearchTab ? tabBarTabs + [.search] : tabBarTabs
    }

    /// The tab OCTO opens on, when it's still in the bar.
    var initialTab: AppTab {
        visibleTabs.contains(startTab) ? startTab : .home
    }

    // MARK: Chat list

    /// Which chats the chat list shows: all of them, those of the ChatGPT account, or those written with Codex.
    var chatOriginFilter: ChatOriginFilter {
        didSet { defaults.set(chatOriginFilter.rawValue, forKey: Keys.chatOriginFilter) }
    }

    /// A small ChatGPT or Codex mark next to each chat of the list.
    var showsChatOrigin: Bool {
        didSet { defaults.set(showsChatOrigin, forKey: Keys.showsChatOrigin) }
    }

    // MARK: Privacy

    var temporaryChatsByDefault: Bool {
        didSet { defaults.set(temporaryChatsByDefault, forKey: Keys.temporaryChatsByDefault) }
    }

    var localRetention: LocalRetention {
        didSet { defaults.set(localRetention.rawValue, forKey: Keys.localRetention) }
    }

    /// Covers the chats while the screen is recorded, mirrored or shared.
    var hidesWhenScreenCaptured: Bool {
        didSet { defaults.set(hidesWhenScreenCaptured, forKey: Keys.hidesWhenScreenCaptured) }
    }

    /// Copied text stays off Universal Clipboard.
    var copiesOnlyOnThisDevice: Bool {
        didSet { defaults.set(copiesOnlyOnThisDevice, forKey: Keys.copiesOnlyOnThisDevice) }
    }

    var clipboardExpiry: ClipboardExpiry {
        didSet { defaults.set(clipboardExpiry.rawValue, forKey: Keys.clipboardExpiry) }
    }

    var blocksThirdPartyKeyboards: Bool {
        didSet { defaults.set(blocksThirdPartyKeyboards, forKey: Keys.blocksThirdPartyKeyboards) }
    }

    var removesLinkTrackers: Bool {
        didSet { defaults.set(removesLinkTrackers, forKey: Keys.removesLinkTrackers) }
    }

    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Keys.checksForUpdates) }
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
        customAccentHex = defaults.string(forKey: Keys.customAccentHex) ?? "#8E5CF7"
        chatTextSize = defaults.string(forKey: Keys.chatTextSize).flatMap(ChatTextSize.init(rawValue:)) ?? .standard
        chatFont = defaults.string(forKey: Keys.chatFont).flatMap(ChatFont.init(rawValue:)) ?? .system
        revealSpeed = defaults.string(forKey: Keys.revealSpeed).flatMap(RevealSpeed.init(rawValue:)) ?? .normal
        wrapsCodeLines = defaults.bool(forKey: Keys.wrapsCodeLines)
        streamingHaptics = defaults.bool(forKey: Keys.streamingHaptics)
        sendsWithReturn = defaults.bool(forKey: Keys.sendsWithReturn)
        correctsSpelling = defaults.object(forKey: Keys.correctsSpelling) as? Bool ?? true
        showsSuggestions = defaults.object(forKey: Keys.showsSuggestions) as? Bool ?? true
        suggestionStyle = defaults.string(forKey: Keys.suggestionStyle).flatMap(SuggestionStyle.init(rawValue:)) ?? .list
        showsUpgradeButton = defaults.object(forKey: Keys.showsUpgradeButton) as? Bool ?? true
        showsGreeting = defaults.object(forKey: Keys.showsGreeting) as? Bool ?? false
        // Personal by default: the address and the number show once you ask for them.
        contactVisibility = defaults.string(forKey: Keys.contactVisibility).flatMap(ContactVisibility.init(rawValue:)) ?? .tapToReveal
        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier)
        voicePause = defaults.string(forKey: Keys.voicePause).flatMap(VoicePause.init(rawValue:)) ?? .normal
        transcriptionEngine = defaults.string(forKey: Keys.transcriptionEngine).flatMap(TranscriptionEngine.init(rawValue:)) ?? .chatGPT
        notifiesReplies = defaults.bool(forKey: Keys.notifiesReplies)
        showsNotificationPreviews = defaults.object(forKey: Keys.showsNotificationPreviews) as? Bool ?? true
        locksWithFaceID = defaults.bool(forKey: Keys.locksWithFaceID)
        lockTimeout = LockTimeout(rawValue: defaults.integer(forKey: Keys.lockTimeout)) ?? .immediately
        hidesContentInAppSwitcher = defaults.object(forKey: Keys.hidesContentInAppSwitcher) as? Bool ?? true
        temporaryChatsByDefault = defaults.bool(forKey: Keys.temporaryChatsByDefault)
        localRetention = LocalRetention(rawValue: defaults.integer(forKey: Keys.localRetention)) ?? .forever
        hidesWhenScreenCaptured = defaults.object(forKey: Keys.hidesWhenScreenCaptured) as? Bool ?? true
        copiesOnlyOnThisDevice = defaults.object(forKey: Keys.copiesOnlyOnThisDevice) as? Bool ?? true
        clipboardExpiry = ClipboardExpiry(rawValue: defaults.integer(forKey: Keys.clipboardExpiry)) ?? .never
        blocksThirdPartyKeyboards = Self.blocksThirdPartyKeyboards(defaults: defaults)
        removesLinkTrackers = defaults.object(forKey: Keys.removesLinkTrackers) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true
        serviceTier = defaults.string(forKey: Keys.serviceTier)
        layout = defaults.string(forKey: Keys.layout).flatMap(AppLayout.init(rawValue:)) ?? .sidebar
        tabBarTabs = Self.sanitizedTabs((defaults.stringArray(forKey: Keys.tabBarTabs) ?? []).compactMap(AppTab.init(rawValue:)), fallback: AppTab.defaultBar)
        showsSearchTab = defaults.object(forKey: Keys.showsSearchTab) as? Bool ?? true
        startTab = defaults.string(forKey: Keys.startTab).flatMap(AppTab.init(rawValue:)) ?? .home
        tabBarMinimizesOnScroll = defaults.object(forKey: Keys.tabBarMinimizesOnScroll) as? Bool ?? true
        chatOriginFilter = defaults.string(forKey: Keys.chatOriginFilter).flatMap(ChatOriginFilter.init(rawValue:)) ?? .all
        showsChatOrigin = defaults.object(forKey: Keys.showsChatOrigin) as? Bool ?? true
    }

    /// Tabs of the bar without duplicates, search or overflow, Home always among them.
    static func sanitizedTabs(_ tabs: [AppTab], fallback: [AppTab] = [.home]) -> [AppTab] {
        var result: [AppTab] = []
        for tab in tabs where AppTab.barTabs.contains(tab) && !result.contains(tab) {
            result.append(tab)
        }
        if result.isEmpty {
            result = fallback
        }
        if !result.contains(.home) {
            result.insert(.home, at: min(1, result.count))
        }
        return Array(result.prefix(AppTab.maximumInBar))
    }

    /// Read before the settings exist, when iOS asks whether third-party keyboards may be used.
    nonisolated static func blocksThirdPartyKeyboards(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Keys.blocksThirdPartyKeyboards) as? Bool ?? true
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
        static let customAccentHex = "settings.customAccentHex"
        static let chatTextSize = "settings.chatTextSize"
        static let chatFont = "settings.chatFont"
        static let revealSpeed = "settings.revealSpeed"
        static let wrapsCodeLines = "settings.wrapsCodeLines"
        static let streamingHaptics = "settings.streamingHaptics"
        static let sendsWithReturn = "settings.sendsWithReturn"
        static let correctsSpelling = "settings.correctsSpelling"
        static let showsSuggestions = "settings.showsSuggestions"
        static let suggestionStyle = "settings.suggestionStyle"
        static let showsUpgradeButton = "settings.showsUpgradeButton"
        static let showsGreeting = "settings.showsGreeting"
        static let contactVisibility = "settings.contactVisibility"
        static let voiceIdentifier = "settings.voiceIdentifier"
        static let voicePause = "settings.voicePause"
        static let transcriptionEngine = "settings.transcriptionEngine"
        static let notifiesReplies = "settings.notifiesReplies"
        static let showsNotificationPreviews = "settings.showsNotificationPreviews"
        static let locksWithFaceID = "settings.locksWithFaceID"
        static let lockTimeout = "settings.lockTimeout"
        static let hidesContentInAppSwitcher = "settings.hidesContentInAppSwitcher"
        static let temporaryChatsByDefault = "settings.temporaryChatsByDefault"
        static let localRetention = "settings.localRetention"
        static let hidesWhenScreenCaptured = "settings.hidesWhenScreenCaptured"
        static let copiesOnlyOnThisDevice = "settings.copiesOnlyOnThisDevice"
        static let clipboardExpiry = "settings.clipboardExpiry"
        static let blocksThirdPartyKeyboards = "settings.blocksThirdPartyKeyboards"
        static let removesLinkTrackers = "settings.removesLinkTrackers"
        static let checksForUpdates = "settings.checksForUpdates"
        static let serviceTier = "settings.serviceTier"
        static let layout = "settings.layout"
        static let tabBarTabs = "settings.tabBarTabs"
        static let showsSearchTab = "settings.showsSearchTab"
        static let startTab = "settings.startTab"
        static let tabBarMinimizesOnScroll = "settings.tabBarMinimizesOnScroll"
        static let chatOriginFilter = "settings.chatOriginFilter"
        static let showsChatOrigin = "settings.showsChatOrigin"
    }
}
