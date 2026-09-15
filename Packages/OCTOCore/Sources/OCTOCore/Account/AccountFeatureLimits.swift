import Foundation

/// One usage limit of the ChatGPT account, as the website reads it from `POST /conversation/init`.
/// These features (Deep Research, image generation, file uploads, extended thinking…) run on
/// ChatGPT's own servers; OCTO only shows how much is left, exactly like the site.
public struct FeatureLimit: Codable, Equatable, Sendable, Identifiable {
    /// Raw feature key such as "deep_research", "image_gen" or "file_upload".
    public var feature: String
    /// Uses left in the current window, when the account reports one.
    public var remaining: Int?
    /// When the window resets.
    public var resetsAt: Date?
    /// True once the feature is blocked until it resets.
    public var isBlocked: Bool
    /// The message ChatGPT shows for a blocked feature, when there is one.
    public var message: String?

    public var id: String { feature }

    public init(feature: String, remaining: Int? = nil, resetsAt: Date? = nil, isBlocked: Bool = false, message: String? = nil) {
        self.feature = feature
        self.remaining = remaining
        self.resetsAt = resetsAt
        self.isBlocked = isBlocked
        self.message = message
    }
}

/// The account's live limits, from `POST /backend-api/conversation/init`. This is the same call the
/// website makes when it opens a new chat, so OCTO reflects the real ChatGPT account, not Codex.
public struct FeatureLimits: Codable, Equatable, Sendable {
    /// The model ChatGPT would pick by default, e.g. "auto".
    public var defaultModelSlug: String?
    /// Per-feature limits, in the order ChatGPT lists them.
    public var features: [FeatureLimit]
    /// Largest attachment the account may upload, in megabytes.
    public var maxAttachmentMB: Int?

    public init(defaultModelSlug: String? = nil, features: [FeatureLimit] = [], maxAttachmentMB: Int? = nil) {
        self.defaultModelSlug = defaultModelSlug
        self.features = features
        self.maxAttachmentMB = maxAttachmentMB
    }

    public var isEmpty: Bool { features.isEmpty }

    public static func parse(_ data: Data) -> FeatureLimits? {
        guard let object = JSONValue.object(data) else { return nil }
        // Only the init metadata carries these; guard against unrelated payloads.
        guard JSONValue.string(object["type"]) == "conversation_detail_metadata"
            || object["limits_progress"] != nil
            || object["default_model_slug"] != nil
        else { return nil }

        var byFeature: [String: FeatureLimit] = [:]
        var order: [String] = []
        func upsert(_ feature: String, _ transform: (inout FeatureLimit) -> Void) {
            if byFeature[feature] == nil {
                byFeature[feature] = FeatureLimit(feature: feature)
                order.append(feature)
            }
            transform(&byFeature[feature]!)
        }

        for entry in object["limits_progress"] as? [[String: Any]] ?? [] {
            guard let feature = JSONValue.string(entry["feature_name"]), !feature.isEmpty else { continue }
            let remaining = JSONValue.int(entry["remaining"])
            upsert(feature) { limit in
                limit.remaining = remaining
                limit.resetsAt = FlexibleDate.parse(entry["reset_after"])
                limit.isBlocked = remaining == 0
            }
        }
        // Blocked features add the reason and reset time when a limit is already hit.
        for entry in object["blocked_features"] as? [[String: Any]] ?? [] {
            guard let feature = JSONValue.string(entry["name"]), !feature.isEmpty else { continue }
            upsert(feature) { limit in
                limit.isBlocked = true
                if limit.remaining == nil { limit.remaining = 0 }
                limit.resetsAt = limit.resetsAt ?? FlexibleDate.parse(entry["resets_after"])
                limit.message = JSONValue.string(entry["description"]) ?? limit.message
            }
        }

        let attachment = object["file_attachment_limits"] as? [String: Any]
        return FeatureLimits(
            defaultModelSlug: JSONValue.string(object["default_model_slug"]),
            features: order.compactMap { byFeature[$0] },
            maxAttachmentMB: JSONValue.int(attachment?["max_size_mb"])
        )
    }
}
