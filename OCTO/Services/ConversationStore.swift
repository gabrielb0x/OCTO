import Foundation
import Observation
import OCTOCore

/// Content picked in the composer, kept in memory until the message is sent.
struct PendingAttachment: Identifiable, Equatable {
    enum Content: Equatable {
        case image(Data)
        case text(String)
    }

    let id = UUID()
    var name: String
    var content: Content
}

/// JSON files in Application Support. Writes happen on a serial background queue.
final class ConversationFiles: @unchecked Sendable {
    let conversationsDirectory: URL
    let attachmentsDirectory: URL
    private let queue = DispatchQueue(label: "com.gabrielb0x.octo.storage", qos: .utility)

    init(folderName: String = "OCTO", startEmpty: Bool = false) {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        let root = base.appendingPathComponent(folderName, isDirectory: true)
        if startEmpty {
            try? fileManager.removeItem(at: root)
        }
        conversationsDirectory = root.appendingPathComponent("Conversations", isDirectory: true)
        attachmentsDirectory = root.appendingPathComponent("Attachments", isDirectory: true)
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    private var indexURL: URL {
        conversationsDirectory.appendingPathComponent("index.json")
    }

    private func fileURL(for id: UUID) -> URL {
        conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func attachmentURL(_ name: String) -> URL {
        attachmentsDirectory.appendingPathComponent(name)
    }

    func loadIndex() -> [ConversationSummary]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode([ConversationSummary].self, from: data)
    }

    func loadConversation(_ id: UUID) -> Conversation? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(Conversation.self, from: data)
    }

    func conversationIDs() -> [UUID] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            url.pathExtension == "json" ? UUID(uuidString: url.deletingPathExtension().lastPathComponent) : nil
        }
    }

    func write(_ conversation: Conversation?, index: [ConversationSummary]) {
        queue.async { [self] in
            let encoder = JSONEncoder()
            if let conversation, let data = try? encoder.encode(conversation) {
                try? data.write(to: fileURL(for: conversation.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            if let data = try? encoder.encode(index) {
                try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    func delete(_ id: UUID, attachmentNames: [String], index: [ConversationSummary]) {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: fileURL(for: id))
            for name in attachmentNames {
                try? FileManager.default.removeItem(at: attachmentURL(name))
            }
            if let data = try? JSONEncoder().encode(index) {
                try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    func deleteEverything() {
        queue.async { [self] in
            for directory in [conversationsDirectory, attachmentsDirectory] {
                let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    func saveAttachment(_ data: Data, fileExtension: String) -> String? {
        let name = "\(UUID().uuidString).\(fileExtension)"
        do {
            try data.write(to: attachmentURL(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            return nil
        }
    }

    /// Blocks until queued writes are on disk.
    func flush() {
        queue.sync {}
    }
}

/// Local chat history. Nothing is stored on OpenAI's servers (`store: false`).
@MainActor
@Observable
final class ConversationStore {
    private(set) var summaries: [ConversationSummary] = []

    let files: ConversationFiles
    @ObservationIgnored private var cache: [UUID: Conversation] = [:]
    @ObservationIgnored private var searchCorpus: [UUID: String] = [:]
    @ObservationIgnored private var corpusLoaded = false

    init(files: ConversationFiles = ConversationFiles()) {
        self.files = files
        if let index = files.loadIndex() {
            summaries = index
        } else {
            summaries = files.conversationIDs().compactMap { files.loadConversation($0)?.summary }
            if !summaries.isEmpty {
                files.write(nil, index: summaries)
            }
        }
        sortSummaries()
    }

    func conversation(id: UUID) -> Conversation? {
        if let cached = cache[id] { return cached }
        guard var conversation = files.loadConversation(id) else { return nil }
        // Messages interrupted by the app being closed mid-stream.
        for index in conversation.messages.indices where conversation.messages[index].status == .streaming {
            conversation.messages[index].status = .cancelled
        }
        cache[id] = conversation
        return conversation
    }

    func save(_ conversation: Conversation) {
        guard !conversation.messages.isEmpty else { return }
        cache[conversation.id] = conversation
        let summary = conversation.summary
        if let index = summaries.firstIndex(where: { $0.id == conversation.id }) {
            summaries[index] = summary
        } else {
            summaries.append(summary)
        }
        sortSummaries()
        if corpusLoaded {
            searchCorpus[conversation.id] = Self.corpus(for: conversation)
        }
        files.write(conversation, index: summaries)
    }

    func delete(id: UUID) {
        let conversation = cache[id] ?? files.loadConversation(id)
        let names = conversation?.messages.flatMap { $0.attachments.map(\.storedFileName) } ?? []
        cache[id] = nil
        searchCorpus[id] = nil
        summaries.removeAll { $0.id == id }
        files.delete(id, attachmentNames: names, index: summaries)
    }

    func deleteAll() {
        cache.removeAll()
        searchCorpus.removeAll()
        summaries.removeAll()
        files.deleteEverything()
    }

    func setPinned(_ isPinned: Bool, id: UUID) {
        guard var conversation = conversation(id: id) else { return }
        conversation.isPinned = isPinned
        save(conversation)
    }

    func rename(id: UUID, to title: String) {
        guard var conversation = conversation(id: id) else { return }
        conversation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save(conversation)
    }

    func search(_ query: String) -> [ConversationSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return summaries }
        loadCorpusIfNeeded()
        return summaries.filter { summary in
            summary.title.lowercased().contains(needle) || (searchCorpus[summary.id]?.contains(needle) ?? false)
        }
    }

    // MARK: Attachments

    func storeAttachment(_ pending: PendingAttachment) -> MessageAttachment? {
        switch pending.content {
        case .image(let data):
            guard let name = files.saveAttachment(data, fileExtension: "jpg") else { return nil }
            return MessageAttachment(kind: .image, storedFileName: name, displayName: pending.name, mimeType: "image/jpeg", byteCount: data.count)
        case .text(let text):
            let data = Data(text.utf8)
            guard let name = files.saveAttachment(data, fileExtension: "txt") else { return nil }
            return MessageAttachment(kind: .text, storedFileName: name, displayName: pending.name, mimeType: "text/plain", byteCount: data.count)
        }
    }

    nonisolated func payload(for attachment: MessageAttachment) -> AttachmentPayload? {
        guard let data = try? Data(contentsOf: files.attachmentURL(attachment.storedFileName)) else { return nil }
        switch attachment.kind {
        case .image:
            return .imageDataURL("data:\(attachment.mimeType);base64,\(data.base64EncodedString())")
        case .text:
            return .text(String(decoding: data, as: UTF8.self))
        }
    }

    func markdownExport(of conversation: Conversation) -> String {
        var lines = ["# \(conversation.displayTitle)", ""]
        for message in conversation.messages where !message.text.isEmpty {
            let author = message.role == .user ? String(localized: "You") : "OCTO"
            lines.append("**\(author)**")
            lines.append("")
            lines.append(message.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private func loadCorpusIfNeeded() {
        guard !corpusLoaded else { return }
        corpusLoaded = true
        for summary in summaries {
            if let conversation = cache[summary.id] ?? files.loadConversation(summary.id) {
                searchCorpus[summary.id] = Self.corpus(for: conversation)
            }
        }
    }

    private static func corpus(for conversation: Conversation) -> String {
        String(conversation.messages.map(\.text).joined(separator: "\n").prefix(50_000)).lowercased()
    }

    private func sortSummaries() {
        summaries.sort { $0.updatedAt > $1.updatedAt }
    }
}
