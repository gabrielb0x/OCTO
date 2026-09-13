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
    let backend: ChatBackend
    let speech: SpeechPlayer

    private(set) var models: [ModelDescriptor]
    private(set) var isRefreshingModels = false
    private(set) var usage: UsageSnapshot?
    private(set) var usageError: String?

    /// Chats that are still generating keep running when you switch to another chat.
    @ObservationIgnored private var liveSessions: [UUID: ChatSession] = [:]

    init() {
        // Keychain items survive app deletion: start clean on a fresh install.
        let launchedKey = "app.hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            Keychain.remove(CredentialVault.chatGPTAccount)
            Keychain.remove(CredentialVault.apiKeyAccount)
            UserDefaults.standard.set(true, forKey: launchedKey)
        }

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: configuration)

        let auth = AuthManager(session: session)
        self.auth = auth
        settings = AppSettings()
        store = ConversationStore()
        backend = ChatBackend(vault: auth.vault, session: session)
        speech = SpeechPlayer()
        models = Self.cachedModels(for: auth.account?.method)
    }

    var authMethod: AuthMethod? {
        auth.account?.method
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
        guard let method = authMethod, !isRefreshingModels else { return }
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        do {
            let fetched = try await backend.fetchModels()
            models = fetched
            Self.cache(fetched, for: method)
        } catch {
            if models.isEmpty {
                models = Self.fallback(for: method)
            }
        }
    }

    func refreshUsage() async {
        do {
            usage = try await backend.fetchUsage()
            usageError = nil
        } catch {
            usageError = error.localizedDescription
        }
    }

    func didSignIn() async {
        models = Self.cachedModels(for: authMethod)
        await refreshModels()
    }

    func signOut() async {
        for session in liveSessions.values {
            session.stop()
        }
        liveSessions.removeAll()
        speech.stop()
        usage = nil
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
        }
        let model = defaultModel
        let conversation = Conversation(
            modelID: model.id,
            reasoningEffort: model.resolvedEffort(preferred: settings.defaultReasoningEffort),
            webSearchEnabled: settings.webSearchByDefault
        )
        return ChatSession(conversation: conversation, isTemporary: temporary, app: self)
    }

    func sessionStartedStreaming(_ session: ChatSession) {
        liveSessions[session.id] = session
    }

    func sessionStoppedStreaming(_ session: ChatSession) {
        liveSessions[session.id] = nil
    }

    // MARK: Model cache

    private static func cacheKey(for method: AuthMethod) -> String {
        "models.cache.\(method.rawValue)"
    }

    private static func fallback(for method: AuthMethod) -> [ModelDescriptor] {
        method == .chatGPT ? ModelCatalog.chatGPTFallback : ModelCatalog.platformFallback
    }

    private static func cachedModels(for method: AuthMethod?) -> [ModelDescriptor] {
        guard let method else { return ModelCatalog.chatGPTFallback }
        if let data = UserDefaults.standard.data(forKey: cacheKey(for: method)),
           let models = try? JSONDecoder().decode([ModelDescriptor].self, from: data),
           !models.isEmpty {
            return models
        }
        return fallback(for: method)
    }

    private static func cache(_ models: [ModelDescriptor], for method: AuthMethod) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: method))
    }
}
