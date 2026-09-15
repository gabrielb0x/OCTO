import Foundation
import Observation
import OCTOCore
import UIKit

/// What OCTO keeps about the ChatGPT account, saved so it shows up right away and offline.
struct AccountSnapshot: Codable {
    var profile: AccountProfile?
    var settings: AccountSettings?
    var instructions: CustomInstructions?
    var personalities: [PersonalityOption]?
    var traits: [PersonalityTrait]?
    var memories: MemoriesSnapshot?
    /// Whether the account's policy lets its data be used for training at all.
    var dataUsagePermitted: Bool?
    var avatarURL: URL?
    var subscription: AccountSubscription?
    var featureLimits: FeatureLimits?
    var ageStatus: AgeStatus?
}

/// The account snapshot and profile picture, in Application Support.
final class AccountCache: @unchecked Sendable {
    let directory: URL

    init(folderName: String = "OCTO") {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        directory = base
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("Account", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var snapshotURL: URL { directory.appendingPathComponent("account.json") }
    private var avatarURL: URL { directory.appendingPathComponent("avatar") }

    func loadSnapshot() -> AccountSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(AccountSnapshot.self, from: data)
    }

    func save(_ snapshot: AccountSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func loadAvatar() -> Data? {
        try? Data(contentsOf: avatarURL)
    }

    func saveAvatar(_ data: Data?) {
        if let data {
            try? data.write(to: avatarURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } else {
            try? FileManager.default.removeItem(at: avatarURL)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: snapshotURL)
        try? FileManager.default.removeItem(at: avatarURL)
    }
}

/// The signed-in ChatGPT account: profile and picture, subscription, custom instructions,
/// personality, memory, data settings and age status, as shown in Settings and sent along with messages.
@MainActor
@Observable
final class AccountStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var profile: AccountProfile?
    private(set) var avatar: UIImage?
    private(set) var settings: AccountSettings?
    private(set) var subscription: AccountSubscription?
    private(set) var instructions: CustomInstructions?
    private(set) var personalities: [PersonalityOption] = []
    private(set) var traits: [PersonalityTrait] = []
    private(set) var memories: MemoriesSnapshot?
    private(set) var dataUsagePermitted: Bool?
    private(set) var ageStatus: AgeStatus?
    /// Live usage limits of the ChatGPT account (Deep Research, image generation, file uploads…).
    private(set) var featureLimits: FeatureLimits?
    /// Settings being saved to the account right now.
    private(set) var savingSettings: Set<AccountSettingFeature> = []
    private(set) var state: LoadState = .idle
    private(set) var lastRefresh: Date?

    @ObservationIgnored let cache: AccountCache
    @ObservationIgnored private let service: AccountService?
    @ObservationIgnored private var avatarURL: URL?
    /// Bumped on sign-out so late responses don't bring the old account back.
    @ObservationIgnored private var generation = 0

    init(service: AccountService?, cache: AccountCache) {
        self.service = service
        self.cache = cache
        if let snapshot = cache.loadSnapshot() {
            apply(snapshot)
            state = .loaded
        }
        avatar = cache.loadAvatar().flatMap { UIImage(data: $0) }
    }

    /// Custom instructions, personality and saved memories, added to every request.
    var personalContext: PersonalContext {
        var context = PersonalContext()
        if let instructions, instructions.isEnabled {
            context.nickname = instructions.nickname
            context.occupation = instructions.occupation
            context.aboutUser = instructions.aboutUser
            context.responseStyle = instructions.responseStyle
            context.personality = instructions.personality
            context.traits = instructions.traits
            if let option = personalities.first(where: { $0.key == instructions.personality }) {
                context.personalityDescription = [option.label, option.summary].compactMap { $0 }.joined(separator: ": ")
            }
        }
        if settings?.referencesSavedMemories != false {
            context.memories = memories?.memories.map(\.content) ?? []
        }
        return context
    }

    /// Downloads the account data again, unless it was refreshed less than `interval` seconds ago.
    func refresh(ifOlderThan interval: TimeInterval = 0) async {
        guard let service, state != .loading else { return }
        if interval > 0, let lastRefresh, Date().timeIntervalSince(lastRefresh) < interval { return }
        lastRefresh = Date()
        let generation = self.generation
        state = .loading
        DevLog.log("account", "Refreshing the account")

        async let profileResult = capture { try await service.profile() }
        async let settingsResult = capture { try await service.settings() }
        async let subscriptionResult = capture { try await service.subscription() }
        async let instructionsResult = capture { try await service.customInstructions() }
        async let personalitiesResult = capture { try await service.personalityTypes() }
        async let traitsResult = capture { try await service.personalityTraits() }
        async let memoriesResult = capture { try await service.memories() }
        async let dataUsageResult = capture { try await service.dataUsagePolicy() }
        async let featureLimitsResult = capture { try await service.featureLimits() }
        async let ageStatusResult = capture { try await service.ageStatus() }

        let profileOutcome = await profileResult
        let settingsOutcome = await settingsResult
        let subscriptionOutcome = await subscriptionResult
        let instructionsOutcome = await instructionsResult
        let personalitiesOutcome = await personalitiesResult
        let traitsOutcome = await traitsResult
        let memoriesOutcome = await memoriesResult
        let dataUsageOutcome = await dataUsageResult
        let featureLimitsOutcome = await featureLimitsResult
        let ageStatusOutcome = await ageStatusResult
        guard generation == self.generation else { return }

        if case .success(let value) = profileOutcome { profile = value }
        // A setting being saved keeps the value shown until the account confirms it.
        if case .success(let value) = settingsOutcome, savingSettings.isEmpty { settings = value }
        if case .success(let value) = subscriptionOutcome { subscription = value }
        if case .success(let value) = instructionsOutcome { instructions = value }
        if case .success(let value) = personalitiesOutcome { personalities = value }
        if case .success(let value) = traitsOutcome { traits = value }
        if case .success(let value) = memoriesOutcome { memories = value }
        if case .success(let value) = dataUsageOutcome { dataUsagePermitted = value }
        if case .success(let value) = featureLimitsOutcome { featureLimits = value }
        if case .success(let value) = ageStatusOutcome { ageStatus = value }

        let failures: [(String, Error?)] = [
            ("profile", profileOutcome.failure),
            ("settings", settingsOutcome.failure),
            ("subscription", subscriptionOutcome.failure),
            ("instructions", instructionsOutcome.failure),
            ("personalities", personalitiesOutcome.failure),
            ("traits", traitsOutcome.failure),
            ("memories", memoriesOutcome.failure),
            ("dataUsage", dataUsageOutcome.failure),
            ("featureLimits", featureLimitsOutcome.failure),
            ("ageStatus", ageStatusOutcome.failure),
        ]
        for case let (name, error?) in failures {
            DevLog.log("account", "\(name) failed: \(DevLog.describe(error))", level: error.isCancellation ? .debug : .warning)
        }

        if let error = profileOutcome.failure ?? instructionsOutcome.failure, !error.isCancellation {
            state = .failed(ChatSession.describe(error))
        } else {
            state = .loaded
        }
        saveSnapshot()
        await updateAvatar()
    }

    func saveInstructions(_ draft: CustomInstructions) async throws {
        guard let service else {
            instructions = draft
            return
        }
        let saved = try await service.saveCustomInstructions(draft)
        instructions = saved
        saveSnapshot()
    }

    /// Changes a setting of the account like ChatGPT's own settings, then reads the settings back
    /// so the switch shows what the account really kept.
    func setSetting(_ feature: AccountSettingFeature, to value: Bool) async throws {
        guard let service else {
            var updated = settings ?? AccountSettings()
            updated[feature] = value
            settings = updated
            return
        }
        guard !savingSettings.contains(feature) else { return }
        let generation = self.generation
        let previous = settings?[feature]
        var updated = settings ?? AccountSettings()
        updated[feature] = value
        settings = updated
        savingSettings.insert(feature)
        defer { savingSettings.remove(feature) }
        DevLog.log("account", "Setting \(feature.rawValue) to \(value)")

        do {
            try await service.updateSetting(feature, value: value)
        } catch {
            if generation == self.generation {
                settings?[feature] = previous
            }
            throw error
        }
        guard let saved = try? await service.settings(), generation == self.generation else { return }
        settings = saved
        saveSnapshot()
        if saved[feature] != value {
            DevLog.log("account", "\(feature.rawValue) wasn't kept by the account", level: .warning)
            throw AccountAPIError.settingNotSaved
        }
    }

    /// Forgets the account on sign-out.
    func clear() {
        generation += 1
        profile = nil
        avatar = nil
        settings = nil
        subscription = nil
        instructions = nil
        personalities = []
        traits = []
        memories = nil
        dataUsagePermitted = nil
        ageStatus = nil
        featureLimits = nil
        savingSettings = []
        avatarURL = nil
        lastRefresh = nil
        state = .idle
        cache.clear()
    }

    #if OCTO_DEMO
    func useDemo(_ snapshot: AccountSnapshot) {
        apply(snapshot)
        state = .loaded
    }
    #endif

    // MARK: Private

    private func updateAvatar() async {
        guard let service, let profile else { return }
        guard let url = profile.pictureURL else {
            if avatarURL != nil || avatar != nil {
                avatar = nil
                avatarURL = nil
                cache.saveAvatar(nil)
                saveSnapshot()
            }
            return
        }
        guard url != avatarURL || avatar == nil else { return }
        let generation = self.generation
        guard let data = try? await service.imageData(at: url),
              let image = UIImage(data: data),
              generation == self.generation
        else { return }
        avatar = image
        avatarURL = url
        cache.saveAvatar(data)
        saveSnapshot()
    }

    private func apply(_ snapshot: AccountSnapshot) {
        profile = snapshot.profile
        settings = snapshot.settings
        subscription = snapshot.subscription
        instructions = snapshot.instructions
        personalities = snapshot.personalities ?? []
        traits = snapshot.traits ?? []
        memories = snapshot.memories
        dataUsagePermitted = snapshot.dataUsagePermitted
        featureLimits = snapshot.featureLimits
        ageStatus = snapshot.ageStatus
        avatarURL = snapshot.avatarURL
    }

    private func saveSnapshot() {
        cache.save(AccountSnapshot(
            profile: profile,
            settings: settings,
            instructions: instructions,
            personalities: personalities,
            traits: traits,
            memories: memories,
            dataUsagePermitted: dataUsagePermitted,
            avatarURL: avatarURL,
            subscription: subscription,
            featureLimits: featureLimits,
            ageStatus: ageStatus
        ))
    }
}

private func capture<Value>(_ operation: () async throws -> Value) async -> Result<Value, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
