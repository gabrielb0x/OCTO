import OCTOCore
import SwiftUI
import UIKit

struct MarkdownView: View {
    let text: String

    var body: some View {
        MarkdownBlocksView(blocks: MarkdownParser.parse(text))
    }
}

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var spacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
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
            Text(InlineMarkdown.attributed(text))
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(InlineMarkdown.attributed(text))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(index: index, item: item)
                    MarkdownBlocksView(blocks: item.blocks, spacing: 8)
                }
            }
        }
        .padding(.leading, 2)
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
            .background(isHeader ? Color.white.opacity(0.06) : Color.clear)
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
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: language?.lowercased() ?? "code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
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
                .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.04))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighting.attributed(code, language: language))
                    .font(.system(.footnote, design: .monospaced))
                    .lineSpacing(3)
                    .padding(14)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator))
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
                result[run.range].backgroundColor = Color.white.opacity(0.1)
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
