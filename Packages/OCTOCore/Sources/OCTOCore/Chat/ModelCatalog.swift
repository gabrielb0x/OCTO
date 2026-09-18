import Foundation

public struct ReasoningEffortOption: Codable, Hashable, Sendable, Identifiable {
    public var effort: String
    public var summary: String?

    public var id: String { effort }

    public init(effort: String, summary: String? = nil) {
        self.effort = effort
        self.summary = summary
    }
}

/// A faster way for a model to answer, which Codex calls a service tier: "Fast" is sent as
/// `priority`. It answers sooner and counts more against the plan's usage.
public struct ModelSpeedTier: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String?

    public init(id: String, name: String, summary: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

public struct ModelDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var summary: String?
    public var reasoningEfforts: [ReasoningEffortOption]
    public var defaultReasoningEffort: String?
    public var supportsReasoningSummaries: Bool
    public var supportsVerbosity: Bool
    public var acceptsImages: Bool
    public var supportsWebSearch: Bool
    public var contextWindow: Int?
    public var priority: Int
    /// The plans Codex offers the model to (`available_in_plans`); nil when its catalog doesn't say.
    public var availablePlans: [String]?
    /// The faster tiers the model can answer with (`service_tiers`).
    public var speedTiers: [ModelSpeedTier]

    public init(
        id: String,
        displayName: String,
        summary: String? = nil,
        reasoningEfforts: [ReasoningEffortOption] = [],
        defaultReasoningEffort: String? = nil,
        supportsReasoningSummaries: Bool = true,
        supportsVerbosity: Bool = false,
        acceptsImages: Bool = true,
        supportsWebSearch: Bool = true,
        contextWindow: Int? = nil,
        priority: Int = 1_000,
        availablePlans: [String]? = nil,
        speedTiers: [ModelSpeedTier] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.reasoningEfforts = reasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportsReasoningSummaries = supportsReasoningSummaries
        self.supportsVerbosity = supportsVerbosity
        self.acceptsImages = acceptsImages
        self.supportsWebSearch = supportsWebSearch
        self.contextWindow = contextWindow
        self.priority = priority
        self.availablePlans = availablePlans
        self.speedTiers = speedTiers
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, summary, reasoningEfforts, defaultReasoningEffort, supportsReasoningSummaries
        case supportsVerbosity, acceptsImages, supportsWebSearch, contextWindow, priority, availablePlans, speedTiers
    }

    // Lenient decoding keeps the models cached by an earlier version readable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        reasoningEfforts = try container.decodeIfPresent([ReasoningEffortOption].self, forKey: .reasoningEfforts) ?? []
        defaultReasoningEffort = try container.decodeIfPresent(String.self, forKey: .defaultReasoningEffort)
        supportsReasoningSummaries = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoningSummaries) ?? true
        supportsVerbosity = try container.decodeIfPresent(Bool.self, forKey: .supportsVerbosity) ?? false
        acceptsImages = try container.decodeIfPresent(Bool.self, forKey: .acceptsImages) ?? true
        supportsWebSearch = try container.decodeIfPresent(Bool.self, forKey: .supportsWebSearch) ?? true
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 1_000
        availablePlans = try container.decodeIfPresent([String].self, forKey: .availablePlans)
        speedTiers = try container.decodeIfPresent([ModelSpeedTier].self, forKey: .speedTiers) ?? []
    }

    public var supportsReasoning: Bool { !reasoningEfforts.isEmpty }

    /// Whether Codex offers the model to accounts on `plan`. A catalog that doesn't say, or a plan
    /// OCTO couldn't read, counts as offered: Codex still has the last word when a message is sent.
    public func isOffered(toPlan plan: String?) -> Bool {
        guard let availablePlans, !availablePlans.isEmpty,
              let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !plan.isEmpty
        else { return true }
        return availablePlans.contains { $0.lowercased() == plan }
    }

    /// The tier to ask for, when the model offers the one chosen.
    public func speedTier(_ id: String?) -> ModelSpeedTier? {
        guard let id else { return nil }
        return speedTiers.first { $0.id == id }
    }

    /// The effort to send: the preferred one when supported, else the model default.
    public func resolvedEffort(preferred: String?) -> String? {
        guard supportsReasoning else { return nil }
        if let preferred, reasoningEfforts.contains(where: { $0.effort == preferred }) {
            return preferred
        }
        if let defaultReasoningEffort, reasoningEfforts.contains(where: { $0.effort == defaultReasoningEffort }) {
            return defaultReasoningEffort
        }
        return reasoningEfforts.first { $0.effort == "medium" }?.effort ?? reasoningEfforts.first?.effort
    }

    /// Cheapest supported effort, used for background work such as titles.
    public var lightestEffort: String? {
        guard supportsReasoning else { return nil }
        let supported = Set(reasoningEfforts.map(\.effort))
        return ReasoningEffortScale.ordered.first { supported.contains($0) } ?? reasoningEfforts.first?.effort
    }
}

public enum ReasoningEffortScale {
    public static let ordered = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "persistent"]

    public static func rank(_ effort: String) -> Int {
        ordered.firstIndex(of: effort) ?? ordered.count
    }
}

public enum ModelCatalog {
    /// Parses `GET /backend-api/codex/models`, keeping models meant for pickers.
    public static func parseCodexModels(_ data: Data) -> [ModelDescriptor]? {
        guard let object = JSONValue.object(data),
              let models = object["models"] as? [[String: Any]]
        else { return nil }

        let descriptors = models.compactMap { model -> ModelDescriptor? in
            guard let slug = JSONValue.string(model["slug"]), !slug.isEmpty else { return nil }
            let visibility = JSONValue.string(model["visibility"])?.lowercased() ?? "list"
            guard visibility == "list" else { return nil }

            let efforts = (model["supported_reasoning_levels"] as? [[String: Any]] ?? []).compactMap { level -> ReasoningEffortOption? in
                guard let effort = JSONValue.string(level["effort"]), !effort.isEmpty else { return nil }
                return ReasoningEffortOption(effort: effort, summary: JSONValue.string(level["description"]))
            }
            let modalities = (model["input_modalities"] as? [Any])?.compactMap { JSONValue.string($0)?.lowercased() } ?? ["text", "image"]
            let plans = (model["available_in_plans"] as? [Any])?.compactMap { JSONValue.string($0)?.lowercased() }

            return ModelDescriptor(
                id: slug,
                displayName: JSONValue.string(model["display_name"]) ?? slug,
                summary: JSONValue.string(model["description"]),
                reasoningEfforts: efforts,
                defaultReasoningEffort: JSONValue.string(model["default_reasoning_level"]),
                supportsReasoningSummaries: JSONValue.bool(model["supports_reasoning_summary_parameter"]) ?? true,
                supportsVerbosity: JSONValue.bool(model["support_verbosity"]) ?? false,
                acceptsImages: modalities.contains("image"),
                supportsWebSearch: JSONValue.bool(model["supports_search_tool"]) ?? true,
                contextWindow: JSONValue.int(model["context_window"]),
                priority: JSONValue.int(model["priority"]) ?? 1_000,
                availablePlans: plans,
                speedTiers: speedTiers(of: model)
            )
        }
        return descriptors.sorted { ($0.priority, $0.displayName) < ($1.priority, $1.displayName) }
    }

    /// `service_tiers` of a catalog entry. Older catalogs only listed `additional_speed_tiers:
    /// ["fast"]`, which Codex sends as `priority`. "default" means no tier at all.
    static func speedTiers(of model: [String: Any]) -> [ModelSpeedTier] {
        let tiers = (model["service_tiers"] as? [[String: Any]] ?? []).compactMap { tier -> ModelSpeedTier? in
            guard let id = JSONValue.string(tier["id"])?.trimmingCharacters(in: .whitespaces), !id.isEmpty, id != "default" else { return nil }
            let name = JSONValue.string(tier["name"]).flatMap { $0.isEmpty ? nil : $0 } ?? id.capitalized
            return ModelSpeedTier(id: id, name: name, summary: JSONValue.string(tier["description"]))
        }
        if !tiers.isEmpty { return tiers }
        let legacy = (model["additional_speed_tiers"] as? [Any])?.compactMap { JSONValue.string($0)?.lowercased() } ?? []
        return legacy.contains("fast") ? [ModelSpeedTier(id: "priority", name: "Fast")] : []
    }

    /// Parses `GET /v1/models`, keeping text models usable with the Responses API.
    public static func parsePlatformModels(_ data: Data) -> [ModelDescriptor]? {
        guard let object = JSONValue.object(data),
              let list = object["data"] as? [[String: Any]]
        else { return nil }
        let ids = list.compactMap { JSONValue.string($0["id"]) }.filter(isPlatformChatModel)
        return ids.map(platformDescriptor(for:)).sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }
    }

    public static func isPlatformChatModel(_ id: String) -> Bool {
        let id = id.lowercased()
        let families = ["gpt-", "chatgpt-", "o1", "o3", "o4"]
        guard families.contains(where: { id.hasPrefix($0) }) else { return false }
        let excluded = ["audio", "realtime", "transcribe", "tts", "image", "embedding", "moderation", "search",
                        "instruct", "davinci", "babbage", "whisper", "dall-e", "computer-use", "deep-research", "gpt-3.5"]
        if excluded.contains(where: { id.contains($0) }) { return false }
        // Skip dated snapshots such as gpt-4o-2024-08-06; the aliases are enough.
        if id.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return false }
        return true
    }

    public static func platformDescriptor(for id: String) -> ModelDescriptor {
        let lower = id.lowercased()
        let isChatVariant = lower.contains("-chat")
        let isOSeries = lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4")
        let reasoning = !isChatVariant && (isOSeries || lower.hasPrefix("gpt-5") || lower.hasPrefix("gpt-6"))
        let efforts = reasoning ? ["low", "medium", "high"].map { ReasoningEffortOption(effort: $0) } : []
        let noImages = lower.hasPrefix("o1-mini") || lower.hasPrefix("o3-mini")
        let noSearch = lower.contains("nano") || lower.hasPrefix("o1") || lower.hasPrefix("o3-mini")

        return ModelDescriptor(
            id: id,
            displayName: platformDisplayName(for: id),
            reasoningEfforts: efforts,
            defaultReasoningEffort: reasoning ? "medium" : nil,
            supportsReasoningSummaries: reasoning,
            supportsVerbosity: reasoning && !isOSeries,
            acceptsImages: !noImages,
            supportsWebSearch: !noSearch,
            priority: platformPriority(for: lower)
        )
    }

    static func platformDisplayName(for id: String) -> String {
        var name = id
        if name.lowercased().hasPrefix("gpt-") {
            name = "GPT-" + name.dropFirst(4)
        } else if name.lowercased().hasPrefix("chatgpt-") {
            name = "ChatGPT-" + name.dropFirst(8)
        }
        for suffix in ["mini", "nano", "pro", "latest", "chat", "codex"] {
            name = name.replacingOccurrences(of: "-\(suffix)", with: " \(suffix)")
        }
        return name
    }

    /// Newer families first, then the base model before its smaller variants.
    static func platformPriority(for id: String) -> Int {
        var version = 0.0
        if id.hasPrefix("gpt-") {
            let digits = id.dropFirst(4).prefix { $0.isNumber || $0 == "." }
            version = Double(digits) ?? 4
            if id.hasPrefix("gpt-4o") { version = 4.2 }
        } else if id.hasPrefix("o") {
            version = (Double(String(id.dropFirst().prefix { $0.isNumber })) ?? 1) - 0.5
        } else {
            version = 4.1
        }
        var penalty = 0
        if id.contains("mini") { penalty += 20 }
        if id.contains("nano") { penalty += 30 }
        if id.contains("pro") { penalty += 10 }
        if id.contains("chat") || id.contains("codex") { penalty += 40 }
        return Int((20 - version) * 100) + penalty
    }

    /// Used when the ChatGPT model list cannot be fetched. Mirrors the catalog bundled with Codex
    /// 0.155.0 (`codex-rs/models-manager/models.json`), which offers these five to every plan,
    /// free included.
    public static let chatGPTFallback: [ModelDescriptor] = {
        let full = [
            ReasoningEffortOption(effort: "low", summary: "Fast responses with lighter reasoning"),
            ReasoningEffortOption(effort: "medium", summary: "Balances speed and reasoning depth for everyday tasks"),
            ReasoningEffortOption(effort: "high", summary: "Greater reasoning depth for complex problems"),
            ReasoningEffortOption(effort: "xhigh", summary: "Extra high reasoning depth for complex problems"),
            ReasoningEffortOption(effort: "max", summary: "Maximum reasoning depth for the hardest problems"),
            ReasoningEffortOption(effort: "ultra", summary: "Maximum reasoning with automatic task delegation"),
        ]
        let fast = ModelSpeedTier(id: "priority", name: "Fast", summary: "1.5x speed, increased usage")
        return [
            ModelDescriptor(
                id: "gpt-6-astra", displayName: "GPT-6-Astra", summary: "Our most capable model for complex, demanding work.",
                reasoningEfforts: full, defaultReasoningEffort: "low", supportsVerbosity: true, contextWindow: 272_000, priority: 1,
                speedTiers: [ModelSpeedTier(id: "priority", name: "Fast", summary: "2x speed, increased usage")]
            ),
            ModelDescriptor(
                id: "gpt-5.6-sol", displayName: "GPT-5.6-Sol", summary: "Latest frontier agentic coding model.",
                reasoningEfforts: full, defaultReasoningEffort: "low", supportsVerbosity: true, contextWindow: 272_000, priority: 6,
                speedTiers: [fast, ModelSpeedTier(id: "ultrafast", name: "Ultrafast", summary: "The fastest available responses for latency-sensitive work.")]
            ),
            ModelDescriptor(
                id: "gpt-5.6-terra", displayName: "GPT-5.6-Terra", summary: "Balanced agentic coding model for everyday work.",
                reasoningEfforts: full, defaultReasoningEffort: "medium", supportsVerbosity: true, contextWindow: 272_000, priority: 7,
                speedTiers: [fast]
            ),
            ModelDescriptor(
                id: "gpt-5.6-luna", displayName: "GPT-5.6-Luna", summary: "Fast and affordable agentic coding model.",
                reasoningEfforts: Array(full.dropLast()), defaultReasoningEffort: "medium", supportsVerbosity: true, contextWindow: 272_000, priority: 8,
                speedTiers: [fast]
            ),
            ModelDescriptor(
                id: "gpt-5.5", displayName: "GPT-5.5", summary: "Frontier model for complex coding, research, and real-world work.",
                reasoningEfforts: Array(full.prefix(4)), defaultReasoningEffort: "medium", supportsVerbosity: true, contextWindow: 272_000, priority: 12,
                speedTiers: [fast]
            ),
        ]
    }()

    public static let platformFallback: [ModelDescriptor] = ["gpt-5", "gpt-5-mini", "gpt-4.1"].map(platformDescriptor(for:))
}

/// Which models an account can really use. Codex's catalog says which plans a model is offered
/// to, but it's Codex that decides when a message is sent: a model it turns down leaves the
/// picker, and the question goes to another one.
public enum ModelAvailability {
    /// The models to offer an account on `plan`: those the catalog offers that plan, minus those
    /// Codex refused. Never empty — with nothing left, the whole catalog stays offered.
    public static func available(_ models: [ModelDescriptor], plan: String?, refused: Set<String> = []) -> [ModelDescriptor] {
        let offered = models.filter { $0.isOffered(toPlan: plan) && !refused.contains($0.id) }
        return offered.isEmpty ? models : offered
    }

    /// True when Codex turned a request down because the account can't use its model. Complaints
    /// about a parameter, a tool or the speed of the model aren't: those are fixed by changing the
    /// request, not the model.
    public static func isRefusal(status: Int, payload: APIErrorPayload, modelID: String) -> Bool {
        guard [400, 403, 404].contains(status) else { return false }
        let identifiers = [payload.code, payload.type].compactMap { $0?.lowercased() }
        let refusalCodes: Set<String> = ["model_not_found", "model_not_available", "model_not_supported", "unsupported_model"]
        if identifiers.contains(where: { refusalCodes.contains($0) }) { return true }
        guard let message = payload.message?.lowercased() else { return false }
        guard message.contains(modelID.lowercased()) || message.contains("model") else { return false }
        let aboutTheRequest = ["parameter", "value", "reasoning", "effort", "tool", "service_tier", "service tier", "verbosity", "summary", "instruction", "context", "token"]
        if aboutTheRequest.contains(where: { message.contains($0) }) { return false }
        let complaints = ["not supported", "unsupported", "not available", "unavailable", "does not exist", "doesn't exist", "not found",
                          "do not have access", "don't have access", "does not have access", "no access", "not allowed", "not enabled", "not included"]
        return complaints.contains { message.contains($0) }
    }
}
