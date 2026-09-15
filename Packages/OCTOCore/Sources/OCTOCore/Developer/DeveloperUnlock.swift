import Foundation

/// Counts the taps that turn on developer mode, like the build number on Android:
/// `requiredTaps` taps in a row, each less than `maximumGap` after the previous one.
public struct DeveloperUnlock: Sendable {
    public enum Progress: Equatable, Sendable {
        case counting(remaining: Int)
        case unlocked
    }

    public let requiredTaps: Int
    public let maximumGap: TimeInterval
    private var count = 0
    private var lastTap: Date?

    public init(requiredTaps: Int = 8, maximumGap: TimeInterval = 1.5) {
        self.requiredTaps = max(1, requiredTaps)
        self.maximumGap = maximumGap
    }

    public mutating func registerTap(at date: Date = Date()) -> Progress {
        if let lastTap, date < lastTap || date.timeIntervalSince(lastTap) > maximumGap {
            count = 0
        }
        lastTap = date
        count += 1
        guard count >= requiredTaps else {
            return .counting(remaining: requiredTaps - count)
        }
        count = 0
        lastTap = nil
        return .unlocked
    }
}

/// When OCTO asks for Face ID again.
public enum AppLockPolicy {
    /// `backgroundedAt` is nil on a cold launch, which always locks.
    public static func requiresUnlock(isEnabled: Bool, backgroundedAt: Date?, now: Date, timeout: TimeInterval) -> Bool {
        guard isEnabled else { return false }
        guard let backgroundedAt else { return true }
        return now.timeIntervalSince(backgroundedAt) >= max(timeout, 0)
    }
}

/// A new GitHub issue prefilled with the problem and, when allowed, details about the device.
public enum IssueReport {
    public static func body(description: String, diagnostics: [(label: String, value: String)], log: String?) -> String {
        var sections: [String] = []
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            sections.append(text)
        }
        if !diagnostics.isEmpty {
            let rows = diagnostics.map { "| \($0.label) | \($0.value.replacingOccurrences(of: "|", with: "/")) |" }
            sections.append((["| | |", "|---|---|"] + rows).joined(separator: "\n"))
        }
        if let log, !log.isEmpty {
            sections.append("<details><summary>Log</summary>\n\n```\n\(log)\n```\n</details>")
        }
        return sections.joined(separator: "\n\n")
    }

    /// Long bodies are shortened so the address stays under `maximumLength` characters.
    public static func newIssueURL(repository: URL, title: String, body: String, maximumLength: Int = 7_500) -> URL {
        func make(_ text: String) -> URL? {
            URL(string: "\(repository.absoluteString)/issues/new?title=\(FormEncoding.escape(title))&body=\(FormEncoding.escape(text))")
        }
        var text = body
        var shortened = false
        while let url = make(shortened ? text + "\n\n…" : text), url.absoluteString.count > maximumLength, !text.isEmpty {
            let excess = url.absoluteString.count - maximumLength
            text = String(text.prefix(max(0, text.count - max(100, excess / 3))))
            shortened = true
        }
        return make(shortened ? text + "\n\n…" : text) ?? repository
    }
}
