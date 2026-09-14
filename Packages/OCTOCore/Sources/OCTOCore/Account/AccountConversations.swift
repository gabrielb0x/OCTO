import Foundation

/// A chat as listed by `GET /conversations` or inside a project.
public struct RemoteConversationSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isPinned: Bool
    public var isArchived: Bool
    /// Project (`g-p-…`) the chat belongs to.
    public var projectID: String?

    public init(id: String, title: String, createdAt: Date? = nil, updatedAt: Date? = nil, isPinned: Bool = false, isArchived: Bool = false, projectID: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.projectID = projectID
    }

    init?(json: [String: Any]) {
        guard let id = JSONValue.string(json["id"]) ?? JSONValue.string(json["conversation_id"]), !id.isEmpty else { return nil }
        let createdAt = FlexibleDate.parse(json["create_time"])
        self.init(
            id: id,
            title: JSONValue.string(json["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            createdAt: createdAt,
            updatedAt: FlexibleDate.parse(json["update_time"]) ?? createdAt,
            isPinned: FlexibleDate.parse(json["pinned_time"]) != nil || JSONValue.bool(json["is_starred"]) == true,
            isArchived: JSONValue.bool(json["is_archived"]) ?? false,
            projectID: RemoteConversationParser.projectID(json["gizmo_id"])
        )
    }
}

public struct RemoteConversationPage: Equatable, Sendable {
    public var items: [RemoteConversationSummary]
    public var total: Int?
    /// Next page of a project's chats; nil at the end.
    public var cursor: String?

    public init(items: [RemoteConversationSummary], total: Int? = nil, cursor: String? = nil) {
        self.items = items
        self.total = total
        self.cursor = cursor
    }

    public static func parse(_ data: Data) -> RemoteConversationPage? {
        guard let object = JSONValue.object(data), let items = object["items"] as? [[String: Any]] else { return nil }
        return RemoteConversationPage(
            items: items.compactMap(RemoteConversationSummary.init(json:)),
            total: JSONValue.int(object["total"]),
            cursor: RemoteConversationParser.cursor(object["cursor"])
        )
    }
}

public struct RemoteProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// ChatGPT icon name, such as "folder" or "graduation-cap".
    public var iconName: String?
    /// Hex color such as "#0285FF".
    public var colorHex: String?
    public var conversations: [RemoteConversationSummary]
    public var conversationsCursor: String?

    public init(id: String, name: String, iconName: String? = nil, colorHex: String? = nil, conversations: [RemoteConversationSummary] = [], conversationsCursor: String? = nil) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.conversations = conversations
        self.conversationsCursor = conversationsCursor
    }
}

/// `GET /gizmos/snorlax/sidebar`: projects with their latest chats.
public enum RemoteProjectList {
    public static func parse(_ data: Data) -> [RemoteProject]? {
        guard let object = JSONValue.object(data), let items = object["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            let wrapper = item["gizmo"] as? [String: Any] ?? [:]
            let gizmo = wrapper["gizmo"] as? [String: Any] ?? wrapper
            guard let id = JSONValue.string(gizmo["id"]), !id.isEmpty else { return nil }
            let display = gizmo["display"] as? [String: Any] ?? [:]
            let conversations = item["conversations"] as? [String: Any] ?? [:]
            let summaries = (conversations["items"] as? [[String: Any]] ?? []).compactMap { json -> RemoteConversationSummary? in
                guard var summary = RemoteConversationSummary(json: json) else { return nil }
                summary.projectID = summary.projectID ?? id
                return summary
            }
            return RemoteProject(
                id: id,
                name: JSONValue.string(display["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                iconName: JSONValue.string(display["emoji"]),
                colorHex: JSONValue.string(display["theme"]),
                conversations: summaries,
                conversationsCursor: RemoteConversationParser.cursor(conversations["cursor"])
            )
        }
    }
}

/// One visible turn of an account chat.
public struct RemoteMessage: Equatable, Sendable {
    public var id: String
    public var role: ChatMessage.Role
    public var text: String
    public var reasoning: String
    public var reasoningDuration: TimeInterval?
    public var citations: [Citation]
    /// Images are shown as placeholders: their files stay in the account.
    public var imageCount: Int
    public var fileNames: [String]
    public var createdAt: Date?

    public init(
        id: String,
        role: ChatMessage.Role,
        text: String = "",
        reasoning: String = "",
        reasoningDuration: TimeInterval? = nil,
        citations: [Citation] = [],
        imageCount: Int = 0,
        fileNames: [String] = [],
        createdAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.reasoningDuration = reasoningDuration
        self.citations = citations
        self.imageCount = imageCount
        self.fileNames = fileNames
        self.createdAt = createdAt
    }

    var hasVisibleContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageCount > 0 || !fileNames.isEmpty
    }
}

public struct RemoteConversation: Equatable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var projectID: String?
    public var messages: [RemoteMessage]

    public init(id: String, title: String, createdAt: Date? = nil, updatedAt: Date? = nil, projectID: String? = nil, messages: [RemoteMessage]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectID = projectID
        self.messages = messages
    }
}

/// Turns the message tree of `GET /conversation/{id}` into the turns shown in the chat:
/// the branch ending at `current_node`, without hidden context, tool calls or tool output,
/// and with each assistant turn (thoughts, tool steps, answer) merged into one message.
public enum RemoteConversationParser {
    public static func parse(_ data: Data, id fallbackID: String) -> RemoteConversation? {
        guard let object = JSONValue.object(data), let mapping = object["mapping"] as? [String: Any] else { return nil }
        var nodes: [String: [String: Any]] = [:]
        for (key, value) in mapping {
            if let node = value as? [String: Any] { nodes[key] = node }
        }

        var turns: [RemoteMessage] = []
        for nodeID in branch(in: nodes, endingAt: JSONValue.string(object["current_node"])) {
            guard let message = nodes[nodeID]?["message"] as? [String: Any],
                  let piece = piece(from: message, nodeID: nodeID)
            else { continue }
            append(piece, to: &turns)
        }

        let createdAt = FlexibleDate.parse(object["create_time"])
        return RemoteConversation(
            id: JSONValue.string(object["conversation_id"]) ?? JSONValue.string(object["id"]) ?? fallbackID,
            title: JSONValue.string(object["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            createdAt: createdAt,
            updatedAt: FlexibleDate.parse(object["update_time"]) ?? createdAt,
            projectID: projectID(object["gizmo_id"]),
            messages: turns.filter(\.hasVisibleContent)
        )
    }

    static func branch(in nodes: [String: [String: Any]], endingAt currentNode: String?) -> [String] {
        var path: [String] = []
        var visited = Set<String>()
        if let currentNode, nodes[currentNode] != nil {
            var cursor: String? = currentNode
            while let id = cursor, let node = nodes[id], visited.insert(id).inserted {
                path.append(id)
                cursor = JSONValue.string(node["parent"])
            }
            return path.reversed()
        }
        // Without a current node, follow the newest child from the root.
        let root = nodes.keys.sorted().first { id in
            guard let parent = JSONValue.string(nodes[id]?["parent"]) else { return true }
            return nodes[parent] == nil
        }
        var cursor = root
        while let id = cursor, let node = nodes[id], visited.insert(id).inserted {
            path.append(id)
            cursor = (node["children"] as? [Any])?.compactMap { JSONValue.string($0) }.last
        }
        return path
    }

    static func piece(from message: [String: Any], nodeID: String) -> RemoteMessage? {
        let metadata = message["metadata"] as? [String: Any] ?? [:]
        if JSONValue.bool(metadata["is_visually_hidden_from_conversation"]) == true { return nil }
        let author = message["author"] as? [String: Any] ?? [:]
        let content = message["content"] as? [String: Any] ?? [:]
        let contentType = JSONValue.string(content["content_type"]) ?? "text"
        let recipient = JSONValue.string(message["recipient"]) ?? "all"
        let id = JSONValue.string(message["id"]) ?? nodeID
        let createdAt = FlexibleDate.parse(message["create_time"])

        switch JSONValue.string(author["role"]) {
        case "user"?:
            guard contentType == "text" || contentType == "multimodal_text" else { return nil }
            let parts = textAndImages(in: content)
            let files = (metadata["attachments"] as? [[String: Any]] ?? []).compactMap { attachment -> String? in
                let mimeType = JSONValue.string(attachment["mime_type"])?.lowercased() ?? ""
                guard !mimeType.hasPrefix("image/") else { return nil }
                return JSONValue.string(attachment["name"])
            }
            return RemoteMessage(id: id, role: .user, text: parts.text, imageCount: parts.images, fileNames: files, createdAt: createdAt)

        case "assistant"?:
            switch contentType {
            case "text", "multimodal_text":
                guard recipient == "all" else { return nil }
                let parts = textAndImages(in: content)
                let cleaned = CitationCleaner.clean(parts.text, references: metadata["content_references"] as? [[String: Any]] ?? [])
                var citations = legacyCitations(in: metadata)
                for citation in cleaned.citations where !citations.contains(where: { $0.url == citation.url }) {
                    citations.append(citation)
                }
                return RemoteMessage(id: id, role: .assistant, text: cleaned.text, citations: citations, imageCount: parts.images, createdAt: createdAt)
            case "thoughts":
                let thoughts = (content["thoughts"] as? [[String: Any]] ?? []).compactMap { thought -> String? in
                    let summary = JSONValue.string(thought["summary"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let body = JSONValue.string(thought["content"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if summary.isEmpty { return body.isEmpty ? nil : body }
                    return body.isEmpty ? "**\(summary)**" : "**\(summary)**\n\n\(body)"
                }
                return RemoteMessage(
                    id: id,
                    role: .assistant,
                    reasoning: thoughts.joined(separator: "\n\n"),
                    reasoningDuration: JSONValue.double(metadata["finished_duration_sec"]),
                    createdAt: createdAt
                )
            case "reasoning_recap":
                return RemoteMessage(id: id, role: .assistant, reasoningDuration: JSONValue.double(metadata["finished_duration_sec"]), createdAt: createdAt)
            default:
                return nil
            }

        case "tool"?:
            // Generated images come back from the image tool.
            guard contentType == "multimodal_text" else { return nil }
            let images = textAndImages(in: content).images
            return images > 0 ? RemoteMessage(id: id, role: .assistant, imageCount: images, createdAt: createdAt) : nil

        default:
            return nil
        }
    }

    static func append(_ piece: RemoteMessage, to turns: inout [RemoteMessage]) {
        guard piece.role == .assistant, var merged = turns.last, merged.role == .assistant else {
            turns.append(piece)
            return
        }
        merged.text = [merged.text, piece.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        merged.reasoning = [merged.reasoning, piece.reasoning].filter { !$0.isEmpty }.joined(separator: "\n\n")
        merged.reasoningDuration = [merged.reasoningDuration, piece.reasoningDuration].compactMap { $0 }.max()
        for citation in piece.citations where !merged.citations.contains(where: { $0.url == citation.url }) {
            merged.citations.append(citation)
        }
        merged.imageCount += piece.imageCount
        turns[turns.count - 1] = merged
    }

    static func textAndImages(in content: [String: Any]) -> (text: String, images: Int) {
        var texts: [String] = []
        var images = 0
        if let parts = content["parts"] as? [Any] {
            for part in parts {
                if let text = part as? String {
                    texts.append(text)
                } else if let object = part as? [String: Any] {
                    if JSONValue.string(object["content_type"]) == "image_asset_pointer" {
                        images += 1
                    } else if let text = JSONValue.string(object["text"]) {
                        texts.append(text)
                    }
                }
            }
        } else if let text = JSONValue.string(content["text"]) {
            texts.append(text)
        }
        return (texts.filter { !$0.isEmpty }.joined(separator: "\n\n"), images)
    }

    static func legacyCitations(in metadata: [String: Any]) -> [Citation] {
        var citations: [Citation] = []
        for entry in metadata["citations"] as? [[String: Any]] ?? [] {
            let info = entry["metadata"] as? [String: Any] ?? entry
            guard let url = JSONValue.string(info["url"]), !url.isEmpty, !citations.contains(where: { $0.url == url }) else { continue }
            citations.append(Citation(url: url, title: JSONValue.string(info["title"])))
        }
        return citations
    }

    static func projectID(_ value: Any?) -> String? {
        guard let id = JSONValue.string(value), id.hasPrefix("g-p-") else { return nil }
        return id
    }

    static func cursor(_ value: Any?) -> String? {
        JSONValue.string(value) ?? JSONValue.int(value).map(String.init)
    }
}

/// Removes ChatGPT's inline reference markers from a reply and collects its web sources.
public enum CitationCleaner {
    public static func clean(_ text: String, references: [[String: Any]]) -> (text: String, citations: [Citation]) {
        var citations: [Citation] = []
        func add(_ item: [String: Any]) {
            guard let url = JSONValue.string(item["url"]), !url.isEmpty, !citations.contains(where: { $0.url == url }) else { return }
            citations.append(Citation(url: url, title: JSONValue.string(item["title"])))
        }
        for reference in references {
            for item in reference["items"] as? [[String: Any]] ?? [] {
                add(item)
                for site in item["supporting_websites"] as? [[String: Any]] ?? [] {
                    add(site)
                }
            }
            for source in reference["sources"] as? [[String: Any]] ?? [] {
                add(source)
            }
        }

        var output = replaceMarkers(in: text)
        // Older browsing replies cite sources as 【12†source】.
        output = output.replacingOccurrences(of: "【[^】\n]*†[^】\n]*】", with: "", options: .regularExpression)
        return (output, citations)
    }

    /// Markers look like U+E200 kind U+E202 payload U+E201, e.g. a citation `cite…turn0search3`
    /// or an entity `entity…["city","Lyon"]` whose name must stay in the sentence.
    static func replaceMarkers(in text: String) -> String {
        guard text.contains("\u{E200}"),
              let regex = try? NSRegularExpression(pattern: " ?\u{E200}([^\u{E201}\u{E202}]*)(?:\u{E202}([^\u{E201}]*))?\u{E201}")
        else { return text }

        let source = text as NSString
        var result = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            let kind = match.range(at: 1).location == NSNotFound ? "" : source.substring(with: match.range(at: 1))
            let payload = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            if let visible = visibleText(kind: kind, payload: payload) {
                result += (source.substring(with: match.range).hasPrefix(" ") ? " " : "") + visible
            }
            location = match.range.location + match.range.length
        }
        result += source.substring(from: location)
        return result
    }

    static func visibleText(kind: String, payload: String) -> String? {
        guard kind == "entity",
              let data = payload.data(using: .utf8),
              let parts = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return nil }
        let strings = parts.compactMap { $0 as? String }.filter { !$0.isEmpty }
        return strings.count > 1 ? strings[1] : strings.first
    }
}

/// Converts account chats into OCTO conversations.
public enum AccountChatMapper {
    public static func summary(from remote: RemoteConversationSummary, existing: ConversationSummary?, now: Date = Date()) -> ConversationSummary {
        let remoteUpdatedAt = remote.updatedAt ?? remote.createdAt
        let updatedAt = [remoteUpdatedAt, existing?.updatedAt].compactMap { $0 }.max() ?? now
        return ConversationSummary(
            id: existing?.id ?? RemoteIdentifier.localID(for: remote.id),
            title: remote.title.isEmpty ? (existing?.title ?? "") : remote.title,
            createdAt: remote.createdAt ?? existing?.createdAt ?? updatedAt,
            updatedAt: updatedAt,
            isPinned: existing?.isPinned ?? remote.isPinned,
            preview: existing?.preview ?? "",
            remoteID: remote.id,
            projectID: remote.projectID ?? existing?.projectID,
            remoteUpdatedAt: remoteUpdatedAt
        )
    }

    /// The account copy of a chat, followed by the turns written in OCTO after it.
    public static func conversation(from remote: RemoteConversation, merging local: Conversation?, now: Date = Date()) -> Conversation {
        let createdAt = remote.createdAt ?? local?.createdAt ?? now
        var conversation = local ?? Conversation(id: RemoteIdentifier.localID(for: remote.id), createdAt: createdAt, updatedAt: createdAt)
        let localTurns = conversation.messages.filter { $0.remoteID == nil }
        conversation.remoteID = remote.id
        conversation.projectID = remote.projectID ?? conversation.projectID
        if !remote.title.isEmpty {
            conversation.title = remote.title
        }
        conversation.createdAt = createdAt
        conversation.messages = remote.messages.map { chatMessage(from: $0, fallbackDate: createdAt) } + localTurns

        let remoteUpdatedAt = remote.updatedAt ?? remote.messages.last?.createdAt ?? createdAt
        conversation.remoteUpdatedAt = remoteUpdatedAt
        conversation.updatedAt = max(remoteUpdatedAt, local?.updatedAt ?? remoteUpdatedAt)
        return conversation
    }

    static func chatMessage(from message: RemoteMessage, fallbackDate: Date) -> ChatMessage {
        var attachments: [MessageAttachment] = []
        for index in 0..<message.imageCount {
            attachments.append(MessageAttachment(
                id: RemoteIdentifier.localID(for: "\(message.id)#image-\(index)"),
                kind: .image,
                storedFileName: "",
                mimeType: "image/*",
                byteCount: 0
            ))
        }
        for (index, name) in message.fileNames.enumerated() {
            attachments.append(MessageAttachment(
                id: RemoteIdentifier.localID(for: "\(message.id)#file-\(index)"),
                kind: .text,
                storedFileName: "",
                displayName: name,
                mimeType: "application/octet-stream",
                byteCount: 0
            ))
        }
        return ChatMessage(
            id: RemoteIdentifier.localID(for: message.id),
            role: message.role,
            text: message.text,
            reasoning: message.reasoning,
            reasoningDuration: message.reasoningDuration,
            attachments: attachments,
            citations: message.citations,
            status: .complete,
            createdAt: message.createdAt ?? fallbackDate,
            remoteID: message.id
        )
    }
}
