import Foundation
import Observation
import OCTOCore
import UIKit

/// One event of the developer log.
struct DevLogEntry: Identifiable, Equatable, Sendable {
    enum Level: String, CaseIterable, Sendable {
        case debug
        case info
        case warning
        case error
    }

    let id = UUID()
    let date: Date
    let level: Level
    let category: String
    let message: String
}

/// Timestamped events of the app for developer mode, kept in memory only while it's on.
final class DevLog: @unchecked Sendable {
    static let shared = DevLog()

    private let lock = NSLock()
    private var sink: (@Sendable (DevLogEntry) -> Void)?

    func configure(sink: (@Sendable (DevLogEntry) -> Void)?) {
        lock.withLock { self.sink = sink }
    }

    static func log(_ category: String, _ message: @autoclosure () -> String, level: DevLogEntry.Level = .info) {
        guard let sink = shared.lock.withLock({ shared.sink }) else { return }
        sink(DevLogEntry(date: Date(), level: level, category: category, message: message()))
    }

    /// Everything known about an error, down to the underlying error, unlike the messages shown to users.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(String(reflecting: error)) [\(nsError.domain) \(nsError.code)]"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " ← [\(underlying.domain) \(underlying.code)] \(underlying.localizedDescription)"
        }
        return text
    }
}

/// What developer mode recorded: network exchanges and app events, newest requests first.
@MainActor
@Observable
final class DeveloperConsole {
    static let networkLimit = 250
    static let eventLimit = 1_000

    private(set) var network: [NetworkEntry] = []
    private(set) var events: [DevLogEntry] = []

    func record(_ entry: NetworkEntry) {
        if let index = network.firstIndex(where: { $0.id == entry.id }) {
            if network[index].revision < entry.revision {
                network[index] = entry
            }
            return
        }
        network.insert(entry, at: 0)
        if network.count > Self.networkLimit {
            network.removeLast(network.count - Self.networkLimit)
        }
    }

    func record(_ event: DevLogEntry) {
        var index = events.endIndex
        while index > events.startIndex, events[index - 1].date > event.date {
            index -= 1
        }
        events.insert(event, at: index)
        if events.count > Self.eventLimit {
            events.removeFirst(events.count - Self.eventLimit)
        }
    }

    func clearNetwork() {
        network.removeAll()
    }

    func clearEvents() {
        events.removeAll()
    }

    /// The event log as plain text, oldest first.
    func eventsText(limit: Int = 1_000) -> String {
        events.suffix(limit).map { event in
            "\(event.date.formatted(.iso8601.time(includingFractionalSeconds: true))) [\(event.level.rawValue)] \(event.category): \(event.message)"
        }.joined(separator: "\n")
    }
}

/// Developer mode, turned on by tapping the build number eight times in About.
/// Tools that change how the app behaves are reset when it's turned off or the app restarts.
@MainActor
@Observable
final class DeveloperSettings {
    enum PlanOverride: String, CaseIterable, Identifiable {
        case automatic
        case free
        case go
        case plus
        case pro

        var id: String { rawValue }
        var planType: String? { self == .automatic ? nil : rawValue }
    }

    let console: DeveloperConsole
    let performance: PerformanceMonitor
    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled {
                resetTools()
            }
            apply()
        }
    }

    var recordsNetwork: Bool {
        didSet {
            defaults.set(recordsNetwork, forKey: Keys.recordsNetwork)
            apply()
        }
    }

    var showsMessageDetails: Bool {
        didSet { defaults.set(showsMessageDetails, forKey: Keys.showsMessageDetails) }
    }

    var showsRawMarkdown: Bool {
        didSet { defaults.set(showsRawMarkdown, forKey: Keys.showsRawMarkdown) }
    }

    var disablesTextPacing: Bool {
        didSet { defaults.set(disablesTextPacing, forKey: Keys.disablesTextPacing) }
    }

    var showsPerformanceOverlay: Bool {
        didSet {
            defaults.set(showsPerformanceOverlay, forKey: Keys.showsPerformanceOverlay)
            apply()
        }
    }

    /// Not saved: a simulated failure never outlives the session that turned it on.
    var simulatedFailure: SimulatedFailure = .none {
        didSet { apply() }
    }

    var planOverride: PlanOverride = .automatic
    var forcesModelPicker = false

    var slowAnimations = false {
        didSet { applyAnimationSpeed() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        console = DeveloperConsole()
        performance = PerformanceMonitor()
        isEnabled = defaults.bool(forKey: Keys.enabled)
        recordsNetwork = defaults.object(forKey: Keys.recordsNetwork) as? Bool ?? true
        showsMessageDetails = defaults.bool(forKey: Keys.showsMessageDetails)
        showsRawMarkdown = defaults.bool(forKey: Keys.showsRawMarkdown)
        disablesTextPacing = defaults.bool(forKey: Keys.disablesTextPacing)
        showsPerformanceOverlay = defaults.bool(forKey: Keys.showsPerformanceOverlay)
        apply()
    }

    /// Hooks the network recorder, the event log and the overlay up to the current options.
    func apply() {
        let console = console
        let isActive = isEnabled
        NetworkRecorder.shared.configure(
            recording: isActive && recordsNetwork,
            failure: isActive ? simulatedFailure : .none,
            sink: { entry in Task { @MainActor in console.record(entry) } }
        )
        if isActive {
            DevLog.shared.configure { event in Task { @MainActor in console.record(event) } }
        } else {
            DevLog.shared.configure(sink: nil)
        }
        if isActive, showsPerformanceOverlay {
            performance.start()
        } else {
            performance.stop()
        }
    }

    /// Reapplies the animation speed, for windows created after it was changed.
    func applyAnimationSpeed() {
        let speed: Float = isEnabled && slowAnimations ? 0.25 : 1
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.layer.speed = speed
            }
        }
    }

    private func resetTools() {
        simulatedFailure = .none
        planOverride = .automatic
        forcesModelPicker = false
        slowAnimations = false
        showsMessageDetails = false
        showsRawMarkdown = false
        disablesTextPacing = false
        showsPerformanceOverlay = false
        console.clearNetwork()
        console.clearEvents()
    }

    private enum Keys {
        static let enabled = "developer.enabled"
        static let recordsNetwork = "developer.recordsNetwork"
        static let showsMessageDetails = "developer.showsMessageDetails"
        static let showsRawMarkdown = "developer.showsRawMarkdown"
        static let disablesTextPacing = "developer.disablesTextPacing"
        static let showsPerformanceOverlay = "developer.showsPerformanceOverlay"
    }
}

/// Details about the device and the build, for the developer tools and bug reports.
@MainActor
enum DeviceInfo {
    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "–"
    }

    static var freeDiskSpace: Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// Non-sensitive facts for bug reports: no account, no chats.
    static func diagnostics() -> [(label: String, value: String)] {
        [
            ("OCTO", "\(AppInfo.version) (\(AppInfo.build)) \(buildConfiguration)"),
            ("System", systemVersion),
            ("Device", modelIdentifier),
            ("Language", AppInfo.languageTag),
            ("Codex client", CodexBackend.clientVersion),
        ]
    }
}
