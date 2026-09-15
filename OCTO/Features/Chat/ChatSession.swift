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

    /// Download of the account copy of the chat.
    enum AccountLoad: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let id: UUID
    let isTemporary: Bool
    private(set) var conversation: Conversation
    private(set) var activity: Activity = .idle
    private(set) var needsSignIn = false
    private(set) var accountLoad: AccountLoad = .idle
    /// The reply being written. Its text is observed by its own view only.
    private(set) var live: LiveReply?
    var draft = ""
    var pendingAttachments: [PendingAttachment] = []
    /// While voice mode is open, replies are written to be read aloud.
    var isVoiceConversation = false

    /// Counters used as haptic feedback triggers.
    private(set) var sentCount = 0
    private(set) var completedCount = 0
    /// The message sent last, which the chat brings to the top of the screen.
    private(set) var lastSentMessageID: UUID?

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

    /// A new chat with nothing in it yet. An account chat whose messages are still downloading doesn't count.
    var isBlank: Bool {
        conversation.messages.isEmpty && !conversation.isAccountChat
    }

    var canSend: Bool {
        guard !isStreaming, !isWaitingForAccountCopy else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    var model: ModelDescriptor {
        app?.model(for: conversation.modelID) ?? ModelCatalog.chatGPTFallback[0]
    }

    /// Without a subscription there's no choice: the model's own thinking level is used.
    var reasoningEffort: String? {
        model.resolvedEffort(preferred: app?.allowsModelChoice == false ? nil : conversation.reasoningEffort)
    }

    /// First message written in OCTO after the account copy of the chat.
    var firstLocalMessageID: UUID? {
        guard conversation.isAccountChat,
              let index = conversation.messages.firstIndex(where: { $0.remoteID == nil }),
              index > 0
        else { return nil }
        return conversation.messages[index].id
    }

    /// Everything received for a message, including text still waiting to appear.
    func fullText(of message: ChatMessage) -> String {
        if let live, live.messageID == message.id {
            return live.receivedText
        }
        return message.text
    }

    /// Messages of the account copy stay as they are: only replies written in OCTO can be edited or regenerated.
    func canModify(_ message: ChatMessage) -> Bool {
        !isStreaming && message.remoteID == nil
    }

    private var isWaitingForAccountCopy: Bool {
        conversation.isAccountChat && conversation.messages.isEmpty
    }

    // MARK: Account

    /// Shows the account copy of the chat, downloading it when it's missing or has changed.
    func loadFromAccount(force: Bool = false) async {
        guard let app, conversation.isAccountChat, !isTemporary, !isStreaming, accountLoad != .loading else { return }
        if !force, !conversation.messages.isEmpty, let downloaded = conversation.remoteUpdatedAt {
            let listed = app.store.summary(id: id)?.remoteUpdatedAt
            if listed.map({ $0 <= downloaded }) ?? true { return }
        }
        accountLoad = .loading
        do {
            let downloaded = try await app.store.downloadAccountChat(id: id)
            accountLoad = .loaded
            guard var downloaded, !isStreaming else { return }
            downloaded.modelID = conversation.modelID ?? downloaded.modelID
            downloaded.reasoningEffort = conversation.reasoningEffort ?? downloaded.reasoningEffort
            downloaded.webSearchEnabled = conversation.webSearchEnabled
            conversation = downloaded
        } catch {
            DevLog.log("chats", "Downloading \(conversation.remoteID ?? "?") failed: \(DevLog.describe(error))", level: error.isCancellation ? .debug : .error)
            // Leaving the chat cancels the download: it simply starts again next time.
            accountLoad = error.isCancellation ? .idle : .failed(Self.describe(error))
        }
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

    func rename(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.title = trimmed
        guard !isTemporary, let app else { return }
        if conversation.messages.isEmpty {
            app.store.rename(id: id, to: trimmed)
        } else {
            persist()
            app.store.renameInAccount(id: id, title: trimmed)
        }
    }

    func setPinned(_ isPinned: Bool) {
        conversation.isPinned = isPinned
        guard !isTemporary, let app else { return }
        if conversation.messages.isEmpty {
            app.store.setPinned(isPinned, id: id)
        } else {
            persist()
        }
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
        let message = ChatMessage(role: .user, text: text, attachments: attachments)
        conversation.messages.append(message)
        conversation.updatedAt = Date()
        lastSentMessageID = message.id
        sentCount += 1
        startAssistantTurn()
    }

    /// Sends a transcript from voice mode, leaving the composer draft untouched.
    func sendVoiceMessage(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !isWaitingForAccountCopy, !text.isEmpty else { return }
        let message = ChatMessage(role: .user, text: text)
        conversation.messages.append(message)
        conversation.updatedAt = Date()
        lastSentMessageID = message.id
        sentCount += 1
        startAssistantTurn()
    }

    func stop() {
        streamTask?.cancel()
    }

    func regenerate(_ messageID: UUID, using model: ModelDescriptor? = nil) {
        guard !isStreaming,
              let index = conversation.messages.firstIndex(where: { $0.id == messageID }),
              conversation.messages[index].role == .assistant,
              conversation.messages[index].remoteID == nil
        else { return }
        if let model {
            selectModel(model)
        }
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
              conversation.messages[index].role == .user,
              conversation.messages[index].remoteID == nil
        else { return }
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !conversation.messages[index].attachments.isEmpty else { return }
        conversation.messages[index].text = text
        conversation.messages.removeSubrange((index + 1)...)
        conversation.updatedAt = Date()
        lastSentMessageID = messageID
        sentCount += 1
        startAssistantTurn()
    }

    /// Temporary chats leave nothing behind.
    func discardIfTemporary() {
        guard isTemporary, let app else { return }
        stop()
        for attachment in conversation.messages.flatMap(\.attachments) {
            if let url = app.store.files.attachmentURL(attachment.storedFileName) {
                try? FileManager.default.removeItem(at: url)
            }
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
        let reply = LiveReply(messageID: assistant.id, paced: !(app.developer.isEnabled && app.developer.disablesTextPacing))
        live = reply
        activity = .waiting
        persist()
        app.sessionStartedStreaming(self)

        let store = app.store
        let backend = app.backend
        let effort = model.resolvedEffort(preferred: app.allowsModelChoice ? conversation.reasoningEffort : nil)
        let instructions = SystemPrompt.make(personal: app.account.personalContext, spokenReplies: isVoiceConversation)
        let webSearch = conversation.webSearchEnabled && model.supportsWebSearch
        let summaries = app.settings.showReasoning && model.supportsReasoningSummaries
        let cacheKey = conversation.id.uuidString
        DevLog.log("reply", "Started with \(model.id), thinking \(effort ?? "none"), web search \(webSearch ? "on" : "off"), \(history.count) messages")

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
            await self?.consume(backend.stream(request), reply: reply)
        }
    }

    private func consume(_ stream: AsyncThrowingStream<ResponseStreamUpdate, Error>, reply: LiveReply) async {
        var reasoningStartedAt: Date?
        var failure: Error?
        reply.start()

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
                    reply.receiveReasoning(delta)
                    if activity != .writing { activity = .thinking }
                case .reasoningSectionBreak:
                    reply.startReasoningSection()
                case .reasoningFinished:
                    reply.recordReasoningDuration(since: reasoningStartedAt)
                case .textDelta(let delta):
                    if activity != .writing {
                        reply.recordReasoningDuration(since: reasoningStartedAt)
                        activity = .writing
                    }
                    reply.receiveText(delta)
                case .webSearchStarted:
                    activity = .searching
                case .webSearchFinished(let query):
                    reply.addSearchQuery(query)
                    if activity == .searching { activity = .thinking }
                case .citations(let citations):
                    reply.addCitations(citations)
                case .completed(let usage):
                    reply.usage = usage
                }
            }
        } catch {
            failure = error
        }

        let cancelled = Task.isCancelled || failure is CancellationError || (failure as? URLError)?.code == .cancelled
        if cancelled {
            reply.revealEverything()
            finishTurn(reply, status: .cancelled, error: nil)
        } else {
            // Stopping while the end of a complete reply is still appearing keeps the whole reply.
            await reply.finishRevealing()
            finishTurn(reply, status: failure == nil ? .complete : .failed, error: failure)
        }
    }

    private func finishTurn(_ reply: LiveReply, status: ChatMessage.Status, error: Error?) {
        reply.stop()
        updateMessage(reply.messageID) { message in
            message.text = reply.receivedText
            message.reasoning = reply.receivedReasoning
            message.reasoningDuration = reply.reasoningDuration
            message.searchQueries = reply.searchQueries
            message.citations = reply.citations
            message.usage = reply.usage
            message.status = status
            message.errorMessage = error.map(Self.describe)
        }
        if live === reply {
            live = nil
        }
        conversation.updatedAt = Date()
        activity = .idle
        streamTask = nil
        needsSignIn = (error as? ChatBackendError)?.requiresSignIn == true || (error as? AuthError) == .sessionExpired || (error as? AuthError) == .notSignedIn
        app?.sessionStoppedStreaming(self, reply: reply.receivedText, failed: status == .failed)

        var summary = "Finished \(status.rawValue), \(reply.receivedText.count) characters"
        if let usage = reply.usage {
            summary += ", tokens in \(usage.inputTokens) (cached \(usage.cachedInputTokens)), out \(usage.outputTokens), reasoning \(usage.reasoningTokens)"
        }
        if let error {
            summary += ": \(DevLog.describe(error))"
        }
        DevLog.log("reply", summary, level: status == .failed ? .error : .info)

        persist()
        if status == .complete {
            completedCount += 1
            generateTitleIfNeeded()
        }
    }

    private func generateTitleIfNeeded() {
        guard !isTemporary, !conversation.isAccountChat, conversation.title.isEmpty, let app, app.settings.autoGenerateTitles,
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

    private func updateMessage(_ id: UUID, _ transform: (inout ChatMessage) -> Void) {
        guard let index = conversation.messages.lastIndex(where: { $0.id == id }) else { return }
        transform(&conversation.messages[index])
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
