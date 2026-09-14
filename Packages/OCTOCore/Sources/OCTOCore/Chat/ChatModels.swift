import Foundation

public struct Citation: Codable, Hashable, Sendable, Identifiable {
    public var url: String
    public var title: String?

    public var id: String { url }

    public init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }

    /// Host without a leading "www.", for compact source chips.
    public var host: String? {
        guard let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int

    public init(inputTokens: Int = 0, cachedInputTokens: Int = 0, outputTokens: Int = 0, reasoningTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }
}

public struct MessageAttachment: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case image
        case text
    }

    public var id: UUID
    public var kind: Kind
    /// File name inside the app's attachments directory; empty for files that stayed in the ChatGPT account.
    public var storedFileName: String
    /// Original file name shown to the user (text files).
    public var displayName: String?
    public var mimeType: String
    public var byteCount: Int

    public init(id: UUID = UUID(), kind: Kind, storedFileName: String, displayName: String? = nil, mimeType: String, byteCount: Int) {
        self.id = id
        self.kind = kind
        self.storedFileName = storedFileName
        self.displayName = displayName
        self.mimeType = mimeType
        self.byteCount = byteCount
    }

    /// False for placeholders of account attachments, which have no file on the device.
    public var isStoredOnDevice: Bool {
        !storedFileName.isEmpty && !storedFileName.contains("/") && storedFileName != ".." && storedFileName != "."
    }
}

public struct ChatMessage: Codable, Hashable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public enum Status: String, Codable, Sendable {
        case complete
        case streaming
        case failed
        case cancelled
    }

    public var id: UUID
    public var role: Role
    public var text: String
    public var reasoning: String
    public var reasoningDuration: TimeInterval?
    public var attachments: [MessageAttachment]
    public var citations: [Citation]
    public var searchQueries: [String]
    public var modelID: String?
    public var status: Status
    public var errorMessage: String?
    public var usage: TokenUsage?
    public var createdAt: Date
    /// Id of the message in the ChatGPT account; nil for messages written in OCTO.
    public var remoteID: String?

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String = "",
        reasoning: String = "",
        reasoningDuration: TimeInterval? = nil,
        attachments: [MessageAttachment] = [],
        citations: [Citation] = [],
        searchQueries: [String] = [],
        modelID: String? = nil,
        status: Status = .complete,
        errorMessage: String? = nil,
        usage: TokenUsage? = nil,
        createdAt: Date = Date(),
        remoteID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.reasoningDuration = reasoningDuration
        self.attachments = attachments
        self.citations = citations
        self.searchQueries = searchQueries
        self.modelID = modelID
        self.status = status
        self.errorMessage = errorMessage
        self.usage = usage
        self.createdAt = createdAt
        self.remoteID = remoteID
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, reasoning, reasoningDuration, attachments, citations, searchQueries
        case modelID, status, errorMessage, usage, createdAt, remoteID
    }

    // Lenient decoding keeps old files readable when fields are added later.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .user
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        reasoningDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .reasoningDuration)
        attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        citations = try container.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        searchQueries = try container.decodeIfPresent([String].self, forKey: .searchQueries) ?? []
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        status = (try? container.decodeIfPresent(Status.self, forKey: .status)) ?? .complete
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        usage = try? container.decodeIfPresent(TokenUsage.self, forKey: .usage)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
    }
}

public struct Conversation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var modelID: String?
    public var reasoningEffort: String?
    public var webSearchEnabled: Bool
    public var messages: [ChatMessage]
    /// Id of the chat in the ChatGPT account; nil for chats created in OCTO.
    public var remoteID: String?
    /// ChatGPT project (`g-p-…`) the chat belongs to.
    public var projectID: String?
    /// Last update of the account copy that was downloaded.
    public var remoteUpdatedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        modelID: String? = nil,
        reasoningEffort: String? = nil,
        webSearchEnabled: Bool = false,
        messages: [ChatMessage] = [],
        remoteID: String? = nil,
        projectID: String? = nil,
        remoteUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
        self.webSearchEnabled = webSearchEnabled
        self.messages = messages
        self.remoteID = remoteID
        self.projectID = projectID
        self.remoteUpdatedAt = remoteUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, isPinned, modelID, reasoningEffort, webSearchEnabled, messages
        case remoteID, projectID, remoteUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        remoteUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .remoteUpdatedAt)
    }

    /// True for chats that come from the ChatGPT account.
    public var isAccountChat: Bool { remoteID != nil }

    /// Title to display, falling back to the first user message.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Conversation.fallbackTitle(from: messages.first { $0.role == .user }?.text ?? "")
    }

    public var summary: ConversationSummary {
        let last = messages.last { !$0.text.isEmpty }
        let preview = MarkdownPlainText.strip(last?.text ?? "")
        return ConversationSummary(
            id: id,
            title: displayTitle,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: isPinned,
            preview: String(preview.prefix(160)),
            remoteID: remoteID,
            projectID: projectID,
            remoteUpdatedAt: remoteUpdatedAt
        )
    }

    public static func fallbackTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map { MarkdownPlainText.strip(String($0)) } ?? ""
        let collapsed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= 48 { return collapsed }
        return String(collapsed.prefix(47)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public struct ConversationSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var preview: String
    public var remoteID: String?
    public var projectID: String?
    public var remoteUpdatedAt: Date?

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool,
        preview: String,
        remoteID: String? = nil,
        projectID: String? = nil,
        remoteUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.preview = preview
        self.remoteID = remoteID
        self.projectID = projectID
        self.remoteUpdatedAt = remoteUpdatedAt
    }

    public var isAccountChat: Bool { remoteID != nil }
}
