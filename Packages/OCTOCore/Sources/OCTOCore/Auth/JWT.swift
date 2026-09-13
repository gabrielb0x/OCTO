import Foundation

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

/// Reads JWT payloads without verifying signatures: the tokens come straight
/// from auth.openai.com over TLS and are only used for display and routing.
public enum JWT {
    public static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let data = Base64URL.decode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func expirationDate(of token: String) -> Date? {
        guard let exp = JSONValue.double(payload(of: token)?["exp"]) else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

/// Account information carried by the ChatGPT OAuth tokens.
public struct ChatGPTAccountClaims: Equatable, Sendable {
    public var email: String?
    public var planType: String?
    public var accountID: String?
    public var userID: String?
    public var accessTokenExpiresAt: Date?

    public init(email: String? = nil, planType: String? = nil, accountID: String? = nil, userID: String? = nil, accessTokenExpiresAt: Date? = nil) {
        self.email = email
        self.planType = planType
        self.accountID = accountID
        self.userID = userID
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    public init(idToken: String?, accessToken: String?) {
        let id = idToken.flatMap { JWT.payload(of: $0) } ?? [:]
        let access = accessToken.flatMap { JWT.payload(of: $0) } ?? [:]
        let authKey = "https://api.openai.com/auth"
        let profileKey = "https://api.openai.com/profile"
        let idAuth = id[authKey] as? [String: Any] ?? [:]
        let accessAuth = access[authKey] as? [String: Any] ?? [:]
        let idProfile = id[profileKey] as? [String: Any] ?? [:]
        let accessProfile = access[profileKey] as? [String: Any] ?? [:]

        email = JSONValue.string(id["email"])
            ?? JSONValue.string(idProfile["email"])
            ?? JSONValue.string(accessProfile["email"])
        planType = JSONValue.string(idAuth["chatgpt_plan_type"]) ?? JSONValue.string(accessAuth["chatgpt_plan_type"])
        accountID = JSONValue.string(idAuth["chatgpt_account_id"]) ?? JSONValue.string(accessAuth["chatgpt_account_id"])
        userID = JSONValue.string(idAuth["chatgpt_user_id"])
            ?? JSONValue.string(idAuth["user_id"])
            ?? JSONValue.string(accessAuth["chatgpt_user_id"])
        accessTokenExpiresAt = JSONValue.double(access["exp"]).map { Date(timeIntervalSince1970: $0) }
    }
}

public enum ChatGPTPlan {
    /// Human-readable plan name for a raw `chatgpt_plan_type` value.
    public static func displayName(for rawValue: String?) -> String? {
        guard let raw = rawValue?.lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite", "pro_lite": return "Pro Lite"
        case "team": return "Team"
        case "business", "self_serve_business_prolite", "self_serve_business_usage_based": return "Business"
        case "enterprise", "hc", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based": return "Enterprise"
        case "edu", "education": return "Edu"
        case "edu_plus": return "Edu Plus"
        case "edu_pro": return "Edu Pro"
        default:
            return raw.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }
}

/// Lenient accessors for `JSONSerialization` output, whose number types differ
/// between Darwin (NSNumber) and swift-corelibs-foundation.
public enum JSONValue {
    public static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        default: return nil
        }
    }

    public static func double(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let int64 as Int64: return Double(int64)
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public static func int(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let int64 as Int64: return Int(int64)
        case let double as Double: return Int(double)
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String: return ["true", "1", "yes"].contains(string.lowercased())
        default: return nil
        }
    }

    public static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
