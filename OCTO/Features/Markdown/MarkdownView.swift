import OCTOCore
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The words of a reply being written that are still fading in; nil once the reply is complete.
    @Entry var streamingReveal: StreamingReveal? = nil
    /// Long lines of code wrap instead of scrolling sideways.
    @Entry var wrapsCodeLines = false
}

/// When the latest words of a reply appeared, counted back from the end of the reply.
struct StreamingReveal: Equatable {
    /// Oldest first. The words before them are fully shown.
    var times: [TimeInterval]
    var duration: TimeInterval
    /// Words of the reply that come after the text this value is given to.
    var wordsAfter = 0

    /// When the word `index` words before the end of the text appeared, or nil if it's fully shown.
    func time(ofWordFromEnd index: Int) -> TimeInterval? {
        let position = times.count - 1 - wordsAfter - index
        return index >= 0 && times.indices.contains(position) ? times[position] : nil
    }

    /// False once every word of the text is fully shown.
    var reachesText: Bool {
        wordsAfter < times.count
    }

    func followed(byWords count: Int) -> StreamingReveal {
        var copy = self
        copy.wordsAfter += count
        return copy
    }
}

/// Shares the fade of a reply between its blocks, from the last one back, by the words each shows.
@MainActor
enum RevealLayout {
    static func split(_ reveal: StreamingReveal?, count: Int, words: (Int) -> Int) -> [StreamingReveal?] {
        var result = [StreamingReveal?](repeating: nil, count: count)
        guard var current = reveal else { return result }
        for index in stride(from: count - 1, through: 0, by: -1) {
            guard current.reachesText else { break }
            result[index] = current
            current = current.followed(byWords: words(index))
        }
        return result
    }

    /// The words a block shows, cut the way a reply is revealed.
    static func words(in block: MarkdownBlock) -> Int {
        switch block {
        case .heading(_, let text), .paragraph(let text):
            return RevealTokenizer.count(in: InlineMarkdown.attributed(text).characters)
        case .code(_, let code):
            return RevealTokenizer.count(in: code)
        case .quote(let blocks):
            return blocks.reduce(0) { $0 + words(in: $1) }
        case .list(let list):
            return list.items.reduce(0) { $0 + words(in: $1) }
        case .table(let table):
            return (table.header + table.rows.flatMap { $0 }).reduce(0) { $0 + RevealTokenizer.count(in: InlineMarkdown.attributed($1).characters) }
        case .math(let expression):
            return RevealTokenizer.count(in: expression)
        case .rule:
            return 0
        }
    }

    static func words(in item: MarkdownListItem) -> Int {
        item.blocks.reduce(0) { $0 + words(in: $1) }
    }
}

struct MarkdownView: View {
    let text: String

    var body: some View {
        MarkdownBlocksView(blocks: MarkdownParser.parse(text))
    }
}

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var spacing: CGFloat = 14
    @Environment(\.streamingReveal) private var reveal

    var body: some View {
        let reveals = RevealLayout.split(reveal, count: blocks.count) { RevealLayout.words(in: blocks[$0]) }
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                // Only the blocks with words still fading in animate.
                MarkdownBlockView(block: block)
                    .environment(\.streamingReveal, reveals[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            RevealingText(InlineMarkdown.attributed(text))
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            RevealingText(InlineMarkdown.attributed(text))
                .lineSpacing(3)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(Theme.tertiaryText)
                    .frame(width: 3)
                MarkdownBlocksView(blocks: blocks, spacing: 8)
                    .foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            MarkdownListView(list: list)
        case .table(let table):
            MarkdownTableView(table: table)
        case .math(let expression):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: expression)
                    .font(.system(.body, design: .serif))
                    .italic()
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
        case .rule:
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.vertical, 6)
        }
    }

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }
}

struct MarkdownListView: View {
    let list: MarkdownList
    @Environment(\.streamingReveal) private var reveal

    var body: some View {
        let reveals = RevealLayout.split(reveal, count: list.items.count) { RevealLayout.words(in: list.items[$0]) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(index: index, item: item)
                        .modifier(RevealFade(time: Self.firstWordTime(of: item, reveal: reveals[index]), duration: reveal?.duration ?? 0))
                    MarkdownBlocksView(blocks: item.blocks, spacing: 8)
                }
                .environment(\.streamingReveal, reveals[index])
            }
        }
        .padding(.leading, 2)
    }

    /// A bullet appears with the first word of its item.
    private static func firstWordTime(of item: MarkdownListItem, reveal: StreamingReveal?) -> TimeInterval? {
        guard let reveal else { return nil }
        let words = RevealLayout.words(in: item)
        return words > 0 ? reveal.time(ofWordFromEnd: words - 1) : nil
    }

    @ViewBuilder
    private func marker(index: Int, item: MarkdownListItem) -> some View {
        if let isChecked = item.isChecked {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isChecked ? Theme.accent : Theme.secondaryText)
        } else if list.ordered {
            Text(verbatim: "\(list.startNumber + index).")
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 20, alignment: .trailing)
        } else {
            Text(verbatim: "•")
                .fontWeight(.bold)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        cellView(cell, column: column, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            cellView(cell, column: column, isHeader: false)
                        }
                    }
                }
            }
        }
        .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cellView(_ text: String, column: Int, isHeader: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        return Text(InlineMarkdown.attributed(text))
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(minWidth: 64, maxWidth: 260, alignment: alignment.frameAlignment)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isHeader ? Theme.primaryText.opacity(0.06) : Color.clear)
            .gridColumnAlignment(alignment.horizontalAlignment)
    }
}

private extension MarkdownTableAlignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @Environment(AppModel.self) private var app
    @Environment(\.wrapsCodeLines) private var wrapsLines
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: language?.lowercased() ?? "code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    Clipboard.copy(code, settings: app.settings, cleansLinks: false)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy"), systemImage: copied ? "checkmark" : "square.on.square")
                        .font(.caption.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .sensoryFeedback(.success, trigger: copied) { _, isCopied in
                    isCopied && app.settings.hapticsEnabled
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.primaryText.opacity(0.04))

            if wrapsLines {
                codeText
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    codeText
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator))
    }

    private var codeText: some View {
        RevealingText(CodeHighlighting.attributed(code, language: language))
            .font(.system(.footnote, design: .monospaced))
            .lineSpacing(3)
            .padding(14)
    }
}

/// Marks a word of a reply being written with the moment it appeared.
struct WordRevealAttribute: TextAttribute {
    var time: TimeInterval
}

enum WordRevealCurve {
    /// How far a word is into its fade, eased out: 0 when it appears, 1 once fully shown.
    static func eased(now: TimeInterval, time: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        let progress = min(max((now - time) / duration, 0), 1)
        return 1 - (1 - progress) * (1 - progress)
    }
}

/// Draws the words of a reply fading in one by one, each settling into place from slightly below.
struct WordRevealRenderer: TextRenderer {
    static let rise: CGFloat = 3

    var now: TimeInterval
    var duration: TimeInterval

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: Self.rise, trailing: 0)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let reveal = run[WordRevealAttribute.self] else {
                    context.draw(run)
                    continue
                }
                let shown = WordRevealCurve.eased(now: now, time: reveal.time, duration: duration)
                if shown >= 1 {
                    context.draw(run)
                } else if shown > 0 {
                    var word = context
                    word.opacity = shown
                    word.translateBy(x: 0, y: (1 - shown) * Self.rise)
                    word.draw(run)
                }
            }
        }
    }
}

/// Text whose latest words fade in one by one while a reply is written.
struct RevealingText: View {
    let content: AttributedString
    @Environment(\.streamingReveal) private var reveal

    init(_ content: AttributedString) {
        self.content = content
    }

    var body: some View {
        if let reveal, let revealing = Self.text(content, reveal: reveal) {
            TimelineView(.animation) { context in
                revealing
                    .textRenderer(WordRevealRenderer(now: context.date.timeIntervalSinceReferenceDate, duration: reveal.duration))
            }
        } else {
            Text(content)
        }
    }

    /// The text with each word still fading in as its own piece, marked with the moment it appeared.
    static func text(_ content: AttributedString, reveal: StreamingReveal) -> Text? {
        let pieces = RevealTokenizer.ranges(in: content.characters)
        var fading: [(range: Range<AttributedString.Index>, time: TimeInterval)] = []
        for (offset, range) in pieces.reversed().enumerated() {
            guard let time = reveal.time(ofWordFromEnd: offset) else { break }
            fading.append((range, time))
        }
        guard let earliest = fading.last else { return nil }
        var text = Text(AttributedString(content[content.startIndex..<earliest.range.lowerBound]))
        for piece in fading.reversed() {
            let word = Text(AttributedString(content[piece.range])).customAttribute(WordRevealAttribute(time: piece.time))
            text = Text("\(text)\(word)")
        }
        return text
    }
}

/// Fades in something that appears together with a word, such as a list bullet.
struct RevealFade: ViewModifier {
    let time: TimeInterval?
    let duration: TimeInterval

    @ViewBuilder
    func body(content: Content) -> some View {
        if let time, duration > 0 {
            TimelineView(.animation) { context in
                content.opacity(WordRevealCurve.eased(now: context.date.timeIntervalSinceReferenceDate, time: time, duration: duration))
            }
        } else {
            content
        }
    }
}

final class AttributedStringBox {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

/// Inline Markdown (bold, italics, code spans, links) rendered with Foundation's parser.
@MainActor
enum InlineMarkdown {
    private static let cache: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 600
        return cache
    }()

    static func attributed(_ source: String) -> AttributedString {
        let key = source as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        for run in result.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                result[run.range].font = .system(.callout, design: .monospaced)
                result[run.range].backgroundColor = Theme.primaryText.opacity(0.1)
            }
            if run.link != nil {
                result[run.range].foregroundColor = Theme.link
                result[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.link.opacity(0.45))
            }
        }
        cache.setObject(AttributedStringBox(result), forKey: key)
        return result
    }
}

@MainActor
enum CodeHighlighting {
    private static let cache: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 120
        return cache
    }()

    static func attributed(_ code: String, language: String?) -> AttributedString {
        let key = "\(language ?? "")\u{0}\(code)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        var result = AttributedString()
        for token in SyntaxHighlighter.tokenize(code, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = Theme.syntaxColor(token.kind)
            result.append(piece)
        }
        cache.setObject(AttributedStringBox(result), forKey: key)
        return result
    }
}
