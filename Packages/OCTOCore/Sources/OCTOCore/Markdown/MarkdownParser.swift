import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case quote([MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case math(String)
    case rule
}

public struct MarkdownList: Equatable, Sendable {
    public var ordered: Bool
    public var startNumber: Int
    public var items: [MarkdownListItem]
}

public struct MarkdownListItem: Equatable, Sendable {
    public var blocks: [MarkdownBlock]
    /// nil for regular items, true/false for GitHub task list items.
    public var isChecked: Bool?
}

public enum MarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

public struct MarkdownTable: Equatable, Sendable {
    public var header: [String]
    public var alignments: [MarkdownTableAlignment]
    public var rows: [[String]]
}

/// A forgiving block-level Markdown parser tuned for LLM output. Inline syntax
/// (emphasis, code spans, links) is left in the text for the renderer.
/// Incomplete constructs, as seen while streaming, degrade gracefully.
public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return parseBlocks(normalized.components(separatedBy: "\n"))
    }

    static func parseBlocks(_ lines: [String]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isBlank(line) {
                index += 1
            } else if let fence = Fence(line) {
                blocks.append(parseFencedCode(lines, &index, fence: fence))
            } else if isMathStart(line) {
                blocks.append(parseMath(lines, &index))
            } else if let heading = heading(line) {
                blocks.append(heading)
                index += 1
            } else if isThematicBreak(line) {
                blocks.append(.rule)
                index += 1
            } else if isQuoteLine(line) {
                blocks.append(parseQuote(lines, &index))
            } else if isTableStart(lines, index) {
                blocks.append(parseTable(lines, &index))
            } else if ListMarker(line) != nil {
                blocks.append(.list(parseList(lines, &index)))
            } else {
                blocks.append(parseParagraph(lines, &index))
            }
        }
        return blocks
    }

    // MARK: - Code

    struct Fence {
        let character: Character
        let length: Int
        let indent: Int
        let info: String

        init?(_ line: String) {
            let indent = MarkdownParser.leadingSpaces(line)
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
            let run = trimmed.prefix { $0 == first }.count
            guard run >= 3 else { return nil }
            let info = trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces)
            if first == "`", info.contains("`") { return nil }
            self.character = first
            self.length = run
            self.indent = indent
            self.info = info
        }

        func isClosing(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= length && trimmed.allSatisfy { $0 == character }
        }
    }

    static func parseFencedCode(_ lines: [String], _ index: inout Int, fence: Fence) -> MarkdownBlock {
        index += 1
        var codeLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            index += 1
            if fence.isClosing(line) { break }
            codeLines.append(removeIndent(line, count: fence.indent))
        }
        let language = fence.info.split(separator: " ").first.map(String.init)
        return .code(language: language, code: codeLines.joined(separator: "\n"))
    }

    // MARK: - Math

    static func isMathStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\\[") { return true }
        guard trimmed.hasPrefix("$$") else { return false }
        return !trimmed.dropFirst(2).hasPrefix("$")
    }

    static func parseMath(_ lines: [String], _ index: inout Int) -> MarkdownBlock {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let (open, close) = trimmed.hasPrefix("$$") ? ("$$", "$$") : ("\\[", "\\]")
        let rest = String(trimmed.dropFirst(open.count))

        if rest.count >= close.count, rest.hasSuffix(close) {
            index += 1
            return .math(String(rest.dropLast(close.count)).trimmingCharacters(in: .whitespaces))
        }

        var body: [String] = rest.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [rest]
        index += 1
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.hasSuffix(close) {
                let before = String(line.dropLast(close.count))
                if !before.trimmingCharacters(in: .whitespaces).isEmpty { body.append(before) }
                break
            }
            body.append(lines[index - 1])
        }
        return .math(body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Headings, rules, quotes

    static func heading(_ line: String) -> MarkdownBlock? {
        guard leadingSpaces(line) <= 3 else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        if text.allSatisfy({ $0 == "#" }) {
            text = ""
        } else if let range = text.range(of: #"\s+#+$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return .heading(level: hashes, text: text)
    }

    static func isThematicBreak(_ line: String) -> Bool {
        guard leadingSpaces(line) <= 3 else { return false }
        let marks = line.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    static func isQuoteLine(_ line: String) -> Bool {
        leadingSpaces(line) <= 3 && line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    static func parseQuote(_ lines: [String], _ index: inout Int) -> MarkdownBlock {
        var inner: [String] = []
        while index < lines.count {
            let line = lines[index]
            if isQuoteLine(line) {
                var content = line.trimmingCharacters(in: .whitespaces).dropFirst()
                if content.first == " " { content = content.dropFirst() }
                inner.append(String(content))
                index += 1
            } else if !isBlank(line), let last = inner.last, !isBlank(last), !startsBlock(lines, index) {
                inner.append(line) // lazy continuation
                index += 1
            } else {
                break
            }
        }
        return .quote(parseBlocks(inner))
    }

    // MARK: - Tables

    static func isTableStart(_ lines: [String], _ index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return lines[index].contains("|") && lines[index + 1].contains("|") && isTableDelimiter(lines[index + 1])
    }

    static func isTableDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        return splitRow(trimmed).allSatisfy { cell in
            var core = Substring(cell)
            if core.hasPrefix(":") { core = core.dropFirst() }
            if core.hasSuffix(":") { core = core.dropLast() }
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }

        var cells: [String] = []
        var current = ""
        var inCode = false
        var previous: Character?
        for character in trimmed {
            if character == "`" { inCode.toggle() }
            if character == "|", !inCode {
                if previous == "\\" {
                    current.removeLast()
                    current.append(character)
                } else {
                    cells.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else {
                current.append(character)
            }
            previous = character
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    static func parseTable(_ lines: [String], _ index: inout Int) -> MarkdownBlock {
        let header = splitRow(lines[index])
        var alignments = splitRow(lines[index + 1]).map { cell -> MarkdownTableAlignment in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            if left && right { return .center }
            return right ? .trailing : .leading
        }
        if alignments.count < header.count {
            alignments += Array(repeating: .leading, count: header.count - alignments.count)
        }
        alignments = Array(alignments.prefix(header.count))

        index += 2
        var rows: [[String]] = []
        while index < lines.count, !isBlank(lines[index]), lines[index].contains("|") {
            var row = splitRow(lines[index])
            if row.count < header.count {
                row += Array(repeating: "", count: header.count - row.count)
            }
            rows.append(Array(row.prefix(header.count)))
            index += 1
        }
        return .table(MarkdownTable(header: header, alignments: alignments, rows: rows))
    }

    // MARK: - Lists

    struct ListMarker {
        let indent: Int
        let ordered: Bool
        let number: Int
        let contentIndent: Int
        let content: String

        init?(_ line: String) {
            var column = 0
            var index = line.startIndex
            while index < line.endIndex, line[index] == " " || line[index] == "\t" {
                column += line[index] == "\t" ? 4 : 1
                index = line.index(after: index)
            }
            guard index < line.endIndex else { return nil }

            let markerStart = index
            var ordered = false
            var number = 1
            let first = line[index]
            if first == "-" || first == "*" || first == "+" {
                index = line.index(after: index)
            } else if first.isASCII, first.isNumber {
                var digits = ""
                while index < line.endIndex, line[index].isASCII, line[index].isNumber, digits.count < 9 {
                    digits.append(line[index])
                    index = line.index(after: index)
                }
                guard index < line.endIndex, line[index] == "." || line[index] == ")" else { return nil }
                index = line.index(after: index)
                ordered = true
                number = Int(digits) ?? 1
            } else {
                return nil
            }

            guard index < line.endIndex, line[index] == " " || line[index] == "\t" else { return nil }
            let markerWidth = line.distance(from: markerStart, to: index)
            var spaces = 0
            while index < line.endIndex, line[index] == " " || line[index] == "\t", spaces < 4 {
                spaces += 1
                index = line.index(after: index)
            }

            self.indent = column
            self.ordered = ordered
            self.number = number
            self.contentIndent = column + markerWidth + max(1, spaces)
            self.content = String(line[index...])
        }
    }

    static func parseList(_ lines: [String], _ index: inout Int) -> MarkdownList {
        let first = ListMarker(lines[index])!
        var items: [MarkdownListItem] = []

        while index < lines.count {
            guard !isThematicBreak(lines[index]),
                  let marker = ListMarker(lines[index]),
                  marker.ordered == first.ordered,
                  marker.indent <= first.indent + 1,
                  marker.indent + 1 >= first.indent
            else { break }

            var itemLines = [marker.content]
            var openFence = Fence(marker.content)
            var pendingBlanks = 0
            index += 1

            while index < lines.count {
                let line = lines[index]
                if let fence = openFence {
                    let stripped = removeIndent(line, count: marker.contentIndent)
                    itemLines.append(stripped)
                    index += 1
                    if fence.isClosing(stripped) { openFence = nil }
                    continue
                }
                if isBlank(line) {
                    pendingBlanks += 1
                    index += 1
                    continue
                }
                let indent = leadingSpaces(line)
                if indent <= first.indent + 1, isThematicBreak(line) || ListMarker(line) != nil {
                    break // sibling item, parent item or a rule
                }
                if indent >= marker.contentIndent || (indent > first.indent && ListMarker(line) != nil) {
                    itemLines.append(contentsOf: Array(repeating: "", count: pendingBlanks))
                    pendingBlanks = 0
                    let stripped = removeIndent(line, count: min(indent, marker.contentIndent))
                    itemLines.append(stripped)
                    openFence = Fence(stripped)
                    index += 1
                    continue
                }
                if pendingBlanks == 0, !startsBlock(lines, index) {
                    itemLines.append(line.trimmingCharacters(in: .whitespaces)) // lazy continuation
                    index += 1
                    continue
                }
                break
            }

            var isChecked: Bool?
            let head = itemLines[0]
            if head.hasPrefix("[ ] ") || head == "[ ]" {
                isChecked = false
                itemLines[0] = String(head.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if head.lowercased().hasPrefix("[x] ") || head.lowercased() == "[x]" {
                isChecked = true
                itemLines[0] = String(head.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
            items.append(MarkdownListItem(blocks: parseBlocks(itemLines), isChecked: isChecked))
        }
        return MarkdownList(ordered: first.ordered, startNumber: first.number, items: items)
    }

    // MARK: - Paragraphs

    static func parseParagraph(_ lines: [String], _ index: inout Int) -> MarkdownBlock {
        var parts = [lines[index].trimmingCharacters(in: .whitespaces)]
        index += 1
        while index < lines.count, !isBlank(lines[index]), !startsBlock(lines, index) {
            parts.append(lines[index].trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return .paragraph(parts.joined(separator: "\n"))
    }

    static func startsBlock(_ lines: [String], _ index: Int) -> Bool {
        let line = lines[index]
        return Fence(line) != nil
            || heading(line) != nil
            || isThematicBreak(line)
            || isQuoteLine(line)
            || ListMarker(line) != nil
            || isMathStart(line)
            || isTableStart(lines, index)
    }

    // MARK: - Helpers

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    static func removeIndent(_ line: String, count: Int) -> String {
        var removed = 0
        var index = line.startIndex
        while index < line.endIndex, removed < count {
            let character = line[index]
            if character == " " {
                removed += 1
            } else if character == "\t" {
                removed += 4
            } else {
                break
            }
            index = line.index(after: index)
        }
        return String(line[index...])
    }
}

/// Markdown → readable plain text, for previews, titles and read-aloud.
public enum MarkdownPlainText {
    public static func strip(_ markdown: String) -> String {
        var output: [String] = []
        var inFence = false
        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                output.append(rawLine)
                continue
            }
            var line = trimmed.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            while line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if MarkdownParser.isThematicBreak(line) { continue }
            if line.contains("|") {
                if MarkdownParser.isTableDelimiter(line) { continue }
                if line.hasPrefix("|") {
                    line = MarkdownParser.splitRow(line).joined(separator: " · ")
                }
            }
            if let marker = MarkdownParser.ListMarker(line) {
                line = marker.content
            }
            output.append(line)
        }

        var text = output.joined(separator: "\n")
        text = text.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for token in ["**", "__", "~~", "`"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
