import Foundation

/// Where a chat comes from. ChatGPT chats live in the ChatGPT account, and OCTO downloads them;
/// Codex chats were started in OCTO, answered by the Codex backend of the plan, and exist only on
/// this device. A ChatGPT chat continued in OCTO stays a ChatGPT chat.
public enum ChatOrigin: String, Codable, CaseIterable, Sendable {
    case chatGPT
    case codex
}

/// Which chats the chat list shows.
public enum ChatOriginFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case chatGPT
    case codex

    public var id: String { rawValue }

    public func includes(_ origin: ChatOrigin) -> Bool {
        switch self {
        case .all: return true
        case .chatGPT: return origin == .chatGPT
        case .codex: return origin == .codex
        }
    }

    /// The chats of `summaries` the filter keeps, in the same order.
    public func apply(to summaries: [ConversationSummary]) -> [ConversationSummary] {
        self == .all ? summaries : summaries.filter { includes($0.origin) }
    }
}

extension ConversationSummary {
    public var origin: ChatOrigin { isAccountChat ? .chatGPT : .codex }
}

extension Conversation {
    public var origin: ChatOrigin { isAccountChat ? .chatGPT : .codex }
}
