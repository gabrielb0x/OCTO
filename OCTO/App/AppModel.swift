import Foundation
import Observation
import OCTOCore

/// Root dependency container shared through the SwiftUI environment.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let auth: AuthManager
    let store: ConversationStore
    let account: AccountStore
    let backend: ChatBackend
    let speech: SpeechPlayer
    let developer: DeveloperSettings
    let toasts: ToastCenter
    let protection: AppProtection
    let notifications: ReplyNotifications
    let overlays: OverlayWindows
    let updates: UpdateChecker
    /// Set when a screenshot build is launched with a demo scene: no network, no keychain.
    let isDemo: Bool
    #if OCTO_DEMO
    let demoScene: DemoScene?
    #endif

    private(set) var models: [ModelDescriptor]
    private(set) var isRefreshingModels = false
    private(set) var modelsError: String?
    private(set) var modelsUpdatedAt: Date?
    private(set) var usage: UsageSnapshot?
    private(set) var usageError: String?
    /// Release notes presented once after an update.
    var whatsNew: ReleaseNotes?
    /// A newer version found on GitHub, offered once.
    var updatePrompt: AppRelease?

    /// Chats that are still generating keep running when you switch to another chat.
    @ObservationIgnored private var liveSessions: [UUID: ChatSession] = [:]
    @ObservationIgnored private var lastAccountRefresh: Date?
    @ObservationIgnored private let session: URLSession

    init() {
        #if OCTO_DEMO
        let demoScene = DemoScene.current
        let isDemo = demoScene != nil
        self.demoScene = demoScene
        #else
        let isDemo = false
        #endif
        self.isDemo = isDemo
        // Developer mode is set up first, so the first requests of a launch are recorded too.
        developer = DeveloperSettings()
        toasts = ToastCenter()
        overlays = OverlayWindows()

        // Decided before the first launch is recorded below, so a fresh install shows no notes.
        #if OCTO_DEMO
        let notes = isDemo ? nil : ReleaseNotes.notesToShowAfterUpdate()
        #else
        let notes = ReleaseNotes.notesToShowAfterUpdate()
        #endif

        // Keychain items survive app deletion: start clean on a fresh install.
        if !isDemo, !UserDefaults.standard.bool(forKey: ReleaseNotes.launchedBeforeKey) {
            Keychain.remove(CredentialVault.chatGPTAccount)
            Keychain.remove(CredentialVault.legacyAPIKeyAccount)
            UserDefaults.standard.set(true, forKey: ReleaseNotes.launchedBeforeKey)
        }

        // Ephemeral: cookies live in memory for this launch only and nothing is cached on disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: configuration)
        self.session = session

        let auth = AuthManager(session: session)
        self.auth = auth
        let settings = AppSettings()
        self.settings = settings
        protection = AppProtection(settings: settings, isDemo: isDemo)
        notifications = ReplyNotifications(isDemo: isDemo)
        updates = UpdateChecker(isDemo: isDemo)
        #if OCTO_DEMO
        let folderName = isDemo ? "Demo" : "OCTO"
        let files = ConversationFiles(folderName: folderName, startEmpty: isDemo)
        let accountCache = AccountCache(folderName: folderName)
        let accountService: AccountService? = isDemo ? nil : AccountService(vault: auth.vault, session: session)
        #else
        let files = ConversationFiles()
        let accountCache = AccountCache()
        let accountService: AccountService? = AccountService(vault: auth.vault, session: session)
        #endif
        store = ConversationStore(files: files)
        account = AccountStore(service: accountService, cache: accountCache)
        backend = ChatBackend(vault: auth.vault, session: session)
        speech = SpeechPlayer()
        models = Self.cachedModels()
        whatsNew = notes
        store.service = accountService

        // Chats older than the time chosen in Privacy leave the device.
        if !isDemo, let interval = settings.localRetention.interval {
            store.removeChats(before: Date().addingTimeInterval(-interval))
        }

        #if OCTO_DEMO
        if let demoScene {
            models = ModelCatalog.chatGPTFallback
            DemoContent.prepare(demoScene, app: self)
        }
        #endif
        DevLog.log("app", "Launched OCTO \(AppInfo.version) (\(AppInfo.build))")
    }

    // MARK: Account

    /// Name shown for the account: the ChatGPT profile name, else the email address.
    var accountName: String {
        if let name = account.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return accountEmail ?? "ChatGPT"
    }

    var accountEmail: String? {
        account.profile?.email ?? auth.account?.email
    }

    /// Whether the email address and the phone number of the account can be read right now.
    var contactShield: ContactShield {
        ContactShield(visibility: settings.contactVisibility, isScreenCaptured: protection.isScreenCaptured)
    }

    /// The name shown in the sidebar and above Settings. An account without a name shows its email
    /// address, which is hidden like the other personal details when the settings ask for it.
    var shieldedAccountName: String {
        let name = accountName
        guard contactShield.isMasked, let email = accountEmail, name == email else { return name }
        return ContactMasking.email(email)
    }

    /// The session to the ChatGPT account; nil in screenshot builds.
    var accountService: AccountService? {
        store.service
    }

    /// The plan, from the subscription check or else the sign-in tokens. Developer mode can override it.
    var planType: String? {
        if developer.isEnabled, let override = developer.planOverride.planType {
            return override
        }
        return account.subscription?.planType ?? auth.account?.planType
    }

    /// Like in ChatGPT, only subscribers choose their model.
    var allowsModelChoice: Bool {
        (developer.isEnabled && developer.forcesModelPicker) || ChatGPTPlan.allowsModelChoice(planType)
    }

    /// Like ChatGPT, an account without a subscription is offered one, unless Appearance says no.
    var showsUpgradeOffer: Bool {
        settings.showsUpgradeButton && ChatGPTPlan.isPaid(planType) == false
    }

    var planName: String {
        if let plan = ChatGPTPlan.displayName(for: planType) {
            return String(localized: "ChatGPT \(plan)")
        }
        return "ChatGPT"
    }

    /// The plan alone, as ChatGPT shows it next to "Subscription".
    var planShortName: String {
        ChatGPTPlan.displayName(for: planType) ?? "–"
    }

    /// Refreshes the models, the account and the chat list together.
    /// Skipped when it ran less than a minute ago, unless forced.
    func refreshAccount(force: Bool = false) async {
        guard !isDemo, auth.account != nil else { return }
        if !force, let lastAccountRefresh, Date().timeIntervalSince(lastAccountRefresh) < 60 { return }
        lastAccountRefresh = Date()
        async let modelsRefresh: Void = refreshModels()
        async let accountRefresh: Void = account.refresh()
        async let chatsRefresh: Void = store.syncWithAccount()
        _ = await (modelsRefresh, accountRefresh, chatsRefresh)
    }

    /// Like "Restore purchases" in ChatGPT: new tokens, then the subscription and models of the plan.
    func restorePurchases() async {
        guard !isDemo else {
            toasts.show(String(localized: "Your subscription is up to date: \(planName)"))
            return
        }
        do {
            try await auth.refreshSession()
            await account.refresh()
            await refreshModels()
            toasts.show(String(localized: "Your subscription is up to date: \(planName)"))
        } catch {
            DevLog.log("auth", "Restore purchases failed: \(DevLog.describe(error))", level: .error)
            toasts.show(ChatSession.describe(error), style: .failure)
        }
    }

    func refreshSession() async {
        guard !isDemo else { return }
        do {
            try await auth.refreshSession()
            toasts.show(String(localized: "Session refreshed"))
        } catch {
            toasts.show(ChatSession.describe(error), style: .failure)
        }
    }

    // MARK: Updates

    /// Looks for a new version when automatic checks are on, and offers it once.
    func checkForUpdatesIfDue() async {
        guard settings.checksForUpdates else { return }
        await updates.checkIfDue()
        guard let release = updates.available, whatsNew == nil, updatePrompt == nil, !updates.wasAnnounced(release) else { return }
        updates.markAnnounced(release)
        updatePrompt = release
    }

    // MARK: Models

    func model(for id: String?) -> ModelDescriptor {
        guard allowsModelChoice else {
            return models.first ?? ModelCatalog.chatGPTFallback[0]
        }
        if let id, let match = models.first(where: { $0.id == id }) {
            return match
        }
        if let preferred = settings.defaultModelID, let match = models.first(where: { $0.id == preferred }) {
            return match
        }
        return models.first ?? ModelCatalog.chatGPTFallback[0]
    }

    var defaultModel: ModelDescriptor {
        model(for: settings.defaultModelID)
    }

    func refreshModels() async {
        guard !isDemo, auth.account != nil, !isRefreshingModels else { return }
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        do {
            let fetched = try await backend.fetchModels()
            models = fetched
            modelsError = nil
            modelsUpdatedAt = Date()
            Self.cache(fetched)
            DevLog.log("models", "Loaded \(fetched.count) models: \(fetched.map(\.id).joined(separator: ", "))")
        } catch {
            modelsError = ChatSession.describe(error)
            DevLog.log("models", "Loading failed: \(DevLog.describe(error))", level: .warning)
            if models.isEmpty {
                models = ModelCatalog.chatGPTFallback
            }
        }
    }

    func refreshUsage() async {
        guard !isDemo else { return }
        do {
            usage = try await backend.fetchUsage()
            usageError = nil
        } catch {
            usageError = ChatSession.describe(error)
        }
    }

    #if OCTO_DEMO
    /// Screenshot builds show usage without touching the network.
    func useDemoUsage(_ snapshot: UsageSnapshot?) {
        usage = snapshot
    }
    #endif

    func didSignIn() async {
        models = Self.cachedModels()
        DevLog.log("auth", "Signed in (\(auth.signInMethod?.rawValue ?? "unknown"))")
        await refreshAccount(force: true)
    }

    func signOut() async {
        for session in liveSessions.values {
            session.stop()
        }
        liveSessions.removeAll()
        speech.stop()
        usage = nil
        lastAccountRefresh = nil
        toasts.dismiss()
        account.clear()
        store.removeAccountChats()
        // The network log holds account data.
        developer.console.clearNetwork()
        DevLog.log("auth", "Signed out")
        await auth.signOut()
        // Cookies and connections of the old session go too.
        await session.reset()
    }

    // MARK: Sessions

    /// A chat to show. New chats are temporary when Privacy asks for it, unless `temporary` says otherwise.
    func makeSession(conversationID: UUID? = nil, temporary: Bool? = nil) -> ChatSession {
        if let conversationID {
            if let live = liveSessions[conversationID] {
                return live
            }
            if let conversation = store.conversation(id: conversationID) {
                return ChatSession(conversation: conversation, isTemporary: false, app: self)
            }
            if let summary = store.summary(id: conversationID), summary.isAccountChat {
                // Opened before its messages were downloaded: the chat loads them from the account.
                let conversation = Conversation(
                    id: summary.id,
                    title: summary.title,
                    createdAt: summary.createdAt,
                    updatedAt: summary.updatedAt,
                    isPinned: summary.isPinned,
                    webSearchEnabled: settings.webSearchByDefault,
                    remoteID: summary.remoteID,
                    projectID: summary.projectID
                )
                return ChatSession(conversation: conversation, isTemporary: false, app: self)
            }
        }
        let model = defaultModel
        let conversation = Conversation(
            modelID: model.id,
            reasoningEffort: model.resolvedEffort(preferred: settings.defaultReasoningEffort),
            webSearchEnabled: settings.webSearchByDefault
        )
        return ChatSession(conversation: conversation, isTemporary: temporary ?? settings.temporaryChatsByDefault, app: self)
    }

    /// A chat that is still generating in the background, if any.
    func liveSession(for id: UUID) -> ChatSession? {
        liveSessions[id]
    }

    var liveSessionCount: Int {
        liveSessions.count
    }

    func sessionStartedStreaming(_ session: ChatSession) {
        liveSessions[session.id] = session
        notifications.replyStarted(session.id)
    }

    func sessionStoppedStreaming(_ session: ChatSession, reply: String, failed: Bool) {
        liveSessions[session.id] = nil
        notifications.replyFinished(session.id, title: session.isTemporary ? "" : session.title, reply: reply, failed: failed, settings: settings)
    }

    // MARK: Model cache

    static let modelsCacheKey = "models.cache.chatGPT"

    private static func cachedModels() -> [ModelDescriptor] {
        if let data = UserDefaults.standard.data(forKey: modelsCacheKey),
           let models = try? JSONDecoder().decode([ModelDescriptor].self, from: data),
           !models.isEmpty {
            return models
        }
        return ModelCatalog.chatGPTFallback
    }

    private static func cache(_ models: [ModelDescriptor]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: modelsCacheKey)
    }
}
