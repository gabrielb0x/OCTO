import Foundation

/// Endpoints of the ChatGPT account itself on `chatgpt.com/backend-api`: profile, settings,
/// custom instructions, memory and chat history. They are called with the same OAuth token as
/// the Codex backend. OCTO only reads and edits account data there: replies are still generated
/// through Codex, so nothing is ever posted into a ChatGPT conversation.
public enum ChatGPTAccountAPI {
    public static let baseURL = URL(string: "https://chatgpt.com/backend-api")!

    public static var profileURL: URL { url("me") }
    public static var settingsURL: URL { url("settings/user") }
    public static var customInstructionsURL: URL { url("user_system_messages") }
    public static var personalityTypesURL: URL { url("personality_types") }
    public static var personalityTraitsURL: URL { url("personality_trait_types") }
    public static var dataUsagePolicyURL: URL { url("accounts/data_usage_for_training") }
    public static var ageStatusURL: URL { url("settings/is_adult") }

    /// The advertising profile ChatGPT builds for the account ("bazaar" is its own name for ads).
    /// `DELETE` clears it, as ChatGPT's own ads screen does, and answers `204 No Content`.
    public static var adsProfileURL: URL { url("bazaar/profile") }

    /// `PATCH`, without a body, saves one setting of the account the way ChatGPT's settings do,
    /// e.g. `settings/account_user_setting?feature=training_allowed&value=false`.
    public static func accountUserSettingURL(_ feature: AccountSettingFeature, value: Bool) -> URL {
        url("settings/account_user_setting", query: [("feature", feature.rawValue), ("value", value ? "true" : "false")])
    }
    public static var memoriesURL: URL { url("memories", query: [("include_memory_entries", "true")]) }

    /// `DELETE` forgets one saved memory, as ChatGPT's own Memory screen does.
    public static func memoryURL(id: String) -> URL {
        url("memories/\(pathSegment(id))")
    }
    public static var accountCheckURL: URL { url("accounts/check/v4-2023-04-27") }

    /// What ChatGPT charges for its plans in a country, as its own plan picker reads it.
    public static func checkoutPricingURL(countryCode: String) -> URL {
        url("checkout_pricing_config/configs/\(CheckoutPricing.countryCode(for: countryCode))")
    }

    /// Devices signed into the account, as ChatGPT's own "Devices" screen lists them.
    public static var devicesURL: URL { url("accounts/sessions") }
    /// Advanced protection and sign-in alerts.
    public static var securitySettingsURL: URL { url("accounts/security_settings/info") }
    /// The account's second factors: authenticator, passkeys, SMS.
    public static var multiFactorURL: URL { url("accounts/mfa_info") }
    /// Space the files of the account's chats take on ChatGPT's side.
    public static var fileStorageURL: URL { url("files/library/storage/usage") }

    /// `POST /conversation/init`: the call the website makes when opening a new chat. Returns the
    /// account's live feature limits (Deep Research, image generation, file uploads…) and default model.
    public static var conversationInitURL: URL { url("conversation/init") }

    /// Body of `POST /conversation/init`, as the website sends it: no conversation, just the timezone.
    public static func conversationInitBody(timezone: String, offsetMinutes: Int) -> Data {
        let object: [String: Any] = [
            "conversation_id": NSNull(),
            "conversation_origin": NSNull(),
            "requested_default_model": NSNull(),
            "timezone": timezone,
            "timezone_offset_min": offsetMinutes,
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// A `backend-api` address typed in the developer console: a relative path with an optional
    /// query. Nil for anything that could point outside `chatgpt.com/backend-api`.
    public static func consoleURL(path input: String) -> URL? {
        var path = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://chatgpt.com/backend-api/", "chatgpt.com/backend-api/", "/backend-api/", "backend-api/", "/"] where path.hasPrefix(prefix) {
            path.removeFirst(prefix.count)
            break
        }
        guard !path.isEmpty, !path.contains("://"), !path.hasPrefix("/"), !path.contains("\\"), !path.contains("#") else { return nil }
        let pathPart = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let lowered = pathPart.lowercased()
        guard !lowered.contains("%2e"), !lowered.contains("%2f"), !lowered.contains("%5c") else { return nil }
        let segments = pathPart.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        guard let url = URL(string: baseURL.absoluteString + "/" + path),
              url.scheme == baseURL.scheme,
              url.host == baseURL.host,
              url.path.hasPrefix(baseURL.path + "/")
        else { return nil }
        return url
    }

    /// `PATCH` with `{"is_visible": false}` deletes every chat of the account.
    public static var allConversationsURL: URL { url("conversations") }

    public static func conversationsURL(offset: Int, limit: Int, archived: Bool = false) -> URL {
        url("conversations", query: [
            ("offset", String(offset)),
            ("limit", String(limit)),
            ("order", "updated"),
            ("is_archived", archived ? "true" : "false"),
        ])
    }

    /// `GET` returns the whole message tree, `PATCH` renames, archives or deletes the chat.
    public static func conversationURL(id: String) -> URL {
        url("conversation/\(pathSegment(id))")
    }

    /// Searches every chat of the account, inside the messages, the way ChatGPT's own search does.
    public static func conversationSearchURL(query: String) -> URL {
        url("conversations/search", query: [("query", query)])
    }

    /// Projects with their latest chats, as listed in the ChatGPT sidebar.
    public static func projectsURL(limit: Int = 20) -> URL {
        url("gizmos/snorlax/sidebar", query: [
            ("owned_only", "true"),
            ("conversations_per_gizmo", "5"),
            ("limit", String(limit)),
        ])
    }

    public static func projectConversationsURL(projectID: String, cursor: String?, limit: Int = 50) -> URL {
        url("gizmos/\(pathSegment(projectID))/conversations", query: [
            ("cursor", cursor ?? "0"),
            ("limit", String(limit)),
            ("owned_only", "true"),
        ])
    }

    /// Codex headers plus the language ChatGPT should use for labels such as personality names.
    public static func headers(accessToken: String, accountID: String?, userAgent: String, language: String?) -> [String: String] {
        var headers = CodexBackend.headers(accessToken: accessToken, accountID: accountID, userAgent: userAgent)
        headers["Accept"] = "application/json"
        if let language, !language.isEmpty {
            headers["OAI-Language"] = language
        }
        return headers
    }

    /// Body of `PATCH conversation/{id}` and `PATCH conversations`.
    public static func conversationUpdateBody(title: String? = nil, isVisible: Bool? = nil, isArchived: Bool? = nil) -> Data {
        var object: [String: Any] = [:]
        if let title { object["title"] = title }
        if let isVisible { object["is_visible"] = isVisible }
        if let isArchived { object["is_archived"] = isArchived }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func url(_ path: String, query: [(String, String)] = []) -> URL {
        var components = URLComponents(string: baseURL.absoluteString + "/" + path)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return components.url!
    }

    /// Keeps an identifier inside its path segment.
    static func pathSegment(_ value: String) -> String {
        FormEncoding.escape(value)
    }
}

/// Dates as the ChatGPT backend sends them: Unix seconds or ISO 8601 strings with up to
/// microseconds and a `Z` or `+00:00` offset (which `ISO8601DateFormatter` doesn't always accept).
public enum FlexibleDate {
    public static func parse(_ value: Any?) -> Date? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let seconds = Double(trimmed) {
                return Date(timeIntervalSince1970: seconds)
            }
            return iso8601(trimmed)
        }
        guard let seconds = JSONValue.double(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func iso8601(_ text: String) -> Date? {
        let bytes = Array(text.utf8)

        func number(_ start: Int, _ length: Int) -> Int? {
            guard start >= 0, start + length <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[start..<(start + length)] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }

        func byte(_ index: Int, is character: Character) -> Bool {
            index < bytes.count && bytes[index] == character.asciiValue
        }

        guard bytes.count >= 19,
              let year = number(0, 4), byte(4, is: "-"),
              let month = number(5, 2), byte(7, is: "-"),
              let day = number(8, 2), byte(10, is: "T") || byte(10, is: " "),
              let hour = number(11, 2), byte(13, is: ":"),
              let minute = number(14, 2), byte(16, is: ":"),
              let second = number(17, 2)
        else { return nil }

        var index = 19
        var fraction = 0.0
        if byte(index, is: ".") {
            index += 1
            var scale = 0.1
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                fraction += Double(bytes[index] - 48) * scale
                scale /= 10
                index += 1
            }
        }

        var offset = 0
        if byte(index, is: "+") || byte(index, is: "-") {
            guard let hours = number(index + 1, 2) else { return nil }
            var minutesStart = index + 3
            if byte(minutesStart, is: ":") { minutesStart += 1 }
            let minutes = number(minutesStart, 2) ?? 0
            offset = (hours * 3_600 + minutes * 60) * (byte(index, is: "-") ? -1 : 1)
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: components) else { return nil }
        return date.addingTimeInterval(fraction - Double(offset))
    }
}

public enum RemoteIdentifier {
    /// Local UUID of something stored in the ChatGPT account. Account ids are UUIDs and are
    /// reused as they are; any other id gets a stable UUID derived from it.
    public static func localID(for remoteID: String) -> UUID {
        if let uuid = UUID(uuidString: remoteID) {
            return uuid
        }
        // Two FNV-1a passes with different offsets fill the 128 bits.
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var first: UInt64 = 0xCBF2_9CE4_8422_2325
        var second: UInt64 = 0x6C62_272E_07BB_0142
        for byte in remoteID.utf8 {
            first = (first ^ UInt64(byte)) &* prime
            second = (second ^ UInt64(byte)) &* prime
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> UInt64(index * 8))
            bytes[8 + index] = UInt8(truncatingIfNeeded: second >> UInt64(index * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
