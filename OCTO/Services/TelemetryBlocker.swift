import Foundation
import OCTOCore

/// Refuses every request to a telemetry address (`TelemetryBlocklist`) before it leaves the
/// device: ChatGPT's event service, Statsig, Datadog, Sentry… OCTO never makes such a request
/// itself — this makes sure nothing else in the app can, in any of its network sessions.
final class TelemetryBlocker: URLProtocol {
    /// Covers the shared session, which system frameworks use.
    static func install() {
        URLProtocol.registerClass(TelemetryBlocker.self)
    }

    /// Covers a session OCTO opens, which doesn't see the classes registered for the shared one.
    static func protect(_ configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [TelemetryBlocker.self] + (configuration.protocolClasses ?? [])
    }

    /// What a blocked request fails with. A cancellation, so nothing ever shows it as an error.
    static var error: URLError {
        URLError(.cancelled, userInfo: [NSLocalizedDescriptionKey: "Blocked by OCTO: telemetry"])
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return TelemetryBlocklist.blocks(url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let url = request.url {
            NetworkActivity.shared.recordBlocked(url)
            DevLog.log("privacy", "Blocked a telemetry request to \(url.host ?? "?")\(url.path)", level: .warning)
        }
        client?.urlProtocol(self, didFailWithError: Self.error)
    }

    override func stopLoading() {}
}
