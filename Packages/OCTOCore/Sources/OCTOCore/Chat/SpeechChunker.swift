import Foundation

/// Splits a streamed Markdown reply into plain-text chunks that can be spoken
/// as soon as each sentence is complete, so voice mode starts talking early.
public struct SpeechChunker: Sendable {
    /// Number of characters of the reply already handed out.
    public private(set) var consumedCount = 0

    private static let terminators: Set<Character> = [".", "!", "?", "…", ":", ";", "。", "！", "？"]

    public init() {}

    /// Returns the text completed since the previous call, stripped of Markdown.
    /// `text` is the whole reply so far; pass `isFinal` once it stops growing.
    public mutating func nextChunk(in text: String, isFinal: Bool) -> String? {
        let characters = Array(text)
        guard consumedCount < characters.count else { return nil }

        var end = consumedCount
        if isFinal {
            end = characters.count
        } else {
            var lineStart = consumedCount
            for index in consumedCount..<characters.count {
                let character = characters[index]
                if character.isNewline {
                    end = index + 1
                    lineStart = index + 1
                } else if Self.terminators.contains(character), index + 1 < characters.count, characters[index + 1].isWhitespace,
                          !Self.isOrderedListMarker(characters[lineStart..<index]) {
                    end = index + 1
                }
            }
        }
        guard end > consumedCount else { return nil }

        let raw = String(characters[consumedCount..<end])
        consumedCount = end
        let spoken = MarkdownPlainText.strip(raw)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return spoken.isEmpty ? nil : spoken
    }

    /// "12." at the start of a line numbers a list item rather than ending a sentence.
    private static func isOrderedListMarker(_ prefix: ArraySlice<Character>) -> Bool {
        let trimmed = prefix.drop { $0 == " " || $0 == "\t" }
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)
    }
}
