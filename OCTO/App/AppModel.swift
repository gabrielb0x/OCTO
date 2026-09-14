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
    /// Set when a screenshot build is launched with a demo scene: no network, no keychain.
    let isDemo: Bool
    #if OCTO_DEMO
    let demoScene: DemoScene?
    #endif

    private(set) var models: [ModelDescriptor]
    private(set) var isRefreshingModels = false
    private(set) var usage: UsageSnapshot?
    private(set) var usageError: String?
    /// Release notes presented once after an update.
    var whatsNew: ReleaseNotes?

    /// Chats that are still generating keep running when you switch to another chat.
    @ObservationIgnored private var liveSessions: [UUID: ChatSession] = [:]
    @ObservationIgnored private var lastAccountRefresh: Date?

    init() {
        #if OCTO_DEMO
        let demoScene = DemoScene.current
        let isDemo = demoScene != nil
        self.demoScene = demoScene
        #else
        let isDemo = false
        #endif
        self.isDemo = isDemo

        // Decided before the first launch is recorded below, so a fresh install shows no notes.
        let notes = isDemo ? nil : ReleaseNotes.notesToShowAfterUpdate()

        // Keychain items survive app deletion: start clean on a fresh install.
        if !isDemo, !UserDefaults.standard.bool(forKey: ReleaseNotes.launchedBeforeKey) {
            Keychain.remove(CredentialVault.chatGPTAccount)
            Keychain.remove(CredentialVault.legacyAPIKeyAccount)
            UserDefaults.standard.set(true, forKey: ReleaseNotes.launchedBeforeKey)
        }

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: configuration)

        let auth = AuthManager(session: session)
        self.auth = auth
        settings = AppSettings()
        #if OCTO_DEMO
        let folderName = isDemo ? "Demo" : "OCTO"
        let files = ConversationFiles(folderName: folderName, startEmpty: isDemo)
        let accountCache = AccountCache(folderName: folderName)
        #else
        let files = ConversationFiles()
        let accountCache = AccountCache()
        #endif
        let accountService = AccountService(vault: auth.vault, session: session)
        store = ConversationStore(files: files)
        account = AccountStore(service: isDemo ? nil : accountService, cache: accountCache)
        backend = ChatBackend(vault: auth.vault, session: session)
        speech = SpeechPlayer()
        models = Self.cachedModels()
        whatsNew = notes
        if !isDemo {
            store.service = accountService
        }

        #if OCTO_DEMO
        if let demoScene {
            models = ModelCatalog.chatGPTFallback
            DemoContent.prepare(demoScene, app: self)
        }
        #endif
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

    var planName: String {
        if let plan = ChatGPTPlan.displayName(for: auth.account?.planType) {
            return String(localized: "ChatGPT \(plan)")
        }
        return "ChatGPT"
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

    // MARK: Models

    func model(for id: String?) -> ModelDescriptor {
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
            Self.cache(fetched)
        } catch {
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

    func didSignIn() async {
        models = Self.cachedModels()
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
        account.clear()
        store.removeAccountChats()
        await auth.signOut()
    }

    // MARK: Sessions

    func makeSession(conversationID: UUID? = nil, temporary: Bool = false) -> ChatSession {
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
        return ChatSession(conversation: conversation, isTemporary: temporary, app: self)
    }

    /// A chat that is still generating in the background, if any.
    func liveSession(for id: UUID) -> ChatSession? {
        liveSessions[id]
    }

    func sessionStartedStreaming(_ session: ChatSession) {
        liveSessions[session.id] = session
    }

    func sessionStoppedStreaming(_ session: ChatSession) {
        liveSessions[session.id] = nil
    }

    // MARK: Model cache

    private static let modelsCacheKey = "models.cache.chatGPT"

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
