import Charts
import OCTOCore
import SwiftUI

/// What the plan's Codex limits have left, in charts: the tokens used each day, each limit, and
/// an estimate of the tokens and messages left, drawn from the chats of the account.
struct CodexUsageView: View {
    @Environment(AppModel.self) private var app
    @State private var history: UsageHistory?
    @State private var selectedDate: Date?

    /// The account's own count of tokens, else the replies written on this iPhone.
    private var activity: CodexTokenActivity? {
        if let activity = app.tokenActivity {
            return activity
        }
        guard let samples = history?.samples, !samples.isEmpty else { return nil }
        return CodexTokenActivity(samples: samples)
    }

    private var countsThisDeviceOnly: Bool {
        app.tokenActivity == nil && activity != nil
    }

    private var estimate: CodexUsageEstimate? {
        guard let usage = app.usage else { return nil }
        return CodexUsageEstimator.estimate(usage: usage, activity: activity, samples: history?.samples ?? [], tokensPerMessage: history?.average?.tokens)
    }

    var body: some View {
        List {
            summary
            tokens
            dailyChart
            limits
            messageSize
        }
        .navigationTitle("Codex usage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .detachedRefreshable {
            await refresh()
        }
    }

    // MARK: Sections

    /// The number that matters first: the messages left, else the share of the limit left.
    @ViewBuilder
    private var summary: some View {
        Section {
            if let window = app.usage?.mostUsedWindow {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let messages = estimate?.messagesLeft {
                            Text(verbatim: "≈ \(messages.formatted())")
                                .font(.system(size: 48, weight: .semibold))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Text("Estimated messages left")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            Text(verbatim: UsageText.percent(window.leftPercent))
                                .font(.system(size: 48, weight: .semibold))
                            Text("Left of your \(UsageText.title(of: window).lowercased())")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    UsageMeter(window: window)
                    UsageCaption(window: window)
                }
                .padding(.vertical, 8)
            } else if let error = app.usageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.danger)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        } footer: {
            Text("Messages sent from OCTO count toward the Codex usage limits included in your ChatGPT plan.")
        }
    }

    /// Tokens used in the limit that runs out first, and about how many are left.
    @ViewBuilder
    private var tokens: some View {
        if let estimate {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    StatTile(label: "Used this period", value: UsageText.tokens(estimate.tokensUsed))
                    StatTile(label: "Left, estimated", value: "≈ " + UsageText.tokens(estimate.tokensLeft))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Tokens")
            } footer: {
                Text("Of your \(UsageText.title(of: estimate.window).lowercased()), which holds about \(UsageText.tokens(estimate.tokensTotal)) tokens.")
            }
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        Section {
            if let activity, !activity.days.isEmpty {
                DailyTokensChart(days: activity.recentDays(14, now: Date()), selectedDate: $selectedDate)
                    .padding(.vertical, 6)
            } else if let error = app.tokenActivityError, activity == nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.secondaryText)
            } else if history != nil {
                Text("No tokens counted yet. Send a message and come back.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        } header: {
            Text("Tokens per day")
        } footer: {
            dailyFooter
        }
    }

    @ViewBuilder
    private var dailyFooter: some View {
        if let activity {
            VStack(alignment: .leading, spacing: 4) {
                if countsThisDeviceOnly {
                    Text("Your account's count couldn't be read: these are the replies written on this iPhone.")
                } else {
                    Text("Every Codex app of your account counts, not only OCTO.")
                }
                if let lifetime = activity.lifetimeTokens {
                    Text("All time: \(UsageText.tokens(lifetime)) tokens")
                }
                if let peak = activity.peakDailyTokens, peak > 0 {
                    Text("Busiest day: \(UsageText.tokens(peak)) tokens")
                }
            }
        }
    }

    /// Every limit of the plan, most used first.
    @ViewBuilder
    private var limits: some View {
        if let usage = app.usage {
            let windows = [usage.primary, usage.secondary].compactMap { $0 }.sorted { $0.usedPercent > $1.usedPercent }
            if windows.count > 1 {
                Section("Limits") {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(verbatim: UsageText.title(of: window))
                                .font(.headline)
                            UsageMeter(window: window)
                            UsageCaption(window: window)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    /// What a message costs, from the chats of the account.
    @ViewBuilder
    private var messageSize: some View {
        if let average = history?.average {
            Section {
                LabeledContent {
                    Text("≈ \(UsageText.tokens(average.tokens)) tokens")
                } label: {
                    Label("Average message", systemImage: "text.bubble")
                }
                LabeledContent {
                    Text(verbatim: average.replies.formatted())
                } label: {
                    Label("Replies it's drawn from", systemImage: "bubble.left.and.bubble.right")
                }
                LabeledContent {
                    Text(verbatim: average.measuredReplies.formatted())
                } label: {
                    Label("Counted by Codex", systemImage: "number")
                }
            } header: {
                Text("Estimate")
            } footer: {
                Text("A message costs its question, the whole chat before it and the reply. Replies written in OCTO come with the count of Codex; the others are estimated from their length. Codex only tells what share of each limit is used: what's left is estimated from what your account used in the same period.")
            }
        }
    }

    // MARK: Data

    private func refresh() async {
        async let usage: Void = app.refreshUsage()
        async let activity: Void = app.refreshTokenActivity()
        async let chats: Void = loadHistory()
        _ = await (usage, activity, chats)
    }

    /// The size of the messages in the chats of the account, read off the main thread.
    private func loadHistory() async {
        let conversations = await app.store.recentConversations(limit: 150)
        let instructions = SystemPrompt.make(personal: app.account.personalContext).count
        history = await Task.detached(priority: .utility) {
            UsageHistory(
                average: MessageCost.average(of: conversations, instructionsCharacters: instructions),
                samples: MessageCost.measuredSamples(in: conversations)
            )
        }.value
    }
}

/// What the chats of the account say about the cost of a message.
private struct UsageHistory: Sendable {
    var average: MessageCost.Average?
    var samples: [TokenSample]
}

/// "Codex usage", with the share of the plan's limits left, opening its page.
struct CodexUsageRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: SettingsRoute.codexUsage) {
            LabeledContent {
                if let window = app.usage?.mostUsedWindow {
                    Text("\(UsageText.percent(window.leftPercent)) left")
                        .monospacedDigit()
                }
            } label: {
                Label("Codex usage", systemImage: "chart.bar.xaxis")
            }
        }
    }
}

/// A number and what it counts, like the tiles of Apple's own dashboards.
private struct StatTile: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text(verbatim: value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// How much of a limit is left, as a bar that empties as it's used. Green while there's plenty,
/// orange when it runs low, red near the end.
struct UsageMeter: View {
    let window: UsageSnapshot.Window

    var body: some View {
        let left = window.leftPercent / 100
        let tint = UsageLevel(leftPercent: window.leftPercent).color
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.22))
                Capsule()
                    .fill(tint)
                    .frame(width: left > 0 ? max(proxy.size.width * left, 8) : 0)
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel(Text(UsageText.title(of: window)))
        .accessibilityValue(Text("\(UsageText.percent(window.leftPercent)) left"))
    }
}

/// "82 % left" and when the limit resets, under a meter. A low limit also says so with an icon.
struct UsageCaption: View {
    let window: UsageSnapshot.Window

    var body: some View {
        let level = UsageLevel(leftPercent: window.leftPercent)
        HStack(spacing: 5) {
            if level != .plenty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(level.color)
                    .accessibilityHidden(true)
            }
            Text("\(UsageText.percent(window.leftPercent)) left")
                .monospacedDigit()
            Spacer(minLength: 8)
            if let resetsAt = window.resetsAt, resetsAt > Date() {
                Text("Resets \(resetsAt, style: .relative)")
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
    }
}

enum UsageLevel: Equatable {
    case plenty
    case low
    case critical

    init(leftPercent: Double) {
        switch leftPercent {
        case ..<15: self = .critical
        case ..<40: self = .low
        default: self = .plenty
        }
    }

    var color: Color {
        switch self {
        case .plenty: return Theme.success
        case .low: return Theme.warning
        case .critical: return Theme.danger
        }
    }
}

/// The tokens of the last days, one bar each. Touching the chart shows a day; otherwise today.
private struct DailyTokensChart: View {
    let days: [CodexTokenActivity.Day]
    @Binding var selectedDate: Date?

    private struct Bar: Identifiable {
        /// Midnight of the day where the phone is, so the axis names the right day.
        let date: Date
        let tokens: Int

        var id: Date { date }
    }

    private var bars: [Bar] {
        days.map { Bar(date: Self.localDay($0.date), tokens: $0.tokens) }
    }

    private var shownBar: Bar? {
        if let selectedDate, let bar = bars.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            return bar
        }
        return bars.last
    }

    var body: some View {
        let bars = bars
        let shown = shownBar
        VStack(alignment: .leading, spacing: 10) {
            if let shown {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: UsageText.tokens(shown.tokens))
                        .font(.title2.weight(.semibold))
                        .contentTransition(.numericText())
                    Text(Calendar.current.isDateInToday(shown.date) ? String(localized: "Today") : shown.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .animation(.smooth(duration: 0.2), value: shown.id)
            }

            Chart(bars) { bar in
                BarMark(
                    x: .value("Day", bar.date, unit: .day),
                    y: .value("Tokens", bar.tokens),
                    width: .ratio(0.62)
                )
                .cornerRadius(4, style: .continuous)
                .foregroundStyle(Theme.chartBar)
                .opacity(shown == nil || shown?.id == bar.id ? 1 : 0.4)
                .accessibilityLabel(Text(bar.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                .accessibilityValue(Text("\(bar.tokens) tokens"))
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(verbatim: UsageText.tokens(tokens))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDates(bars)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            }
            .frame(height: 170)
        }
    }

    /// Three dates under the bars, a week apart and ending today, so the labels never collide.
    private func axisDates(_ bars: [Bar]) -> [Date] {
        guard !bars.isEmpty else { return [] }
        return stride(from: bars.count - 1, through: 0, by: -7).map { bars[$0].date }
    }

    /// The same day as the UTC one Codex counts, at midnight where the phone is.
    private static func localDay(_ date: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: parts) ?? date
    }
}

/// How the usage pages write their numbers.
enum UsageText {
    /// "82 %", as the language of the app writes percentages.
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "12K", "1.2M": short enough for a chart.
    static func tokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// "5-hour limit", "Weekly limit", "Monthly limit"…
    static func title(of window: UsageSnapshot.Window) -> String {
        guard let seconds = window.windowSeconds, seconds > 0 else {
            return String(localized: "Usage")
        }
        let hours = seconds / 3_600
        let days = hours / 24
        if days >= 28 {
            return String(localized: "Monthly limit")
        }
        if days >= 6 {
            return String(localized: "Weekly limit")
        }
        if days >= 1 {
            return String(localized: "\(days)-day limit")
        }
        return String(localized: "\(max(hours, 1))-hour limit")
    }
}
