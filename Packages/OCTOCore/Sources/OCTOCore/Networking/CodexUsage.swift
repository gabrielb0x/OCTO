import Foundation

/// The tokens the account's Codex usage went through, day by day, as the Codex CLI reads them
/// (`CodexBackend.tokenActivityURL`, its `stats`). Every Codex client of the account counts —
/// the CLI, the editors, OCTO — not only this iPhone.
public struct CodexTokenActivity: Codable, Equatable, Sendable {
    public struct Day: Codable, Hashable, Sendable, Identifiable {
        /// Midnight UTC of the day, as the days are counted.
        public var date: Date
        public var tokens: Int

        public var id: Date { date }

        public init(date: Date, tokens: Int) {
            self.date = date
            self.tokens = tokens
        }
    }

    /// Days with some use, oldest first.
    public var days: [Day]
    public var lifetimeTokens: Int?
    public var peakDailyTokens: Int?
    public var currentStreakDays: Int?
    public var longestStreakDays: Int?

    public init(days: [Day] = [], lifetimeTokens: Int? = nil, peakDailyTokens: Int? = nil, currentStreakDays: Int? = nil, longestStreakDays: Int? = nil) {
        self.days = days.sorted { $0.date < $1.date }
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }

    /// The same days, counted from the replies written on this device, for when the account's
    /// own count can't be read.
    public init(samples: [TokenSample]) {
        var totals: [Date: Int] = [:]
        for sample in samples where sample.tokens > 0 {
            totals[Self.dayStart(sample.date), default: 0] += sample.tokens
        }
        self.init(days: totals.map { Day(date: $0.key, tokens: $0.value) }, lifetimeTokens: totals.values.reduce(0, +))
    }

    public static func parse(_ data: Data) -> CodexTokenActivity? {
        guard let object = JSONValue.object(data) else { return nil }
        let stats = object["stats"] as? [String: Any] ?? object
        let buckets = stats["daily_usage_buckets"] as? [[String: Any]]
        let lifetime = JSONValue.int(stats["lifetime_tokens"])
        let peak = JSONValue.int(stats["peak_daily_tokens"])
        guard buckets != nil || lifetime != nil || peak != nil else { return nil }
        var totals: [Date: Int] = [:]
        for bucket in buckets ?? [] {
            guard let date = day(bucket["start_date"]), let tokens = JSONValue.int(bucket["tokens"]), tokens > 0 else { continue }
            totals[date, default: 0] += tokens
        }
        return CodexTokenActivity(
            days: totals.map { Day(date: $0.key, tokens: $0.value) },
            lifetimeTokens: lifetime,
            peakDailyTokens: peak,
            currentStreakDays: JSONValue.int(stats["current_streak_days"]),
            longestStreakDays: JSONValue.int(stats["longest_streak_days"])
        )
    }

    /// Tokens of the day holding `start` and of every day after it.
    public func tokens(since start: Date) -> Int {
        let first = Self.dayStart(start)
        return days.filter { $0.date >= first }.reduce(0) { $0 + $1.tokens }
    }

    /// The last `count` days through the one holding `now`, days without use at zero.
    public func recentDays(_ count: Int, now: Date) -> [Day] {
        let today = Self.dayStart(now)
        let byDate = Dictionary(days.map { ($0.date, $0.tokens) }, uniquingKeysWith: +)
        return (0..<max(count, 0)).reversed().map { offset in
            let date = today.addingTimeInterval(-Double(offset) * 86_400)
            return Day(date: date, tokens: byDate[date] ?? 0)
        }
    }

    /// `"2026-05-29"`, the way the days are dated, or a full date.
    static func day(_ value: Any?) -> Date? {
        if let text = JSONValue.string(value)?.trimmingCharacters(in: .whitespaces), text.count == 10,
           let date = FlexibleDate.iso8601(text + "T00:00:00Z") {
            return date
        }
        return FlexibleDate.parse(value).map(dayStart)
    }

    /// Midnight UTC of the day holding `date`.
    public static func dayStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400)
    }
}

/// Where the plan's Codex limits stand, sent back with every reply: in the
/// `x-codex-primary-used-percent`… headers of the response, and in `codex.rate_limits` events.
public struct CodexRateLimits: Equatable, Sendable {
    public var primary: UsageSnapshot.Window?
    public var secondary: UsageSnapshot.Window?

    public init(primary: UsageSnapshot.Window? = nil, secondary: UsageSnapshot.Window? = nil) {
        self.primary = primary
        self.secondary = secondary
    }

    /// The limits in the headers of a Codex response, whatever the case of their names.
    public static func parse(headers: [String: String], now: Date = Date()) -> CodexRateLimits? {
        var values: [String: String] = [:]
        for (name, value) in headers {
            values[name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }
        func window(_ name: String) -> UsageSnapshot.Window? {
            guard let used = values["x-codex-\(name)-used-percent"].flatMap({ Double($0) }) else { return nil }
            var resetsAt = values["x-codex-\(name)-reset-at"].flatMap { Double($0) }.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            if resetsAt == nil, let after = values["x-codex-\(name)-reset-after-seconds"].flatMap({ Double($0) }) {
                resetsAt = now.addingTimeInterval(after)
            }
            let minutes = values["x-codex-\(name)-window-minutes"].flatMap { Int($0) }
            return UsageSnapshot.Window(usedPercent: min(max(used, 0), 100), windowSeconds: minutes.map { $0 * 60 }, resetsAt: resetsAt)
        }
        let limits = CodexRateLimits(primary: window("primary"), secondary: window("secondary"))
        return limits.isEmpty ? nil : limits
    }

    /// `{"type": "codex.rate_limits", "rate_limits": {"primary": {"used_percent", "window_minutes", "reset_at"}, …}}`.
    static func parse(event object: [String: Any]) -> CodexRateLimits? {
        let details = object["rate_limits"] as? [String: Any]
        func window(_ value: Any?) -> UsageSnapshot.Window? {
            guard let window = value as? [String: Any], let used = JSONValue.double(window["used_percent"]) else { return nil }
            return UsageSnapshot.Window(
                usedPercent: min(max(used, 0), 100),
                windowSeconds: JSONValue.int(window["window_minutes"]).map { $0 * 60 },
                resetsAt: JSONValue.double(window["reset_at"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            )
        }
        let limits = CodexRateLimits(primary: window(details?["primary"]), secondary: window(details?["secondary"]))
        return limits.isEmpty ? nil : limits
    }

    var isEmpty: Bool {
        primary == nil && secondary == nil
    }
}

extension UsageSnapshot {
    /// Usage known only from the limits sent with a reply.
    public init(limits: CodexRateLimits) {
        self.init(
            planType: nil,
            limitReached: [limits.primary, limits.secondary].contains { ($0?.usedPercent ?? 0) >= 100 },
            primary: limits.primary,
            secondary: limits.secondary,
            hasCredits: nil,
            unlimitedCredits: nil,
            creditBalance: nil
        )
    }

    /// The usage with the limits sent along with a reply, which are newer. What the reply didn't
    /// say about a window — its length, when it resets — is kept.
    public func applying(_ limits: CodexRateLimits) -> UsageSnapshot {
        var updated = self
        if let primary = limits.primary {
            updated.primary = primary.filling(from: self.primary)
        }
        if let secondary = limits.secondary {
            updated.secondary = secondary.filling(from: self.secondary)
        }
        updated.limitReached = [updated.primary, updated.secondary].contains { ($0?.usedPercent ?? 0) >= 100 }
        return updated
    }

    /// The window that runs out first: the one most used.
    public var mostUsedWindow: Window? {
        [primary, secondary].compactMap { $0 }.max { $0.usedPercent < $1.usedPercent }
    }
}

extension UsageSnapshot.Window {
    func filling(from previous: UsageSnapshot.Window?) -> UsageSnapshot.Window {
        guard let previous else { return self }
        var window = self
        window.windowSeconds = windowSeconds ?? previous.windowSeconds
        window.resetsAt = resetsAt ?? previous.resetsAt
        return window
    }

    public var leftPercent: Double {
        max(0, 100 - usedPercent)
    }
}

/// One reply and the tokens it went through.
public struct TokenSample: Equatable, Sendable {
    public var date: Date
    public var tokens: Int

    public init(date: Date, tokens: Int) {
        self.date = date
        self.tokens = tokens
    }
}

/// How much of a Codex limit is left, in tokens and in messages. OpenAI only tells how much of
/// each limit is used, as a percentage: the size of a limit is estimated from the tokens the
/// account went through while using that much of it.
public struct CodexUsageEstimate: Equatable, Sendable {
    /// The limit that runs out first.
    public var window: UsageSnapshot.Window
    public var tokensUsed: Int
    public var tokensTotal: Int
    public var tokensLeft: Int
    /// What one message costs, on average, in the chats of the account.
    public var tokensPerMessage: Int?

    public init(window: UsageSnapshot.Window, tokensUsed: Int, tokensTotal: Int, tokensLeft: Int, tokensPerMessage: Int?) {
        self.window = window
        self.tokensUsed = tokensUsed
        self.tokensTotal = tokensTotal
        self.tokensLeft = tokensLeft
        self.tokensPerMessage = tokensPerMessage
    }

    public var messagesLeft: Int? {
        guard let tokensPerMessage, tokensPerMessage > 0 else { return nil }
        return tokensLeft / tokensPerMessage
    }
}

public enum CodexUsageEstimator {
    /// When a window started: its reset minus its length, else its length back from now.
    public static func start(of window: UsageSnapshot.Window, now: Date) -> Date? {
        guard let seconds = window.windowSeconds, seconds > 0 else { return nil }
        return (window.resetsAt ?? now).addingTimeInterval(-Double(seconds))
    }

    /// Tokens the account went through in a window: from the days of its Codex activity when the
    /// window spans days, else from the replies written on this device.
    public static func tokensUsed(in window: UsageSnapshot.Window, activity: CodexTokenActivity?, samples: [TokenSample], now: Date) -> Int? {
        guard let start = start(of: window, now: now) else { return nil }
        if let activity, !activity.days.isEmpty, let seconds = window.windowSeconds, seconds >= 86_400 {
            return activity.tokens(since: start)
        }
        return samples.filter { $0.date >= start && $0.date <= now }.reduce(0) { $0 + $1.tokens }
    }

    /// The estimate for the limit that leaves the fewest tokens. Nil until a limit is used enough
    /// to tell its size.
    public static func estimate(usage: UsageSnapshot, activity: CodexTokenActivity?, samples: [TokenSample], tokensPerMessage: Int?, now: Date = Date()) -> CodexUsageEstimate? {
        var best: CodexUsageEstimate?
        for window in [usage.primary, usage.secondary].compactMap({ $0 }) {
            guard let used = tokensUsed(in: window, activity: activity, samples: samples, now: now) else { continue }
            let estimate: CodexUsageEstimate
            if window.usedPercent >= 100 {
                estimate = CodexUsageEstimate(window: window, tokensUsed: used, tokensTotal: used, tokensLeft: 0, tokensPerMessage: tokensPerMessage)
            } else {
                guard window.usedPercent > 0, used > 0 else { continue }
                let total = Int((Double(used) * 100 / window.usedPercent).rounded())
                estimate = CodexUsageEstimate(window: window, tokensUsed: used, tokensTotal: total, tokensLeft: max(total - used, 0), tokensPerMessage: tokensPerMessage)
            }
            if best.map({ estimate.tokensLeft < $0.tokensLeft }) ?? true {
                best = estimate
            }
        }
        return best
    }
}

/// What one message costs in tokens, from the chats of the account: everything sent with it — the
/// instructions, the chat so far, the question — and the reply. Replies written in OCTO carry
/// their exact count; the others are estimated from the length of their text.
public enum MessageCost {
    public struct Average: Equatable, Sendable {
        public var tokens: Int
        /// How many replies it's drawn from, and how many of them came with their exact count.
        public var replies: Int
        public var measuredReplies: Int

        public init(tokens: Int, replies: Int, measuredReplies: Int) {
            self.tokens = tokens
            self.replies = replies
            self.measuredReplies = measuredReplies
        }
    }

    /// Characters per token of ordinary text, until replies written in OCTO tell better.
    public static let defaultCharactersPerToken = 4.0
    /// About what an image sent to the model costs.
    static let imageTokens = 800

    /// The average cost of the latest replies, at most `limit` of them.
    public static func average(of conversations: [Conversation], instructionsCharacters: Int, limit: Int = 200) -> Average? {
        let ratio = charactersPerToken(in: conversations)
        let recent = replies(in: conversations, instructionsCharacters: instructionsCharacters, charactersPerToken: ratio)
            .sorted { $0.sample.date > $1.sample.date }
            .prefix(limit)
        guard !recent.isEmpty else { return nil }
        let total = recent.reduce(0) { $0 + $1.sample.tokens }
        return Average(tokens: max(1, total / recent.count), replies: recent.count, measuredReplies: recent.filter { $0.isMeasured }.count)
    }

    /// The replies written in OCTO, with the tokens Codex counted for each.
    public static func measuredSamples(in conversations: [Conversation]) -> [TokenSample] {
        conversations.flatMap(\.messages).compactMap { message in
            guard message.role == .assistant, let usage = message.usage else { return nil }
            let tokens = usage.inputTokens + usage.outputTokens
            return tokens > 0 ? TokenSample(date: message.createdAt, tokens: tokens) : nil
        }
    }

    /// Characters per token of the replies Codex counted, when there's enough of them.
    static func charactersPerToken(in conversations: [Conversation]) -> Double {
        var characters = 0
        var tokens = 0
        for message in conversations.flatMap(\.messages) where message.role == .assistant && !message.text.isEmpty {
            guard let usage = message.usage else { continue }
            let written = usage.outputTokens - usage.reasoningTokens
            guard written > 0 else { continue }
            characters += message.text.count
            tokens += written
        }
        guard tokens >= 200 else { return defaultCharactersPerToken }
        return min(max(Double(characters) / Double(tokens), 2.5), 6)
    }

    /// A reply and its cost, counted by Codex or estimated.
    struct Reply {
        var sample: TokenSample
        var isMeasured: Bool
    }

    static func replies(in conversations: [Conversation], instructionsCharacters: Int, charactersPerToken: Double) -> [Reply] {
        var replies: [Reply] = []
        for conversation in conversations {
            // What the chat so far adds to every question: its text, and the images sent in it.
            var contextCharacters = 0
            var contextTokens = 0
            for message in conversation.messages {
                let characters = message.text.count + message.attachments.filter { $0.kind == .text }.reduce(0) { $0 + $1.byteCount }
                switch message.role {
                case .user:
                    contextCharacters += characters
                    contextTokens += message.attachments.filter { $0.kind == .image }.count * imageTokens
                case .assistant:
                    if let usage = message.usage, usage.inputTokens + usage.outputTokens > 0 {
                        replies.append(Reply(sample: TokenSample(date: message.createdAt, tokens: usage.inputTokens + usage.outputTokens), isMeasured: true))
                    } else if message.status == .complete, !message.text.isEmpty {
                        let sent = Double(instructionsCharacters + contextCharacters) / charactersPerToken + Double(contextTokens)
                        let written = Double(message.text.count + message.reasoning.count) / charactersPerToken
                        replies.append(Reply(sample: TokenSample(date: message.createdAt, tokens: Int((sent + written).rounded())), isMeasured: false))
                    }
                    contextCharacters += message.text.count
                }
            }
        }
        return replies
    }
}
