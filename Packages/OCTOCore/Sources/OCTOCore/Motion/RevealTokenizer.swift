import Foundation

/// Cuts a reply into the pieces revealed one at a time: a word with the spaces and line breaks
/// before it, or a single character of the scripts written without spaces (Chinese, Japanese,
/// Thai…). Runs without any space, such as long links, are cut every `maximumLength` characters
/// so they don't hold the reply back.
public struct RevealTokenizer: Sendable {
    public var maximumLength: Int
    /// Text received that doesn't make a complete piece yet.
    public private(set) var pending = ""

    public init(maximumLength: Int = 24) {
        self.maximumLength = max(maximumLength, 1)
    }

    /// Adds streamed text and returns the pieces it completed. A word is complete once what
    /// follows it has arrived.
    public mutating func append(_ text: String) -> [String] {
        pending += text
        let scan = Self.scan(pending, maximumLength: maximumLength, isFinal: false)
        let pieces = scan.ranges.map { String(pending[$0]) }
        if scan.end > pending.startIndex {
            pending = String(pending[scan.end...])
        }
        return pieces
    }

    /// Whatever is left, once the stream is over.
    public mutating func finish() -> [String] {
        let pieces = Self.scan(pending, maximumLength: maximumLength, isFinal: true).ranges.map { String(pending[$0]) }
        pending = ""
        return pieces
    }

    /// The pieces of a complete text, in the order they're revealed. Spaces ending the text join the last piece.
    public static func ranges<Characters: BidirectionalCollection>(in text: Characters, maximumLength: Int = 24) -> [Range<Characters.Index>] where Characters.Element == Character {
        scan(text, maximumLength: max(maximumLength, 1), isFinal: true).ranges
    }

    public static func count<Characters: BidirectionalCollection>(in text: Characters, maximumLength: Int = 24) -> Int where Characters.Element == Character {
        ranges(in: text, maximumLength: maximumLength).count
    }

    static func scan<Characters: BidirectionalCollection>(_ text: Characters, maximumLength: Int, isFinal: Bool) -> (ranges: [Range<Characters.Index>], end: Characters.Index) where Characters.Element == Character {
        var ranges: [Range<Characters.Index>] = []
        var start = text.startIndex
        var index = start
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }
            if isWrittenWithoutSpaces(text[index]) {
                index = text.index(after: index)
            } else {
                var length = 0
                while index < text.endIndex, length < maximumLength, !text[index].isWhitespace, !isWrittenWithoutSpaces(text[index]) {
                    index = text.index(after: index)
                    length += 1
                }
                // The word may go on in the next chunk.
                if index == text.endIndex, length < maximumLength, !isFinal {
                    return (ranges, start)
                }
            }
            ranges.append(start..<index)
            start = index
        }
        if isFinal, start < text.endIndex {
            if let last = ranges.popLast() {
                ranges.append(last.lowerBound..<text.endIndex)
            } else {
                ranges.append(start..<text.endIndex)
            }
            start = text.endIndex
        }
        return (ranges, start)
    }

    static func isWrittenWithoutSpaces(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if scalar.properties.isIdeographic {
            return true
        }
        switch scalar.value {
        case 0x0E00...0x0EFF, // Thai, Lao
             0x1000...0x109F, // Myanmar
             0x1780...0x17FF, // Khmer
             0x3000...0x30FF, // CJK punctuation, Hiragana, Katakana
             0x31F0...0x31FF, // Katakana extensions
             0xFF00...0xFFEF: // Full-width forms
            return true
        default:
            return false
        }
    }
}

/// Recognizes the pieces of a reply that are only Markdown syntax, such as a list bullet, a
/// heading's hashes or a code fence. They show no word of their own, so they appear with the word
/// after them instead of taking a turn, and the words on screen keep matching the pieces revealed.
public struct RevealSyntax: Sendable {
    private var isInCodeBlock = false
    private var isFirstPiece = true

    public init() {}

    /// Call with every piece, in order.
    public mutating func isSyntaxOnly(_ piece: String) -> Bool {
        let startsLine = isFirstPiece || piece.prefix(while: \.isWhitespace).contains(where: \.isNewline)
        isFirstPiece = false
        let word = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return true }
        if isInCodeBlock {
            if startsLine, Self.fenceInfo(word)?.isEmpty == true {
                isInCodeBlock = false
                return true
            }
            return false
        }
        if startsLine {
            if Self.fenceInfo(word) != nil {
                isInCodeBlock = true
                return true
            }
            if Self.isLineMarker(word) {
                return true
            }
        }
        return Self.isTableSyntax(word)
    }

    /// The language of a code fence such as ```swift, empty for a bare fence, nil for anything else.
    static func fenceInfo(_ word: String) -> String? {
        guard let first = word.first, first == "`" || first == "~" else { return nil }
        let run = word.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        let info = word.dropFirst(run)
        if first == "`", info.contains("`") {
            return nil
        }
        return String(info)
    }

    /// Bullets, numbers, heading hashes, quote marks, rules and math delimiters starting a line.
    static func isLineMarker(_ word: String) -> Bool {
        if ["-", "*", "+", "$$", "\\[", "\\]"].contains(word) {
            return true
        }
        if word.allSatisfy({ $0 == "#" }) {
            return word.count <= 6
        }
        if word.allSatisfy({ $0 == ">" }) {
            return true
        }
        if word.count >= 3, let first = word.first, "-*_".contains(first), word.allSatisfy({ $0 == first }) {
            return true
        }
        if let last = word.last, last == "." || last == ")" {
            let digits = word.dropLast()
            return !digits.isEmpty && digits.count <= 9 && digits.allSatisfy { $0.isASCII && $0.isNumber }
        }
        return false
    }

    /// Table pipes and delimiter rows such as `|---|:---:|`.
    static func isTableSyntax(_ word: String) -> Bool {
        word.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" } && (word.contains("|") || word.count >= 3)
    }
}
