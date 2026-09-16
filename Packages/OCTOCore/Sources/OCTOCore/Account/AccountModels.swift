import Foundation

/// The signed-in ChatGPT user (`GET /me`).
public struct AccountProfile: Codable, Equatable, Sendable {
    public var userID: String?
    public var name: String?
    public var email: String?
    public var pictureURL: URL?
    public var phoneNumber: String?
    /// Multi-factor authentication, when the account reports it.
    public var mfaEnabled: Bool?
    public var createdAt: Date?

    public init(
        userID: String? = nil,
        name: String? = nil,
        email: String? = nil,
        pictureURL: URL? = nil,
        phoneNumber: String? = nil,
        mfaEnabled: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.userID = userID
        self.name = name
        self.email = email
        self.pictureURL = pictureURL
        self.phoneNumber = phoneNumber
        self.mfaEnabled = mfaEnabled
        self.createdAt = createdAt
    }

    public static func parse(_ data: Data) -> AccountProfile? {
        guard let object = JSONValue.object(data) else { return nil }
        let name = JSONValue.string(object["name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = JSONValue.string(object["phone_number"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let picture = JSONValue.string(object["picture"]).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let profile = AccountProfile(
            userID: JSONValue.string(object["id"]),
            name: name?.isEmpty == false ? name : nil,
            email: JSONValue.string(object["email"]),
            pictureURL: picture,
            phoneNumber: phone?.isEmpty == false ? phone : nil,
            mfaEnabled: JSONValue.bool(object["mfa_flag_enabled"]),
            createdAt: FlexibleDate.parse(object["created"])
        )
        guard profile.userID != nil || profile.email != nil else { return nil }
        return profile
    }
}

/// The few account settings OCTO shows (`GET /settings/user`).
public struct AccountSettings: Codable, Equatable, Sendable {
    /// "Reference saved memories".
    public var referencesSavedMemories: Bool?
    /// "Reference chat history".
    public var referencesChatHistory: Bool?
    /// "Improve the model for everyone", the choice made in ChatGPT's Data controls.
    public var trainingAllowed: Bool?
    /// Audio recordings of voice chats are included in training.
    public var voiceTrainingAllowed: Bool?
    /// Video recordings are included in training.
    public var videoTrainingAllowed: Bool?
    /// The same choice for Codex, which generates the replies to messages written in OCTO.
    public var codexTrainingAllowed: Bool?
    public var voiceName: String?
    public var voiceLanguage: String?
    /// Ads picked from what the account does ("bazaar" is ChatGPT's own name for its ads).
    public var adsPersonalizationEnabled: Bool?
    /// ChatGPT keeps a history of the ads the account was shown and interacted with.
    public var adsHistoryEnabled: Bool?
    /// Whether the account has already answered ChatGPT's question about personalized ads.
    /// Read only: it's set by answering in ChatGPT, not by a switch.
    public var adsPersonalizationConsentSet: Bool?
    /// A free account that chose fewer messages over ads.
    public var freeAdsOptOut: Bool?

    public init(
        referencesSavedMemories: Bool? = nil,
        referencesChatHistory: Bool? = nil,
        trainingAllowed: Bool? = nil,
        voiceTrainingAllowed: Bool? = nil,
        videoTrainingAllowed: Bool? = nil,
        codexTrainingAllowed: Bool? = nil,
        voiceName: String? = nil,
        voiceLanguage: String? = nil,
        adsPersonalizationEnabled: Bool? = nil,
        adsHistoryEnabled: Bool? = nil,
        adsPersonalizationConsentSet: Bool? = nil,
        freeAdsOptOut: Bool? = nil
    ) {
        self.referencesSavedMemories = referencesSavedMemories
        self.referencesChatHistory = referencesChatHistory
        self.trainingAllowed = trainingAllowed
        self.voiceTrainingAllowed = voiceTrainingAllowed
        self.videoTrainingAllowed = videoTrainingAllowed
        self.codexTrainingAllowed = codexTrainingAllowed
        self.voiceName = voiceName
        self.voiceLanguage = voiceLanguage
        self.adsPersonalizationEnabled = adsPersonalizationEnabled
        self.adsHistoryEnabled = adsHistoryEnabled
        self.adsPersonalizationConsentSet = adsPersonalizationConsentSet
        self.freeAdsOptOut = freeAdsOptOut
    }

    public subscript(feature: AccountSettingFeature) -> Bool? {
        get {
            switch feature {
            case .trainingAllowed: return trainingAllowed
            case .voiceTrainingAllowed: return voiceTrainingAllowed
            case .videoTrainingAllowed: return videoTrainingAllowed
            case .codexTrainingAllowed: return codexTrainingAllowed
            case .referencesSavedMemories: return referencesSavedMemories
            case .referencesChatHistory: return referencesChatHistory
            case .adsPersonalization: return adsPersonalizationEnabled
            case .adsHistory: return adsHistoryEnabled
            case .freeAdsOptOut: return freeAdsOptOut
            }
        }
        set {
            switch feature {
            case .trainingAllowed: trainingAllowed = newValue
            case .voiceTrainingAllowed: voiceTrainingAllowed = newValue
            case .videoTrainingAllowed: videoTrainingAllowed = newValue
            case .codexTrainingAllowed: codexTrainingAllowed = newValue
            case .referencesSavedMemories: referencesSavedMemories = newValue
            case .referencesChatHistory: referencesChatHistory = newValue
            case .adsPersonalization: adsPersonalizationEnabled = newValue
            case .adsHistory: adsHistoryEnabled = newValue
            case .freeAdsOptOut: freeAdsOptOut = newValue
            }
        }
    }

    public static func parse(_ data: Data) -> AccountSettings? {
        guard let object = JSONValue.object(data), let settings = object["settings"] as? [String: Any] else { return nil }
        return AccountSettings(
            referencesSavedMemories: JSONValue.bool(settings["sunshine"]),
            referencesChatHistory: JSONValue.bool(settings["moonshine"]),
            trainingAllowed: JSONValue.bool(settings["training_allowed"]),
            voiceTrainingAllowed: JSONValue.bool(settings["voice_training_allowed"]),
            videoTrainingAllowed: JSONValue.bool(settings["video_training_allowed"]),
            codexTrainingAllowed: JSONValue.bool(settings["codex_training_allowed_v2"]) ?? JSONValue.bool(settings["codex_training_allowed"]),
            voiceName: JSONValue.string(settings["voice_name"]),
            voiceLanguage: JSONValue.string(settings["voice_main_language"]),
            adsPersonalizationEnabled: JSONValue.bool(settings["bazaar_personalization_enabled"]),
            adsHistoryEnabled: JSONValue.bool(settings["bazaar_history_enabled"]),
            adsPersonalizationConsentSet: JSONValue.bool(settings["bazaar_personalization_consent_set"]),
            freeAdsOptOut: JSONValue.bool(settings["free_ads_opt_out"])
        )
    }
}

/// Settings of the account OCTO changes, by their key in `settings/user`, as ChatGPT's web app names them.
public enum AccountSettingFeature: String, CaseIterable, Sendable {
    /// "Improve the model for everyone".
    case trainingAllowed = "training_allowed"
    case voiceTrainingAllowed = "voice_training_allowed"
    case videoTrainingAllowed = "video_training_allowed"
    /// Codex's "Improve the model for everyone".
    case codexTrainingAllowed = "codex_training_allowed_v2"
    /// "Reference saved memories": ChatGPT's own name for the setting is "sunshine".
    case referencesSavedMemories = "sunshine"
    /// "Reference chat history", named "moonshine".
    case referencesChatHistory = "moonshine"
    /// Ads chosen from what the account does.
    case adsPersonalization = "bazaar_personalization_enabled"
    /// The history of the ads the account was shown.
    case adsHistory = "bazaar_history_enabled"
    /// A free account trading ads for fewer messages.
    case freeAdsOptOut = "free_ads_opt_out"
}

/// Whether the account's policy lets its data be used for training at all
/// (`GET /accounts/data_usage_for_training`, "permitted" for personal accounts). It says nothing
/// about the user's own choice, which is `AccountSettings.trainingAllowed`.
public enum TrainingPolicy {
    public static func parse(_ data: Data) -> Bool? {
        guard let object = JSONValue.object(data),
              let value = JSONValue.string(object["data_usage_for_training"])?.lowercased()
        else { return nil }
        switch value {
        case "permitted", "allowed", "enabled", "opted_in", "true":
            return true
        case "denied", "not_permitted", "disabled", "opted_out", "false":
            return false
        default:
            return nil
        }
    }
}

/// Custom instructions and personality (`GET` and `POST /user_system_messages`).
public struct CustomInstructions: Codable, Sendable {
    public var isEnabled: Bool
    public var nickname: String
    public var occupation: String
    public var aboutUser: String
    /// "Custom instructions": how ChatGPT should respond.
    public var responseStyle: String
    /// Key from the personality catalog, such as "default" or "cynic".
    public var personality: String?
    /// Trait key → level ("more", "default" or "less").
    public var traits: [String: String]
    /// The payload as received, so saving keeps the fields OCTO doesn't edit.
    public var raw: Data?

    public init(
        isEnabled: Bool = true,
        nickname: String = "",
        occupation: String = "",
        aboutUser: String = "",
        responseStyle: String = "",
        personality: String? = nil,
        traits: [String: String] = [:],
        raw: Data? = nil
    ) {
        self.isEnabled = isEnabled
        self.nickname = nickname
        self.occupation = occupation
        self.aboutUser = aboutUser
        self.responseStyle = responseStyle
        self.personality = personality
        self.traits = traits
        self.raw = raw
    }

    public static func parse(_ data: Data) -> CustomInstructions? {
        guard let object = JSONValue.object(data) else { return nil }
        func text(_ keys: String...) -> String {
            for key in keys {
                if let value = JSONValue.string(object[key]), !value.isEmpty { return value }
            }
            return ""
        }
        var traits: [String: String] = [:]
        for (key, value) in object["personality_traits"] as? [String: Any] ?? [:] {
            if let level = JSONValue.string(value) { traits[key] = level }
        }
        return CustomInstructions(
            isEnabled: JSONValue.bool(object["enabled"]) ?? true,
            nickname: text("name_user_message"),
            occupation: text("role_user_message"),
            aboutUser: text("other_user_message", "about_user_message"),
            responseStyle: text("traits_model_message", "about_model_message"),
            personality: JSONValue.string(object["personality_type_selection"]),
            traits: traits,
            raw: data
        )
    }

    /// Body for `POST /user_system_messages`. The legacy fields get the same text as the new ones.
    public func requestBody() -> Data {
        var object = raw.flatMap { JSONValue.object($0) } ?? [:]
        object.removeValue(forKey: "object")
        object["enabled"] = isEnabled
        object["name_user_message"] = nickname
        object["role_user_message"] = occupation
        object["other_user_message"] = aboutUser
        object["about_user_message"] = aboutUser
        object["traits_model_message"] = responseStyle
        object["about_model_message"] = responseStyle
        if let personality {
            object["personality_type_selection"] = personality
        }
        object["personality_traits"] = traits
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

extension CustomInstructions: Equatable {
    /// Compares what the user can edit, not the raw payload.
    public static func == (lhs: CustomInstructions, rhs: CustomInstructions) -> Bool {
        lhs.isEnabled == rhs.isEnabled
            && lhs.nickname == rhs.nickname
            && lhs.occupation == rhs.occupation
            && lhs.aboutUser == rhs.aboutUser
            && lhs.responseStyle == rhs.responseStyle
            && lhs.personality == rhs.personality
            && lhs.traits == rhs.traits
    }
}

public struct PersonalityOption: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var summary: String?

    public var id: String { key }

    public init(key: String, label: String, summary: String? = nil) {
        self.key = key
        self.label = label
        self.summary = summary
    }
}

public struct PersonalityTrait: Codable, Equatable, Sendable, Identifiable {
    public struct Level: Codable, Equatable, Sendable, Identifiable {
        public var key: String
        public var label: String
        public var summary: String?

        public var id: String { key }

        public init(key: String, label: String, summary: String? = nil) {
            self.key = key
            self.label = label
            self.summary = summary
        }
    }

    public var key: String
    public var label: String
    public var levels: [Level]

    public var id: String { key }

    public init(key: String, label: String, levels: [Level]) {
        self.key = key
        self.label = label
        self.levels = levels
    }
}

/// Base styles (`GET /personality_types`) and characteristics (`GET /personality_trait_types`),
/// labeled in the language sent with `OAI-Language`.
public enum PersonalityCatalog {
    public static func parseTypes(_ data: Data) -> [PersonalityOption]? {
        guard let entries = list(in: data, keys: ["personality_types", "items"]) else { return nil }
        return entries.compactMap { entry in
            guard JSONValue.bool(entry["deprecated"]) != true,
                  let key = JSONValue.string(entry["key"]), !key.isEmpty
            else { return nil }
            return PersonalityOption(
                key: key,
                label: JSONValue.string(entry["label"]) ?? key.capitalized,
                summary: JSONValue.string(entry["description"])
            )
        }
    }

    public static func parseTraits(_ data: Data) -> [PersonalityTrait]? {
        guard let entries = list(in: data, keys: ["trait_types", "items"]) else { return nil }
        return entries.compactMap { entry in
            guard JSONValue.bool(entry["deprecated"]) != true,
                  let key = JSONValue.string(entry["key"]), !key.isEmpty
            else { return nil }
            let levels = (entry["levels"] as? [[String: Any]] ?? []).compactMap { level -> PersonalityTrait.Level? in
                guard let levelKey = JSONValue.string(level["key"]), !levelKey.isEmpty else { return nil }
                let label = JSONValue.string(level["option_label"]).flatMap { $0.isEmpty ? nil : $0 }
                    ?? JSONValue.string(level["label"]).flatMap { $0.isEmpty ? nil : $0 }
                    ?? levelKey.capitalized
                return PersonalityTrait.Level(key: levelKey, label: label, summary: JSONValue.string(level["description"]))
            }
            return PersonalityTrait(key: key, label: JSONValue.string(entry["label"]) ?? key.capitalized, levels: levels)
        }
    }

    static func list(in data: Data, keys: [String]) -> [[String: Any]]? {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let array = json as? [[String: Any]] {
            return array
        }
        if let object = json as? [String: Any] {
            for key in keys {
                if let array = object[key] as? [[String: Any]] { return array }
            }
        }
        return nil
    }
}

public struct SavedMemory: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var content: String
    public var updatedAt: Date?

    public init(id: String, content: String, updatedAt: Date? = nil) {
        self.id = id
        self.content = content
        self.updatedAt = updatedAt
    }
}

/// Saved memories (`GET /memories?include_memory_entries=true`).
public struct MemoriesSnapshot: Codable, Equatable, Sendable {
    public var memories: [SavedMemory]
    public var usedTokens: Int?
    public var maxTokens: Int?

    public init(memories: [SavedMemory], usedTokens: Int? = nil, maxTokens: Int? = nil) {
        self.memories = memories
        self.usedTokens = usedTokens
        self.maxTokens = maxTokens
    }

    public static func parse(_ data: Data) -> MemoriesSnapshot? {
        guard let object = JSONValue.object(data) else { return nil }
        let entries = object["memories"] as? [[String: Any]] ?? []
        let memories = entries.enumerated().compactMap { index, entry -> SavedMemory? in
            let raw = JSONValue.string(entry["content"]) ?? JSONValue.string(entry["text"]) ?? ""
            let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return SavedMemory(
                id: JSONValue.string(entry["id"]) ?? "memory-\(index)",
                content: content,
                updatedAt: FlexibleDate.parse(entry["updated_at"]) ?? FlexibleDate.parse(entry["created_at"])
            )
        }
        return MemoriesSnapshot(
            memories: memories,
            usedTokens: JSONValue.int(object["memory_num_tokens"]),
            maxTokens: JSONValue.int(object["memory_max_tokens"])
        )
    }
}
