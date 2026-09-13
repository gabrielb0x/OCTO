import Foundation

/// A UI-relevant change decoded from one Responses API stream event.
public enum ResponseStreamUpdate: Equatable, Sendable {
    case created(responseID: String?)
    case reasoningStarted
    case reasoningDelta(String)
    case reasoningSectionBreak
    case reasoningFinished
    case textDelta(String)
    case webSearchStarted
    case webSearchFinished(query: String?)
    case citations([Citation])
    case completed(TokenUsage?)
    case incomplete(reason: String?)
    case failed(ResponseStreamFailure)
}

public struct ResponseStreamFailure: Error, Equatable, Sendable {
    public var code: String?
    public var message: String

    public init(code: String?, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ResponseStreamDecoder {
    public static func updates(fromEventData data: String) -> [ResponseStreamUpdate] {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[DONE]",
              let object = JSONValue.object(Data(trimmed.utf8)),
              let type = JSONValue.string(object["type"])
        else { return [] }

        switch type {
        case "response.created":
            let response = object["response"] as? [String: Any]
            return [.created(responseID: JSONValue.string(response?["id"]))]

        case "response.output_item.added":
            let item = object["item"] as? [String: Any]
            switch JSONValue.string(item?["type"]) {
            case "reasoning": return [.reasoningStarted]
            case "web_search_call": return [.webSearchStarted]
            default: return []
            }

        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            guard let delta = JSONValue.string(object["delta"]), !delta.isEmpty else { return [] }
            return [.reasoningDelta(delta)]

        case "response.reasoning_summary_part.added":
            return [.reasoningSectionBreak]

        case "response.output_text.delta", "response.refusal.delta":
            guard let delta = JSONValue.string(object["delta"]), !delta.isEmpty else { return [] }
            return [.textDelta(delta)]

        case "response.output_text.annotation.added":
            guard let annotation = object["annotation"] as? [String: Any],
                  let citation = citation(from: annotation)
            else { return [] }
            return [.citations([citation])]

        case "response.output_item.done":
            guard let item = object["item"] as? [String: Any] else { return [] }
            switch JSONValue.string(item["type"]) {
            case "reasoning":
                return [.reasoningFinished]
            case "web_search_call":
                let action = item["action"] as? [String: Any]
                let query = JSONValue.string(action?["query"])
                    ?? (action?["queries"] as? [Any])?.compactMap { JSONValue.string($0) }.first
                return [.webSearchFinished(query: query)]
            case "message":
                let parts = item["content"] as? [[String: Any]] ?? []
                let citations = parts.flatMap { part in
                    (part["annotations"] as? [[String: Any]] ?? []).compactMap { citation(from: $0) }
                }
                return citations.isEmpty ? [] : [.citations(citations)]
            default:
                return []
            }

        case "response.completed", "response.done":
            let response = object["response"] as? [String: Any]
            return [.completed(usage(from: response?["usage"] as? [String: Any]))]

        case "response.incomplete":
            let response = object["response"] as? [String: Any]
            let details = response?["incomplete_details"] as? [String: Any]
            return [.incomplete(reason: JSONValue.string(details?["reason"]))]

        case "response.failed":
            let response = object["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            return [.failed(ResponseStreamFailure(
                code: JSONValue.string(error?["code"]) ?? JSONValue.string(error?["type"]),
                message: JSONValue.string(error?["message"]) ?? "The response failed."
            ))]

        case "error":
            let nested = object["error"] as? [String: Any]
            let code = JSONValue.string(object["code"]) ?? JSONValue.string(nested?["code"]) ?? JSONValue.string(nested?["type"])
            let message = JSONValue.string(object["message"]) ?? JSONValue.string(nested?["message"]) ?? "The server reported an error."
            return [.failed(ResponseStreamFailure(code: code, message: message))]

        default:
            return []
        }
    }

    static func citation(from annotation: [String: Any]) -> Citation? {
        guard JSONValue.string(annotation["type"]) == "url_citation",
              let url = JSONValue.string(annotation["url"])
        else { return nil }
        return Citation(url: url, title: JSONValue.string(annotation["title"]))
    }

    public static func usage(from object: [String: Any]?) -> TokenUsage? {
        guard let object else { return nil }
        let inputDetails = object["input_tokens_details"] as? [String: Any]
        let outputDetails = object["output_tokens_details"] as? [String: Any]
        return TokenUsage(
            inputTokens: JSONValue.int(object["input_tokens"]) ?? 0,
            cachedInputTokens: JSONValue.int(inputDetails?["cached_tokens"]) ?? 0,
            outputTokens: JSONValue.int(object["output_tokens"]) ?? 0,
            reasoningTokens: JSONValue.int(outputDetails?["reasoning_tokens"]) ?? 0
        )
    }
}

/// Error body of a non-2xx response from either backend.
public struct APIErrorPayload: Equatable, Sendable {
    public var message: String?
    public var type: String?
    public var code: String?
    public var planType: String?
    public var resetsAt: Date?

    public init(message: String? = nil, type: String? = nil, code: String? = nil, planType: String? = nil, resetsAt: Date? = nil) {
        self.message = message
        self.type = type
        self.code = code
        self.planType = planType
        self.resetsAt = resetsAt
    }

    public static func parse(_ data: Data, now: Date = Date()) -> APIErrorPayload {
        guard let object = JSONValue.object(data) else {
            let text = String(decoding: data.prefix(2_000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("<") {
                return APIErrorPayload() // HTML error pages carry nothing useful
            }
            return APIErrorPayload(message: String(text.prefix(400)))
        }
        if let error = object["error"] as? [String: Any] {
            var resetsAt = JSONValue.double(error["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            if resetsAt == nil, let seconds = JSONValue.double(error["resets_in_seconds"]) {
                resetsAt = now.addingTimeInterval(seconds)
            }
            return APIErrorPayload(
                message: JSONValue.string(error["message"]),
                type: JSONValue.string(error["type"]),
                code: JSONValue.string(error["code"]),
                planType: JSONValue.string(error["plan_type"]),
                resetsAt: resetsAt
            )
        }
        if let detail = JSONValue.string(object["detail"]) {
            return APIErrorPayload(message: detail)
        }
        if let detail = object["detail"] as? [String: Any] {
            return APIErrorPayload(message: JSONValue.string(detail["message"]), code: JSONValue.string(detail["code"]))
        }
        if let error = JSONValue.string(object["error"]) {
            return APIErrorPayload(message: JSONValue.string(object["message"]) ?? error, code: error)
        }
        return APIErrorPayload(message: JSONValue.string(object["message"]))
    }
}

/// What went wrong with a chat request, independent of wording.
public enum ChatFailureKind: Equatable, Sendable {
    case unauthorized
    case usageLimitReached(resetsAt: Date?)
    case usageNotIncluded
    case insufficientQuota
    case rateLimited
    case contextTooLong
    case blocked(String?)
    case invalidRequest(String?)
    case server(String?)
    case other(String?)

    public static func classify(status: Int, payload: APIErrorPayload) -> ChatFailureKind {
        let identifiers = [payload.type, payload.code].compactMap { $0?.lowercased() }
        let message = payload.message
        if identifiers.contains("usage_limit_reached") { return .usageLimitReached(resetsAt: payload.resetsAt) }
        if identifiers.contains("usage_not_included") { return .usageNotIncluded }
        if identifiers.contains("insufficient_quota") { return .insufficientQuota }
        if identifiers.contains("context_length_exceeded") || isContextMessage(message) { return .contextTooLong }

        switch status {
        case 401: return .unauthorized
        case 403: return .blocked(message)
        case 429: return .rateLimited
        case 400, 404, 409, 413, 422: return .invalidRequest(message)
        case 500...599: return .server(message)
        default: return .other(message)
        }
    }

    public static func classify(_ failure: ResponseStreamFailure) -> ChatFailureKind {
        switch failure.code?.lowercased() {
        case "usage_limit_reached"?: return .usageLimitReached(resetsAt: nil)
        case "usage_not_included"?: return .usageNotIncluded
        case "insufficient_quota"?: return .insufficientQuota
        case "rate_limit_exceeded"?: return .rateLimited
        case "context_length_exceeded"?: return .contextTooLong
        case "server_is_overloaded"?, "slow_down"?, "server_error"?: return .server(failure.message)
        case "invalid_prompt"?, "invalid_request_error"?: return .invalidRequest(failure.message)
        default:
            return isContextMessage(failure.message) ? .contextTooLong : .other(failure.message)
        }
    }

    private static func isContextMessage(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return message.contains("context window") || message.contains("maximum context length") || message.contains("context_length_exceeded")
    }
}

/// ChatGPT plan usage windows from `GET /backend-api/wham/usage`.
public struct UsageSnapshot: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var usedPercent: Double
        public var windowSeconds: Int?
        public var resetsAt: Date?
    }

    public var planType: String?
    public var limitReached: Bool
    public var primary: Window?
    public var secondary: Window?
    public var hasCredits: Bool?
    public var unlimitedCredits: Bool?
    public var creditBalance: String?

    public static func parse(_ data: Data, now: Date = Date()) -> UsageSnapshot? {
        guard let object = JSONValue.object(data) else { return nil }
        let rateLimit = object["rate_limit"] as? [String: Any]
        let credits = object["credits"] as? [String: Any]

        func window(_ value: Any?) -> Window? {
            guard let window = value as? [String: Any],
                  let used = JSONValue.double(window["used_percent"])
            else { return nil }
            var resetsAt = JSONValue.double(window["reset_at"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            if resetsAt == nil, let after = JSONValue.double(window["reset_after_seconds"]) {
                resetsAt = now.addingTimeInterval(after)
            }
            return Window(usedPercent: min(max(used, 0), 100), windowSeconds: JSONValue.int(window["limit_window_seconds"]), resetsAt: resetsAt)
        }

        return UsageSnapshot(
            planType: JSONValue.string(object["plan_type"]),
            limitReached: JSONValue.bool(rateLimit?["limit_reached"]) ?? false,
            primary: window(rateLimit?["primary_window"]),
            secondary: window(rateLimit?["secondary_window"]),
            hasCredits: JSONValue.bool(credits?["has_credits"]),
            unlimitedCredits: JSONValue.bool(credits?["unlimited"]),
            creditBalance: JSONValue.string(credits?["balance"])
        )
    }
}
