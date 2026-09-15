import Foundation

/// A version of OCTO published on GitHub, read from the releases API to tell when an update is out.
public struct AppRelease: Codable, Equatable, Sendable, Identifiable {
    public var version: String
    public var title: String?
    /// The release notes, in Markdown.
    public var notes: String
    public var pageURL: URL
    public var ipaURL: URL?
    public var ipaSize: Int?
    public var publishedAt: Date?

    public var id: String { version }

    public init(version: String, title: String? = nil, notes: String = "", pageURL: URL, ipaURL: URL? = nil, ipaSize: Int? = nil, publishedAt: Date? = nil) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.ipaURL = ipaURL
        self.ipaSize = ipaSize
        self.publishedAt = publishedAt
    }

    /// `GET /repos/{owner}/{repo}/releases/latest`: the newest release that isn't a draft or a pre-release.
    public static func latestURL(repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    public static func parse(_ data: Data) -> AppRelease? {
        guard let object = JSONValue.object(data),
              JSONValue.bool(object["draft"]) != true,
              JSONValue.bool(object["prerelease"]) != true,
              let version = JSONValue.string(object["tag_name"]).flatMap(SemanticVersion.init),
              let pageURL = JSONValue.string(object["html_url"]).flatMap(URL.init(string:))
        else { return nil }
        let assets = object["assets"] as? [[String: Any]] ?? []
        let ipa = assets.first { (JSONValue.string($0["name"]) ?? "").lowercased().hasSuffix(".ipa") }
        return AppRelease(
            version: version.description,
            title: JSONValue.string(object["name"]),
            notes: (JSONValue.string(object["body"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: pageURL,
            ipaURL: ipa.flatMap { JSONValue.string($0["browser_download_url"]) }.flatMap(URL.init(string:)),
            ipaSize: ipa.flatMap { JSONValue.int($0["size"]) },
            publishedAt: FlexibleDate.parse(object["published_at"])
        )
    }

    public func isNewer(than installedVersion: String) -> Bool {
        guard let release = SemanticVersion(version), let installed = SemanticVersion(installedVersion) else { return false }
        return release > installed
    }

    /// A link that installs the IPA with a sideloading app: `altstore://install?url=…` or `sidestore://install?url=…`.
    public func installURL(scheme: String) -> URL? {
        guard let ipaURL else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "install"
        components.queryItems = [URLQueryItem(name: "url", value: ipaURL.absoluteString)]
        return components.url
    }
}

/// A version number such as "1.4.0" or "v1.4", compared number by number.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let numbers: [Int]

    public init?(_ text: String) {
        var core = Substring(text.trimmingCharacters(in: .whitespaces))
        if core.first == "v" || core.first == "V" {
            core = core.dropFirst()
        }
        // Pre-release and build suffixes don't take part in the comparison.
        if let suffix = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = core[..<suffix]
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        self.numbers = numbers
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

public enum UpdateSchedule {
    /// Automatic checks run at most every `interval`, so GitHub sees OCTO a few times a day at most.
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = 6 * 3_600) -> Bool {
        guard let lastCheck else { return true }
        // A clock set back doesn't block checks.
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }
}
