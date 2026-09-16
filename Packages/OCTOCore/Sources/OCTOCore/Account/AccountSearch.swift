import Foundation

/// A chat found in the ChatGPT account by `GET /conversations/search`, with the bit of the
/// conversation that matched. Searching on the account's side finds chats OCTO never downloaded,
/// and matches inside messages, not just titles.
public struct RemoteSearchHit: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// The matching passage, as ChatGPT returns it.
    public var snippet: String?
    public var updatedAt: Date?
    /// Project (`g-p-…`) the chat belongs to.
    public var projectID: String?

    public init(id: String, title: String, snippet: String? = nil, updatedAt: Date? = nil, projectID: String? = nil) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.updatedAt = updatedAt
        self.projectID = projectID
    }

    /// The hit as a chat of the list, so it can be opened like any other.
    public var summary: RemoteConversationSummary {
        RemoteConversationSummary(id: id, title: title, updatedAt: updatedAt, projectID: projectID)
    }
}

/// Results of `GET /conversations/search?query=…`. The payload is read loosely: the endpoint is
/// ChatGPT's own and its wrapper has changed names over time, so anything shaped like a list of
/// chats is accepted, and an unreadable answer simply finds nothing.
public enum RemoteSearchResults {
    /// ChatGPT wraps the matching words in its snippets; they're shown as plain text.
    static let highlightMarkers = ["<em>", "</em>", "<mark>", "</mark>", "<b>", "</b>", "<strong>", "</strong>"]

    public static func parse(_ data: Data) -> [RemoteSearchHit]? {
        guard let entries = list(in: data) else { return nil }
        var hits: [RemoteSearchHit] = []
        var seen = Set<String>()
        for entry in entries {
            let id = JSONValue.string(entry["conversation_id"]) ?? JSONValue.string(entry["id"])
            guard let id, !id.isEmpty, seen.insert(id).inserted else { continue }
            let createdAt = FlexibleDate.parse(entry["create_time"])
            hits.append(RemoteSearchHit(
                id: id,
                title: JSONValue.string(entry["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                snippet: snippet(in: entry),
                updatedAt: FlexibleDate.parse(entry["update_time"]) ?? createdAt,
                projectID: RemoteConversationParser.projectID(entry["gizmo_id"])
            ))
        }
        return hits
    }

    static func list(in data: Data) -> [[String: Any]]? {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let array = json as? [[String: Any]] { return array }
        guard let object = json as? [String: Any] else { return nil }
        for key in ["items", "conversations", "results", "data"] {
            if let array = object[key] as? [[String: Any]] { return array }
        }
        return nil
    }

    /// The matching passage, whichever name the payload gives it, cleaned of its highlight tags.
    static func snippet(in entry: [String: Any]) -> String? {
        var text = JSONValue.string(entry["snippet"])
            ?? JSONValue.string(entry["highlight"])
            ?? JSONValue.string(entry["preview"])
        if text == nil, let matches = entry["highlights"] as? [Any] {
            text = matches.compactMap { JSONValue.string($0) }.first
        }
        guard var cleaned = text else { return nil }
        for marker in highlightMarkers {
            cleaned = cleaned.replacingOccurrences(of: marker, with: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(200))
    }
}
