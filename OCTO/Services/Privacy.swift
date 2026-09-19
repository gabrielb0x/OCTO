import OCTOCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Copies text the way the privacy settings ask: only on this device, not to your other Apple
/// devices through Universal Clipboard, for a limited time when chosen, and without link trackers.
@MainActor
enum Clipboard {
    static func copy(_ text: String, settings: AppSettings, cleansLinks: Bool = true) {
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if settings.copiesOnlyOnThisDevice {
            options[.localOnly] = true
        }
        if settings.clipboardExpiry != .never {
            options[.expirationDate] = Date().addingTimeInterval(TimeInterval(settings.clipboardExpiry.rawValue))
        }
        let value = cleansLinks ? settings.shareableText(text) : text
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: value]], options: options)
    }
}

extension AppSettings {
    /// Text leaving OCTO, copied or shared, without link trackers when the privacy settings ask for it.
    func shareableText(_ text: String) -> String {
        removesLinkTrackers ? LinkCleaner.cleanLinks(in: text) : text
    }
}

/// Keeps third-party keyboards out of OCTO when the privacy settings ask for it, since such a
/// keyboard can send what you type to its developer. iOS asks the first time a keyboard is needed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard || !AppSettings.blocksThirdPartyKeyboards()
    }
}

/// The servers OCTO contacted since it opened, and the telemetry it refused to send, for the
/// privacy report. Counted in memory only.
final class NetworkActivity: @unchecked Sendable {
    struct Host: Identifiable, Equatable {
        let name: String
        let requests: Int

        var id: String { name }
    }

    static let shared = NetworkActivity()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var blockedCounts: [String: Int] = [:]

    func record(_ url: URL?) {
        // A telemetry request never leaves: it's counted as blocked, not as contacted.
        guard let url, !TelemetryBlocklist.blocks(url), let host = url.host?.lowercased(), !host.isEmpty else { return }
        lock.withLock {
            counts[host, default: 0] += 1
        }
    }

    func recordBlocked(_ url: URL) {
        let address = (url.host?.lowercased() ?? "") + url.path
        lock.withLock {
            blockedCounts[address, default: 0] += 1
        }
    }

    func hosts() -> [Host] {
        Self.sorted(lock.withLock { counts })
    }

    /// The telemetry addresses something tried to reach, with how many times.
    func blocked() -> [Host] {
        Self.sorted(lock.withLock { blockedCounts })
    }

    private static func sorted(_ counts: [String: Int]) -> [Host] {
        counts
            .map { Host(name: $0.key, requests: $0.value) }
            .sorted { $0.requests == $1.requests ? $0.name < $1.name : $0.requests > $1.requests }
    }
}
