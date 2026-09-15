import Foundation

/// Hides credentials in the requests and responses shown by OCTO's developer tools.
/// The network log only ever keeps these redacted copies.
public enum HTTPLogRedactor {
    public static let placeholder = "<redacted>"

    /// JSON fields holding credentials. Error codes and messages stay readable.
    static let sensitiveFields: Set<String> = [
        "access_token", "refresh_token", "id_token", "token", "code_verifier",
        "authorization_code", "client_secret", "password", "device_auth_id",
    ]

    /// Form and query parameters holding credentials.
    static let sensitiveParameters: Set<String> = [
        "code", "code_verifier", "refresh_token", "access_token", "id_token", "token", "client_secret",
    ]

    public static func headers(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (name, value) in headers {
            switch name.lowercased() {
            case "authorization", "proxy-authorization":
                if let space = value.firstIndex(of: " ") {
                    result[name] = "\(value[..<space]) \(placeholder)"
                } else {
                    result[name] = placeholder
                }
            case "cookie", "set-cookie":
                result[name] = placeholder
            default:
                result[name] = value
            }
        }
        return result
    }

    /// A readable preview of a body: JSON is indented, credentials are hidden, binary data is summarized.
    public static func body(_ data: Data?, contentType: String?, limit: Int = 64_000) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let type = contentType?.lowercased() ?? ""
        if type.hasPrefix("multipart/") {
            // Uploads, such as dictation recordings, stay out of the log.
            return "<\(data.count) bytes of form data>"
        }
        if type.contains("json") || data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "["),
           let object = try? JSONSerialization.jsonObject(with: data) {
            let cleaned = redactJSON(object)
            if JSONSerialization.isValidJSONObject(cleaned),
               let pretty = try? JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                return truncate(redactTokens(String(decoding: pretty, as: UTF8.self)), limit: limit)
            }
        }
        if type.contains("x-www-form-urlencoded") {
            return truncate(redactParameters(String(decoding: data, as: UTF8.self)), limit: limit)
        }
        guard !type.hasPrefix("image/"), !type.hasPrefix("audio/"), !type.hasPrefix("video/"),
              let text = String(data: data, encoding: .utf8)
        else {
            return "<\(data.count) bytes>"
        }
        return truncate(redactTokens(redactText(text)), limit: limit)
    }

    /// The URL with credentials in its query hidden.
    public static func url(_ url: URL) -> String {
        let absolute = url.absoluteString
        guard let mark = absolute.firstIndex(of: "?") else { return absolute }
        var query = absolute[absolute.index(after: mark)...]
        var fragment = ""
        if let hash = query.firstIndex(of: "#") {
            fragment = String(query[hash...])
            query = query[..<hash]
        }
        return String(absolute[..<mark]) + "?" + redactParameters(String(query)) + fragment
    }

    /// `name=value&…` pairs with the values of credentials hidden.
    public static func redactParameters(_ pairs: String) -> String {
        pairs.split(separator: "&", omittingEmptySubsequences: false).map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return String(pair) }
            let name = String(parts[0])
            let decoded = (name.removingPercentEncoding ?? name).lowercased()
            return sensitiveParameters.contains(decoded) ? "\(name)=\(placeholder)" : String(pair)
        }.joined(separator: "&")
    }

    /// A cURL command reproducing a request, with the access token left as a shell variable.
    public static func curlCommand(method: String, url: URL, headers: [String: String], body: String?) -> String {
        var parts = ["curl -X \(method) \(shellQuoted(Self.url(url)))"]
        for name in headers.keys.sorted() {
            if name.lowercased() == "authorization" {
                parts.append("-H \"Authorization: Bearer $CHATGPT_ACCESS_TOKEN\"")
            } else {
                parts.append("-H \(shellQuoted("\(name): \(headers[name] ?? "")"))")
            }
        }
        if let body, !body.isEmpty {
            parts.append("--data-raw \(shellQuoted(body))")
        }
        return parts.joined(separator: " \\\n  ")
    }

    static func redactJSON(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in object {
                result[key] = sensitiveFields.contains(key.lowercased()) && !(item is NSNull) ? placeholder : redactJSON(item)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(redactJSON)
        }
        return value
    }

    /// Credentials in text that isn't valid JSON, such as a truncated body.
    static func redactText(_ text: String) -> String {
        var result = text
        for field in sensitiveFields.sorted() where result.contains(field) {
            result = result.replacingOccurrences(
                of: "\"\(field)\"\\s*:\\s*\"[^\"]*\"",
                with: "\"\(field)\": \"\(placeholder)\"",
                options: .regularExpression
            )
        }
        return result
    }

    /// Anything shaped like a JSON Web Token.
    static func redactTokens(_ text: String) -> String {
        guard text.contains("eyJ") else { return text }
        return text.replacingOccurrences(
            of: "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}",
            with: placeholder,
            options: .regularExpression
        )
    }

    static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
