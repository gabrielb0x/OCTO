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
        priority: Int = 1_000
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
    }

    public var supportsReasoning: Bool { !reasoningEfforts.isEmpty }

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

            return ModelDescriptor(
                id: slug,
                displayName: JSONValue.string(model["display_name"]) ?? slug,
                summary: JSONValue.string(model["description"]),
                reasoningEfforts: efforts,
                defaultReasoningEffort: JSONValue.string(model["default_reasoning_level"]),
                supportsReasoningSummaries: JSONValue.bool(model["supports_reasoning_summary_parameter"]) ?? true,
                supportsVerbosity: JSONValue.bool(model["support_verbosity"]) ?? false,
                acceptsImages: modalities.contains("image"),
                supportsWebSearch: true,
                contextWindow: JSONValue.int(model["context_window"]),
                priority: JSONValue.int(model["priority"]) ?? 1_000
            )
        }
        return descriptors.sorted { ($0.priority, $0.displayName) < ($1.priority, $1.displayName) }
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

    /// Used when the ChatGPT model list cannot be fetched (mirrors Codex's bundled catalog).
    public static let chatGPTFallback: [ModelDescriptor] = {
        let full = ["low", "medium", "high", "xhigh", "max", "ultra"].map { ReasoningEffortOption(effort: $0) }
        return [
            ModelDescriptor(id: "gpt-6-astra", displayName: "GPT-6-Astra", reasoningEfforts: full, defaultReasoningEffort: "low", supportsVerbosity: true, contextWindow: 272_000, priority: 1),
            ModelDescriptor(id: "gpt-5.6-sol", displayName: "GPT-5.6-Sol", reasoningEfforts: full, defaultReasoningEffort: "low", supportsVerbosity: true, contextWindow: 272_000, priority: 6),
            ModelDescriptor(id: "gpt-5.6-terra", displayName: "GPT-5.6-Terra", reasoningEfforts: full, defaultReasoningEffort: "medium", supportsVerbosity: true, contextWindow: 272_000, priority: 7),
            ModelDescriptor(id: "gpt-5.6-luna", displayName: "GPT-5.6-Luna", reasoningEfforts: Array(full.dropLast()), defaultReasoningEffort: "medium", supportsVerbosity: true, contextWindow: 272_000, priority: 8),
            ModelDescriptor(id: "gpt-5.5", displayName: "GPT-5.5", reasoningEfforts: Array(full.prefix(4)), defaultReasoningEffort: "medium", supportsVerbosity: true, contextWindow: 272_000, priority: 12),
        ]
    }()

    public static let platformFallback: [ModelDescriptor] = ["gpt-5", "gpt-5-mini", "gpt-4.1"].map(platformDescriptor(for:))
}
