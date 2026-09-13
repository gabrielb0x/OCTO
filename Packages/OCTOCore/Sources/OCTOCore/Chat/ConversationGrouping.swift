import Foundation

public enum ConversationBucket: Hashable, Sendable {
    case pinned
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(year: Int, month: Int)
}

public struct ConversationSection: Identifiable, Hashable, Sendable {
    public var bucket: ConversationBucket
    public var conversations: [ConversationSummary]

    public var id: ConversationBucket { bucket }

    public init(bucket: ConversationBucket, conversations: [ConversationSummary]) {
        self.bucket = bucket
        self.conversations = conversations
    }
}

public enum ConversationGrouping {
    public static func bucket(for date: Date, now: Date, calendar: Calendar) -> ConversationBucket {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today }
        if let start = calendar.date(byAdding: .day, value: -1, to: startOfToday), date >= start { return .yesterday }
        if let start = calendar.date(byAdding: .day, value: -7, to: startOfToday), date >= start { return .previous7Days }
        if let start = calendar.date(byAdding: .day, value: -30, to: startOfToday), date >= start { return .previous30Days }
        let components = calendar.dateComponents([.year, .month], from: date)
        return .month(year: components.year ?? 0, month: components.month ?? 0)
    }

    /// Pinned chats first, then chats by recency like the ChatGPT sidebar.
    public static func sections(for summaries: [ConversationSummary], now: Date = Date(), calendar: Calendar = .current) -> [ConversationSection] {
        let sorted = summaries.sorted { $0.updatedAt > $1.updatedAt }
        var sections: [ConversationSection] = []

        let pinned = sorted.filter(\.isPinned)
        if !pinned.isEmpty {
            sections.append(ConversationSection(bucket: .pinned, conversations: pinned))
        }
        for summary in sorted where !summary.isPinned {
            let bucket = bucket(for: summary.updatedAt, now: now, calendar: calendar)
            if let last = sections.indices.last, sections[last].bucket == bucket {
                sections[last].conversations.append(summary)
            } else {
                sections.append(ConversationSection(bucket: bucket, conversations: [summary]))
            }
        }
        return sections
    }
}
