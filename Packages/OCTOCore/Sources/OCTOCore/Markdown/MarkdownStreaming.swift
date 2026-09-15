import Foundation

public enum MarkdownStreaming {
    /// Closes the bold and code span left open at the end of a reply being written, so a word such
    /// as "**Important" shows in bold right away instead of with its asterisks.
    public static func closingOpenInlineMarkers(_ text: String) -> String {
        guard text.contains("*") || text.contains("`"), !endsInsideCodeBlock(text) else { return text }
        let lineStart = text.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let line = text[lineStart...]
        // Asterisks inside a code span are literal.
        var outsideCode = ""
        var backticks = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "`" {
                var run = 0
                while index < line.endIndex, line[index] == "`" {
                    run += 1
                    index = line.index(after: index)
                }
                if run == 1 {
                    backticks += 1
                }
                continue
            }
            if backticks % 2 == 0 {
                outsideCode.append(line[index])
            }
            index = line.index(after: index)
        }
        if backticks % 2 == 1 {
            return text + "`"
        }
        return occurrences(of: "**", in: outsideCode) % 2 == 1 ? text + "**" : text
    }

    static func endsInsideCodeBlock(_ text: String) -> Bool {
        guard text.contains("```") || text.contains("~~~") else { return false }
        var isInside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInside.toggle()
            }
        }
        return isInside
    }

    static func occurrences(of marker: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let found = text.range(of: marker, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
    }
}
