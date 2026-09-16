import Foundation

/// A device signed into the ChatGPT account (`GET /accounts/sessions`), as ChatGPT's own
/// "Devices" screen lists them: what it is, where it last signed in from, and which apps use it.
public struct AccountDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// "iPhone", "Computer", "Mac"…
    public var name: String
    /// "iPhone · iOS 26.6.2", as the account words it.
    public var summary: String?
    /// "ios", "macos", "windows", "android", "linux"…
    public var platform: String?
    public var osVersion: String?
    /// The device OCTO is running on, as the account sees it.
    public var isCurrentDevice: Bool
    public var isTrusted: Bool
    public var lastSignedInAt: Date?
    public var city: String?
    /// ISO country code such as "FR".
    public var countryCode: String?
    /// Apps signed in on that device: "ChatGPT Web", "Codex", "ChatGPT iOS App"…
    public var apps: [String]

    public init(
        id: String,
        name: String,
        summary: String? = nil,
        platform: String? = nil,
        osVersion: String? = nil,
        isCurrentDevice: Bool = false,
        isTrusted: Bool = false,
        lastSignedInAt: Date? = nil,
        city: String? = nil,
        countryCode: String? = nil,
        apps: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.platform = platform
        self.osVersion = osVersion
        self.isCurrentDevice = isCurrentDevice
        self.isTrusted = isTrusted
        self.lastSignedInAt = lastSignedInAt
        self.city = city
        self.countryCode = countryCode
        self.apps = apps
    }

    /// "Limoges, France" — the country name in the reader's language, the code as a fallback.
    public func location(locale: Locale = .current) -> String? {
        let country = countryCode.flatMap { code -> String? in
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return locale.localizedString(forRegionCode: trimmed) ?? trimmed
        }
        let parts = [city?.isEmpty == false ? city : nil, country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// The devices of the account, current device first, then the most recently used.
public struct AccountDevices: Codable, Equatable, Sendable {
    public var devices: [AccountDevice]
    /// Whether ChatGPT offers the session manager for this account.
    public var isManageable: Bool

    public init(devices: [AccountDevice], isManageable: Bool = true) {
        self.devices = devices
        self.isManageable = isManageable
    }

    public var isEmpty: Bool { devices.isEmpty }

    public static func parse(_ data: Data) -> AccountDevices? {
        guard let object = JSONValue.object(data), let entries = object["devices"] as? [[String: Any]] else { return nil }
        let devices = entries.compactMap { entry -> AccountDevice? in
            let id = JSONValue.string(entry["render_id"])
                ?? JSONValue.string(entry["session_id"])
                ?? JSONValue.string(entry["hashed_device_id"])
            guard let id, !id.isEmpty else { return nil }
            let apps = (entry["app_sessions"] as? [[String: Any]] ?? []).compactMap { session -> String? in
                let name = JSONValue.string(session["client_name"])?.trimmingCharacters(in: .whitespaces)
                return name?.isEmpty == false ? name : nil
            }
            let name = JSONValue.string(entry["display_name"])?.trimmingCharacters(in: .whitespaces)
                ?? JSONValue.string(entry["device_model"])?.trimmingCharacters(in: .whitespaces)
            return AccountDevice(
                id: id,
                name: name?.isEmpty == false ? name! : JSONValue.string(entry["platform"])?.capitalized ?? id,
                summary: JSONValue.string(entry["human_readable_description"]),
                platform: JSONValue.string(entry["platform"])?.lowercased(),
                osVersion: JSONValue.string(entry["os_version"]),
                isCurrentDevice: JSONValue.bool(entry["is_current_device"]) ?? false,
                isTrusted: JSONValue.bool(entry["is_trusted_device"]) ?? false,
                lastSignedInAt: FlexibleDate.parse(entry["last_signed_in_timestamp_second"]),
                city: JSONValue.string(entry["last_signed_in_city"]),
                countryCode: JSONValue.string(entry["last_signed_in_country"]),
                apps: apps.reduced()
            )
        }
        return AccountDevices(
            devices: devices.sorted { lhs, rhs in
                if lhs.isCurrentDevice != rhs.isCurrentDevice { return lhs.isCurrentDevice }
                return (lhs.lastSignedInAt ?? .distantPast) > (rhs.lastSignedInAt ?? .distantPast)
            },
            isManageable: JSONValue.bool(object["show_session_manager"]) ?? true
        )
    }
}

/// One way the account proves it's you: an authenticator code, a passkey, an SMS or a push.
public struct SecurityFactor: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case authenticator
        case passkey
        case sms
        case push
    }

    public var id: String
    public var kind: Kind
    /// Name of the passkey's authenticator, such as "Proton Pass".
    public var name: String?

    public init(id: String, kind: Kind, name: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
    }
}

/// How the ChatGPT account is protected (`GET /accounts/security_settings/info` and
/// `GET /accounts/mfa_info`). OCTO only reads it: these are changed in ChatGPT itself.
public struct AccountSecurity: Codable, Equatable, Sendable {
    /// ChatGPT's "Advanced protection".
    public var advancedProtectionEnabled: Bool?
    /// "new_devices", "all" or "off": when ChatGPT emails about a sign-in.
    public var loginNotificationMode: String?
    public var multiFactorEnabled: Bool?
    public var factors: [SecurityFactor]

    public init(
        advancedProtectionEnabled: Bool? = nil,
        loginNotificationMode: String? = nil,
        multiFactorEnabled: Bool? = nil,
        factors: [SecurityFactor] = []
    ) {
        self.advancedProtectionEnabled = advancedProtectionEnabled
        self.loginNotificationMode = loginNotificationMode
        self.multiFactorEnabled = multiFactorEnabled
        self.factors = factors
    }

    public var isEmpty: Bool {
        advancedProtectionEnabled == nil && loginNotificationMode == nil && multiFactorEnabled == nil && factors.isEmpty
    }

    /// Both calls together; either one may be missing when the account refuses it.
    public static func parse(settings: Data?, multiFactor: Data?) -> AccountSecurity? {
        var security = AccountSecurity()
        if let settings, let object = JSONValue.object(settings) {
            security.advancedProtectionEnabled = JSONValue.bool(object["advanced_protection_mode_enabled"])
            security.loginNotificationMode = JSONValue.string(object["login_notification_mode"])
        }
        if let multiFactor, let object = JSONValue.object(multiFactor) {
            security.multiFactorEnabled = JSONValue.bool(object["mfa_enabled_v2"]) ?? JSONValue.bool(object["mfa_enabled"])
            security.factors = factors(in: object["factors"] as? [String: Any] ?? [:])
        }
        return security.isEmpty ? nil : security
    }

    /// `factors` holds a list for some kinds and a single object for others.
    static func factors(in object: [String: Any]) -> [SecurityFactor] {
        let kinds: [(String, SecurityFactor.Kind)] = [
            ("totp", .authenticator),
            ("passkeys", .passkey),
            ("sms", .sms),
            ("push_auth", .push),
        ]
        var factors: [SecurityFactor] = []
        for (key, kind) in kinds {
            let entries: [[String: Any]]
            if let list = object[key] as? [[String: Any]] {
                entries = list
            } else if let single = object[key] as? [String: Any] {
                entries = [single]
            } else {
                continue
            }
            for (index, entry) in entries.enumerated() {
                let metadata = entry["metadata"] as? [String: Any] ?? [:]
                let name = JSONValue.string(metadata["authenticator_name"]) ?? JSONValue.string(metadata["factor_name"])
                factors.append(SecurityFactor(
                    id: JSONValue.string(entry["id"]) ?? "\(key)-\(index)",
                    kind: kind,
                    name: name?.isEmpty == false ? name : nil
                ))
            }
        }
        return factors
    }
}

private extension Array where Element == String {
    /// Keeps the first spelling of each name, in order.
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
