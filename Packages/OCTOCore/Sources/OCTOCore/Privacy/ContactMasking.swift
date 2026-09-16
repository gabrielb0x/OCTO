import Foundation

/// Hides the email address and the phone number of the account behind dots, keeping just enough
/// for you to recognize them, so a screenshot, a stream or someone next to you learns nothing.
public enum ContactMasking {
    /// The dot used to replace a character. Narrower than "•", so a masked value keeps its width.
    static let dot = "•"

    /// `gabriel@example.com` becomes `g••••••@e••••••.com`: the first letter, the domain's first
    /// letter and the extension stay, which is enough to tell two accounts apart.
    public static func email(_ value: String) -> String {
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return text(address)
        }
        let domain = String(parts[1])
        let extensionIndex = domain.lastIndex(of: ".")
        let name = extensionIndex.map { String(domain[domain.startIndex..<$0]) } ?? domain
        let suffix = extensionIndex.map { String(domain[$0...]) } ?? ""
        return "\(keepingFirst(String(parts[0])))@\(keepingFirst(name))\(suffix)"
    }

    /// `+33 6 12 34 56 78` becomes `+•• • •• •• •• 78`: the spacing stays, the last two digits too.
    public static func phone(_ value: String) -> String {
        let number = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return number }
        let digitCount = number.filter(\.isNumber).count
        var seen = 0
        return String(number.map { character in
            // Spaces, "+" and dashes stay: the number keeps its shape without telling anything.
            guard character.isNumber else { return character }
            seen += 1
            // Only the last two digits, and only when hiding the others still hides something.
            return digitCount > 4 && seen > digitCount - 2 ? character : Character(dot)
        })
    }

    /// Any other value, such as a name: the first character, then dots.
    public static func text(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return keepingFirst(trimmed)
    }

    /// The first character followed by dots, at most eight so long values don't stretch a row.
    private static func keepingFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        guard value.count > 1 else { return dot }
        return String(first) + String(repeating: dot, count: min(value.count - 1, 8))
    }
}
