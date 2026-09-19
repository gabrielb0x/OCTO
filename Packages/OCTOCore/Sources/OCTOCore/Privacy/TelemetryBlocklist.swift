import Foundation

/// The addresses ChatGPT's apps and the Codex CLI send telemetry to: event logs, feature-flag
/// exposures, error reports, latency reports and metrics. OCTO never sends any of it, and refuses
/// every request to them all the same, so nothing — a system framework, a future change — can
/// start sending it without anyone noticing.
///
/// Found in the requests chatgpt.com makes from a browser and in the Codex CLI's source
/// (`codex-rs/analytics`, `codex-rs/otel`, `codex-rs/feedback`).
public enum TelemetryBlocklist {
    public struct Rule: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            /// A host and all its subdomains.
            case host(String)
            /// Addresses of ChatGPT whose path starts with this.
            case chatGPTPath(String)
            /// Addresses whose path holds this, whatever the host.
            case pathPart(String)
        }

        public let kind: Kind
        /// Who receives what's sent there, for Privacy.
        public let service: String

        public init(_ kind: Kind, service: String) {
            self.kind = kind
            self.service = service
        }

        public var id: String { pattern }

        /// The rule as Privacy shows it: `api.oaistatsig.com`, `chatgpt.com/ces/`, `…/rgstr`.
        public var pattern: String {
            switch kind {
            case .host(let host): return host
            case .chatGPTPath(let path): return "chatgpt.com" + path
            case .pathPart(let part): return "…" + part
            }
        }

        func matches(host: String, path: String) -> Bool {
            switch kind {
            case .host(let blocked):
                return host == blocked || host.hasSuffix("." + blocked)
            case .chatGPTPath(let prefix):
                return TelemetryBlocklist.isChatGPT(host) && path.hasPrefix(prefix)
            case .pathPart(let part):
                return path.contains(part)
            }
        }
    }

    public static let rules: [Rule] = [
        // ChatGPT's own event service, which relays Segment and Statsig: `ces/v1/rgstr`,
        // `ces/statsc/flush`, `ces/v1/t`, `ces/v1/telemetry/intake` (logs for Datadog)…
        Rule(.chatGPTPath("/ces/"), service: "ChatGPT events"),
        // How fast each reply came, token by token.
        Rule(.chatGPTPath("/backend-api/lat/"), service: "ChatGPT latency reports"),
        Rule(.chatGPTPath("/backend-api/personality_settings_impression"), service: "ChatGPT impressions"),
        // What the Codex CLI reports about its sessions.
        Rule(.chatGPTPath("/backend-api/codex/analytics-events/"), service: "Codex analytics"),
        Rule(.chatGPTPath("/cdn-cgi/rum"), service: "Cloudflare Web Analytics"),
        // Statsig, the feature flags and event logs of ChatGPT and Codex, under all its names.
        Rule(.host("oaistatsig.com"), service: "Statsig"),
        Rule(.host("ab.chatgpt.com"), service: "Statsig"),
        Rule(.host("statsig.com"), service: "Statsig"),
        Rule(.host("statsigapi.net"), service: "Statsig"),
        Rule(.host("statsigcdn.com"), service: "Statsig"),
        Rule(.host("featuregates.org"), service: "Statsig"),
        Rule(.host("featureassets.org"), service: "Statsig"),
        Rule(.host("prodregistryv2.org"), service: "Statsig"),
        Rule(.pathPart("/rgstr"), service: "Statsig"),
        Rule(.pathPart("/sdk_exception"), service: "Statsig"),
        Rule(.pathPart("/statsc/"), service: "Statsig"),
        Rule(.pathPart("/otlp/"), service: "OpenTelemetry"),
        Rule(.host("browser-intake-datadoghq.com"), service: "Datadog"),
        Rule(.host("datadoghq.com"), service: "Datadog"),
        Rule(.host("datadoghq.eu"), service: "Datadog"),
        Rule(.host("sentry.io"), service: "Sentry"),
        Rule(.host("segment.io"), service: "Segment"),
        Rule(.host("segment.com"), service: "Segment"),
        Rule(.host("google-analytics.com"), service: "Google Analytics"),
        Rule(.host("googletagmanager.com"), service: "Google Analytics"),
        Rule(.host("doubleclick.net"), service: "Google Analytics"),
        Rule(.host("cloudflareinsights.com"), service: "Cloudflare Web Analytics"),
    ]

    /// The rule refusing this address, if one does.
    public static func rule(for url: URL) -> Rule? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let trimmedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        let path = url.path.lowercased()
        return rules.first { $0.matches(host: trimmedHost, path: path) }
    }

    public static func blocks(_ url: URL) -> Bool {
        rule(for: url) != nil
    }

    static func isChatGPT(_ host: String) -> Bool {
        host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "chat.openai.com"
    }
}
