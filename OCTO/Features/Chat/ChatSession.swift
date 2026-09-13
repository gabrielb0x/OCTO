import Foundation
import Observation
import OCTOCore
import UIKit

/// State and actions of one conversation on screen.
@MainActor
@Observable
final class ChatSession: Identifiable {
    enum Activity: Equatable {
        case idle
        case waiting
        case thinking
        case searching
        case writing
    }

    let id: UUID
    let isTemporary: Bool
    private(set) var conversation: Conversation
    private(set) var activity: Activity = .idle
    private(set) var needsSignIn = false
    var draft = ""
    var pendingAttachments: [PendingAttachment] = []

    /// Counters used as haptic feedback triggers.
    private(set) var sentCount = 0
    private(set) var completedCount = 0

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(conversation: Conversation, isTemporary: Bool, app: AppModel) {
        id = conversation.id
        self.conversation = conversation
        self.isTemporary = isTemporary
        self.app = app
    }

    var messages: [ChatMessage] { conversation.messages }
    var isStreaming: Bool { activity != .idle }
    var title: String { conversation.displayTitle }

    var canSend: Bool {
        !isStreaming && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    var model: ModelDescriptor {
        app?.model(for: conversation.modelID) ?? ModelCatalog.chatGPTFallback[0]
    }

    var reasoningEffort: String? {
        model.resolvedEffort(preferred: conversation.reasoningEffort)
    }

    // MARK: Chat options

    func selectModel(_ model: ModelDescriptor) {
        conversation.modelID = model.id
        conversation.reasoningEffort = model.resolvedEffort(preferred: conversation.reasoningEffort ?? app?.settings.defaultReasoningEffort)
        app?.settings.defaultModelID = model.id
        persist()
    }

    func selectReasoningEffort(_ effort: String) {
        conversation.reasoningEffort = effort
        app?.settings.defaultReasoningEffort = effort
        persist()
    }

    func setWebSearch(_ enabled: Bool) {
        conversation.webSearchEnabled = enabled
        persist()
    }

    // MARK: Attachments

    func addImage(_ image: UIImage) {
        guard pendingAttachments.count < 8, let data = ImageProcessing.jpegData(from: image) else { return }
        pendingAttachments.append(PendingAttachment(name: String(localized: "Image"), content: .image(data)))
    }

    func addTextFile(name: String, text: String) {
        guard pendingAttachments.count < 8 else { return }
        pendingAttachments.append(PendingAttachment(name: name, content: .text(text)))
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    // MARK: Turns

    func send() {
        guard canSend, let app else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments.compactMap { app.store.storeAttachment($0) }
        draft = ""
        pendingAttachments = []
        conversation.messages.append(ChatMessage(role: .user, text: text, attachments: attachments))
        conversation.updatedAt = Date()
        sentCount += 1
        startAssistantTurn()
    }

    func stop() {
        streamTask?.cancel()
    }

    func regenerate(_ messageID: UUID) {
        guard !isStreaming,
              let index = conversation.messages.firstIndex(where: { $0.id == messageID }),
              conversation.messages[index].role == .assistant
        else { return }
        conversation.messages.removeSubrange(index...)
        startAssistantTurn()
    }

    func retry() {
        guard !isStreaming, let last = conversation.messages.last else { return }
        if last.role == .assistant {
            regenerate(last.id)
        } else {
            startAssistantTurn()
        }
    }

    func edit(_ messageID: UUID, text newText: String) {
        guard !isStreaming,
              let index = conversation.messages.firstIndex(where: { $0.id == messageID }),
              conversation.messages[index].role == .user
        else { return }
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !conversation.messages[index].attachments.isEmpty else { return }
        conversation.messages[index].text = text
        conversation.messages.removeSubrange((index + 1)...)
        conversation.updatedAt = Date()
        sentCount += 1
        startAssistantTurn()
    }

    /// Temporary chats leave nothing behind.
    func discardIfTemporary() {
        guard isTemporary, let app else { return }
        stop()
        for attachment in conversation.messages.flatMap(\.attachments) {
            try? FileManager.default.removeItem(at: app.store.files.attachmentURL(attachment.storedFileName))
        }
    }

    var markdownExport: String {
        app?.store.markdownExport(of: conversation) ?? ""
    }

    private func startAssistantTurn() {
        guard let app else { return }
        let model = app.model(for: conversation.modelID)
        conversation.modelID = model.id
        needsSignIn = false

        let history = conversation.messages
        let assistant = ChatMessage(role: .assistant, modelID: model.id, status: .streaming)
        conversation.messages.append(assistant)
        activity = .waiting
        persist()
        app.sessionStartedStreaming(self)

        let store = app.store
        let backend = app.backend
        let settings = app.settings
        let assistantID = assistant.id
        let effort = model.resolvedEffort(preferred: conversation.reasoningEffort)
        let instructions = SystemPrompt.make(aboutUser: settings.aboutUser, responseStyle: settings.responseStyle)
        let webSearch = conversation.webSearchEnabled && model.supportsWebSearch
        let summaries = settings.showReasoning && model.supportsReasoningSummaries
        let cacheKey = conversation.id.uuidString

        streamTask = Task { [weak self] in
            let input = await Task.detached(priority: .userInitiated) {
                ResponsesInputBuilder.input(for: history) { store.payload(for: $0) }
            }.value
            let request = ChatStreamRequest(
                modelID: model.id,
                instructions: instructions,
                input: input,
                reasoningEffort: effort,
                reasoningSummaries: summaries,
                verbosity: nil,
                webSearch: webSearch,
                cacheKey: cacheKey
            )
            await self?.consume(backend.stream(request), assistantID: assistantID)
        }
    }

    private func consume(_ stream: AsyncThrowingStream<ResponseStreamUpdate, Error>, assistantID: UUID) async {
        var textBuffer = ""
        var reasoningBuffer = ""
        var lastFlush = Date.distantPast
        var reasoningStartedAt: Date?
        var failure: Error?

        func flush() {
            lastFlush = Date()
            guard !textBuffer.isEmpty || !reasoningBuffer.isEmpty else { return }
            let text = textBuffer
            let reasoning = reasoningBuffer
            textBuffer = ""
            reasoningBuffer = ""
            updateMessage(assistantID) { message in
                message.text += text
                message.reasoning += reasoning
            }
        }

        do {
            for try await update in stream {
                switch update {
                case .created, .incomplete, .failed:
                    break
                case .reasoningStarted:
                    reasoningStartedAt = reasoningStartedAt ?? Date()
                    if activity != .writing { activity = .thinking }
                case .reasoningDelta(let delta):
                    reasoningStartedAt = reasoningStartedAt ?? Date()
                    reasoningBuffer += delta
                    if activity != .writing { activity = .thinking }
                case .reasoningSectionBreak:
                    let existing = (message(assistantID)?.reasoning ?? "") + reasoningBuffer
                    if !existing.isEmpty { reasoningBuffer += "\n\n" }
                case .reasoningFinished:
                    recordReasoningDuration(assistantID, since: reasoningStartedAt)
                case .textDelta(let delta):
                    if activity != .writing {
                        recordReasoningDuration(assistantID, since: reasoningStartedAt)
                        activity = .writing
                    }
                    textBuffer += delta
                case .webSearchStarted:
                    activity = .searching
                case .webSearchFinished(let query):
                    updateMessage(assistantID) { message in
                        if let query, !query.isEmpty, !message.searchQueries.contains(query) {
                            message.searchQueries.append(query)
                        }
                    }
                    if activity == .searching { activity = .thinking }
                case .citations(let citations):
                    updateMessage(assistantID) { message in
                        for citation in citations where !message.citations.contains(where: { $0.url == citation.url }) {
                            message.citations.append(citation)
                        }
                    }
                case .completed(let usage):
                    updateMessage(assistantID) { $0.usage = usage }
                }
                if Date().timeIntervalSince(lastFlush) > 0.05 {
                    flush()
                }
            }
        } catch {
            failure = error
        }
        flush()

        let cancelled = Task.isCancelled || failure is CancellationError || (failure as? URLError)?.code == .cancelled
        if cancelled {
            finishTurn(assistantID, status: .cancelled, error: nil)
        } else {
            finishTurn(assistantID, status: failure == nil ? .complete : .failed, error: failure)
        }
    }

    private func finishTurn(_ id: UUID, status: ChatMessage.Status, error: Error?) {
        updateMessage(id) { message in
            message.status = status
            message.errorMessage = error.map(Self.describe)
        }
        conversation.updatedAt = Date()
        activity = .idle
        streamTask = nil
        needsSignIn = (error as? ChatBackendError)?.requiresSignIn == true || (error as? AuthError) == .sessionExpired || (error as? AuthError) == .notSignedIn
        app?.sessionStoppedStreaming(self)
        persist()
        if status == .complete {
            completedCount += 1
            generateTitleIfNeeded()
        }
    }

    private func generateTitleIfNeeded() {
        guard !isTemporary, conversation.title.isEmpty, let app, app.settings.autoGenerateTitles,
              let userMessage = conversation.messages.first(where: { $0.role == .user }),
              let reply = conversation.messages.first(where: { $0.role == .assistant && $0.status == .complete && !$0.text.isEmpty })
        else { return }

        let conversationID = conversation.id
        let model = app.model(for: conversation.modelID)
        let backend = app.backend
        let fallback = Conversation.fallbackTitle(from: userMessage.text)
        Task { [weak self, weak app] in
            let generated = try? await backend.generateTitle(model: model, userText: userMessage.text, assistantText: reply.text)
            let title = generated ?? fallback
            guard !title.isEmpty else { return }
            // Rename through the store so a newer copy of the chat is never overwritten.
            if let app, let saved = app.store.conversation(id: conversationID), saved.title.isEmpty {
                app.store.rename(id: conversationID, to: title)
            }
            if let self, self.conversation.title.isEmpty {
                self.conversation.title = title
            }
        }
    }

    private func recordReasoningDuration(_ id: UUID, since start: Date?) {
        guard let start else { return }
        updateMessage(id) { message in
            if message.reasoningDuration == nil {
                message.reasoningDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func updateMessage(_ id: UUID, _ transform: (inout ChatMessage) -> Void) {
        guard let index = conversation.messages.lastIndex(where: { $0.id == id }) else { return }
        transform(&conversation.messages[index])
    }

    private func message(_ id: UUID) -> ChatMessage? {
        conversation.messages.last { $0.id == id }
    }

    private func persist() {
        guard !isTemporary, !conversation.messages.isEmpty else { return }
        app?.store.save(conversation)
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return String(localized: "You appear to be offline.")
            case .timedOut:
                return String(localized: "The request timed out.")
            default:
                return urlError.localizedDescription
            }
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
