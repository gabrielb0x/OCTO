import Foundation
import Observation
import OCTOCore

enum UpdateError: LocalizedError {
    case rateLimited
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return String(localized: "GitHub is limiting requests right now. Try again later.")
        case .http(let status):
            return String(localized: "GitHub returned an error (HTTP \(status)).")
        case .invalidResponse:
            return String(localized: "GitHub returned an unexpected response.")
        }
    }
}

/// Looks for a newer OCTO on GitHub Releases, where every version is published with its IPA. The
/// request goes to api.github.com without cookies, account or identifier, at most every few hours
/// while automatic checks are on.
@MainActor
@Observable
final class UpdateChecker {
    static let repository = "gabrielb0x/OCTO"

    private(set) var latest: AppRelease?
    private(set) var isChecking = false
    private(set) var lastCheck: Date?
    private(set) var errorMessage: String?

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isDemo: Bool

    init(isDemo: Bool, defaults: UserDefaults = .standard) {
        self.isDemo = isDemo
        self.defaults = defaults
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        guard !isDemo else { return }
        lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date
        latest = defaults.data(forKey: Keys.latest).flatMap { try? JSONDecoder().decode(AppRelease.self, from: $0) }
    }

    /// The newer version to install, if there is one.
    var available: AppRelease? {
        guard let latest, latest.isNewer(than: AppInfo.version) else { return nil }
        return latest
    }

    func checkIfDue() async {
        guard UpdateSchedule.isDue(lastCheck: lastCheck, now: Date()) else { return }
        await check()
    }

    func check() async {
        guard !isDemo, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: AppRelease.latestURL(repository: Self.repository))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub wants a user agent; this one says nothing about the device.
        request.setValue("OCTO", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.recordedData(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastCheck = Date()
            defaults.set(lastCheck, forKey: Keys.lastCheck)
            switch status {
            case 200:
                guard let release = AppRelease.parse(data) else { throw UpdateError.invalidResponse }
                latest = release
                defaults.set(try? JSONEncoder().encode(release), forKey: Keys.latest)
                DevLog.log("updates", "Latest release \(release.version), installed \(AppInfo.version)")
            case 404:
                // Nothing published yet.
                latest = nil
                defaults.removeObject(forKey: Keys.latest)
            case 403, 429:
                throw UpdateError.rateLimited
            default:
                throw UpdateError.http(status)
            }
            errorMessage = nil
        } catch let error where error.isCancellation {
            return
        } catch {
            errorMessage = ChatSession.describe(error)
            DevLog.log("updates", "Check failed: \(DevLog.describe(error))", level: .warning)
        }
    }

    func wasAnnounced(_ release: AppRelease) -> Bool {
        defaults.string(forKey: Keys.announcedVersion) == release.version
    }

    func markAnnounced(_ release: AppRelease) {
        defaults.set(release.version, forKey: Keys.announcedVersion)
    }

    #if OCTO_DEMO
    /// Screenshot builds show an update without touching the network.
    func useDemo(_ release: AppRelease) {
        latest = release
        lastCheck = Date()
    }
    #endif

    private enum Keys {
        static let lastCheck = "app.update.lastCheck"
        static let latest = "app.update.latest"
        static let announcedVersion = "app.update.announcedVersion"
    }
}
