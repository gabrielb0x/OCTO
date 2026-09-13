import Foundation

/// Body of `POST /responses` (OpenAI Responses API), shared by the ChatGPT
/// backend and the public API.
public struct ResponsesRequest: Encodable, Equatable, Sendable {
    public var model: String
    public var instructions: String?
    public var input: [ResponsesInputMessage]
    public var tools: [ResponsesTool]
    public var toolChoice: String
    public var parallelToolCalls: Bool
    public var reasoning: ResponsesReasoning?
    public var store: Bool
    public var stream: Bool
    public var include: [String]
    public var promptCacheKey: String?
    public var text: ResponsesTextOptions?

    public init(
        model: String,
        instructions: String?,
        input: [ResponsesInputMessage],
        tools: [ResponsesTool] = [],
        reasoning: ResponsesReasoning? = nil,
        promptCacheKey: String? = nil,
        text: ResponsesTextOptions? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.toolChoice = "auto"
        self.parallelToolCalls = false
        self.reasoning = reasoning
        // Nothing is stored server-side: history lives on the device and is resent.
        self.store = false
        self.stream = true
        self.include = []
        self.promptCacheKey = promptCacheKey
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case model, instructions, input, tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning, store, stream, include
        case promptCacheKey = "prompt_cache_key"
        case text
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct ResponsesInputMessage: Encodable, Equatable, Sendable {
    public enum Role: String, Encodable, Sendable {
        case user
        case assistant
        case developer
    }

    public var role: Role
    public var content: [ResponsesContent]

    public init(role: Role, content: [ResponsesContent]) {
        self.role = role
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case type, role, content
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("message", forKey: .type)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

public enum ResponsesContent: Encodable, Equatable, Sendable {
    case inputText(String)
    case inputImage(dataURL: String)
    case outputText(String)

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let dataURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(dataURL, forKey: .imageURL)
        case .outputText(let text):
            try container.encode("output_text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

public enum ResponsesTool: Encodable, Equatable, Sendable {
    /// Hosted web search. `externalWebAccess` is only sent to the ChatGPT backend.
    case webSearch(externalWebAccess: Bool?)

    private enum CodingKeys: String, CodingKey {
        case type
        case externalWebAccess = "external_web_access"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .webSearch(let externalWebAccess):
            try container.encode("web_search", forKey: .type)
            try container.encodeIfPresent(externalWebAccess, forKey: .externalWebAccess)
        }
    }
}

public struct ResponsesReasoning: Encodable, Equatable, Sendable {
    public var effort: String?
    public var summary: String?

    public init(effort: String?, summary: String?) {
        self.effort = effort
        self.summary = summary
    }
}

public struct ResponsesTextOptions: Encodable, Equatable, Sendable {
    public var verbosity: String?

    public init(verbosity: String?) {
        self.verbosity = verbosity
    }
}

/// Content an attachment contributes to a request.
public enum AttachmentPayload: Equatable, Sendable {
    case imageDataURL(String)
    case text(String)
}

public enum ResponsesInputBuilder {
    /// Converts local history into Responses input items. Assistant turns that
    /// produced no text (failed or cancelled early) are skipped.
    public static func input(
        for messages: [ChatMessage],
        attachmentPayload: (MessageAttachment) -> AttachmentPayload?
    ) -> [ResponsesInputMessage] {
        var items: [ResponsesInputMessage] = []
        for message in messages {
            switch message.role {
            case .user:
                var content: [ResponsesContent] = []
                for attachment in message.attachments {
                    switch attachmentPayload(attachment) {
                    case .text(let fileText)?:
                        let name = attachment.displayName ?? "file"
                        content.append(.inputText("Attached file \"\(name)\":\n```\n\(fileText)\n```"))
                    case .imageDataURL(let url)?:
                        content.append(.inputImage(dataURL: url))
                    case nil:
                        break
                    }
                }
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    content.append(.inputText(message.text))
                }
                if !content.isEmpty {
                    items.append(ResponsesInputMessage(role: .user, content: content))
                }
            case .assistant:
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                items.append(ResponsesInputMessage(role: .assistant, content: [.outputText(message.text)]))
            }
        }
        return items
    }
}

public enum SystemPrompt {
    public static func make(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        localeIdentifier: String = Locale.current.identifier,
        aboutUser: String = "",
        responseStyle: String = ""
    ) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "EEEE, MMMM d, yyyy"

        var prompt = """
        You are OCTO, a helpful and knowledgeable AI assistant inside an open-source iOS chat app, powered by OpenAI models.
        Current date: \(dayFormatter.string(from: now)). Time zone: \(timeZone.identifier). User locale: \(localeIdentifier).

        Formatting:
        - Replies are rendered as GitHub-flavored Markdown: headings, bold, italics, lists, tables, block quotes, links and fenced code blocks with a language tag.
        - LaTeX is not rendered. Write math in plain text or Unicode (×, ÷, ², √, π, ≤, ≥) and put longer formulas in inline code.
        - Keep answers focused: brief for simple questions, structured and thorough for complex ones.
        - Reply in the language the user writes in.
        """

        let about = aboutUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty {
            prompt += "\n\nWhat the user wants you to know about them:\n\(about)"
        }
        let style = responseStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !style.isEmpty {
            prompt += "\n\nHow the user wants you to respond:\n\(style)"
        }
        return prompt
    }
}

public enum TitlePrompt {
    public static let instructions = "You write short titles for chat conversations. Reply with the title only: at most six words, no quotes, no emoji, no final punctuation, in the language of the conversation."

    public static func input(userText: String, assistantText: String) -> [ResponsesInputMessage] {
        let excerpt = """
        User: \(userText.prefix(1_200))

        Assistant: \(assistantText.prefix(800))
        """
        return [ResponsesInputMessage(role: .user, content: [.inputText("Write a title for this conversation:\n\n\(excerpt)")])]
    }

    /// Cleans a model-written title; returns nil when nothing usable remains.
    public static func sanitize(_ raw: String) -> String? {
        var title = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        for prefix in ["Title:", "title:", "Titre :", "Titre:", "#"] where title.hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        title = MarkdownPlainText.strip(title)
        let quotes = CharacterSet(charactersIn: "\"'“”«»‘’`*")
        title = title.trimmingCharacters(in: quotes.union(.whitespaces))
        while let last = title.last, ".!?:;".contains(last) {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: quotes.union(.whitespaces))
        guard !title.isEmpty else { return nil }
        return title.count > 60 ? String(title.prefix(59)) + "…" : title
    }
}
