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
    var pricing: CheckoutPricing?
    var featureLimits: FeatureLimits?
    var ageStatus: AgeStatus?
    var devices: AccountDevices?
    var security: AccountSecurity?
    var fileStorage: AccountFileStorage?
}

/// The account snapshot and profile picture, in Application Support.
final class AccountCache: @unchecked Sendable {
    let directory: URL

    convenience init(folderName: String = AccountStorage.folderName) {
        self.init(directory: AccountStorage.root(folderName: folderName))
    }

    /// The cached data of one account, in that account's own folder.
    init(directory accountDirectory: URL) {
        directory = accountDirectory.appendingPathComponent("Account", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

    /// When the picture was saved, so it's only downloaded again now and then.
    var avatarSavedAt: Date? {
        (try? FileManager.default.attributesOfItem(atPath: avatarURL.path))?[.modificationDate] as? Date
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
    /// What ChatGPT charges for its plans where the device is, for the Upgrade screen. Only that
    /// screen needs them, and they barely move, so they're read there instead of at every refresh.
    private(set) var pricing: CheckoutPricing?
    private(set) var instructions: CustomInstructions?
    private(set) var personalities: [PersonalityOption] = []
    private(set) var traits: [PersonalityTrait] = []
    private(set) var memories: MemoriesSnapshot?
    private(set) var dataUsagePermitted: Bool?
    private(set) var ageStatus: AgeStatus?
    /// Live usage limits of the ChatGPT account (Deep Research, image generation, file uploads…).
    private(set) var featureLimits: FeatureLimits?
    /// Devices signed into the account, and how it's protected. Only the Devices page needs them,
    /// so they're read there instead of at every refresh.
    private(set) var devices: AccountDevices?
    private(set) var security: AccountSecurity?
    private(set) var devicesState: LoadState = .idle
    /// Space the files of the account's chats take on ChatGPT's side, shown next to the device's.
    private(set) var fileStorage: AccountFileStorage?
    /// Settings being saved to the account right now.
    private(set) var savingSettings: Set<AccountSettingFeature> = []
    private(set) var state: LoadState = .idle
    private(set) var lastRefresh: Date?

    @ObservationIgnored private(set) var cache: AccountCache
    @ObservationIgnored private let service: AccountService?
    @ObservationIgnored private var avatarURL: URL?
    @ObservationIgnored private var lastDevicesRefresh: Date?
    @ObservationIgnored private var lastFileStorageRefresh: Date?
    @ObservationIgnored private var lastPricingRefresh: Date?
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

    /// The devices signed into the account and how it's protected. Asked for by the Devices page
    /// only: they say nothing about the chats, so they stay out of the refresh that runs at launch.
    func refreshDevices(ifOlderThan interval: TimeInterval = 0) async {
        guard let service, devicesState != .loading else { return }
        if interval > 0, let lastDevicesRefresh, Date().timeIntervalSince(lastDevicesRefresh) < interval { return }
        lastDevicesRefresh = Date()
        let generation = self.generation
        devicesState = .loading

        async let devicesResult = capture { try await service.devices() }
        async let securityResult = capture { try await service.security() }
        let devicesOutcome = await devicesResult
        let securityOutcome = await securityResult
        guard generation == self.generation else { return }

        if case .success(let value) = devicesOutcome { devices = value }
        if case .success(let value) = securityOutcome { security = value }
        let failures: [(String, Error?)] = [("devices", devicesOutcome.failure), ("security", securityOutcome.failure)]
        for case let (name, error?) in failures {
            DevLog.log("account", "\(name) failed: \(DevLog.describe(error))", level: error.isCancellation ? .debug : .warning)
        }
        // The protection is a bonus: only the device list failing is worth telling about.
        if let error = devicesOutcome.failure, !error.isCancellation {
            devicesState = .failed(ChatSession.describe(error))
        } else {
            devicesState = .loaded
        }
        saveSnapshot()
    }

    /// What the account's own files take on ChatGPT's side, for the Storage page.
    func refreshFileStorage(ifOlderThan interval: TimeInterval = 0) async {
        guard let service else { return }
        if interval > 0, let lastFileStorageRefresh, Date().timeIntervalSince(lastFileStorageRefresh) < interval { return }
        lastFileStorageRefresh = Date()
        let generation = self.generation
        do {
            let value = try await service.fileStorage()
            guard generation == self.generation else { return }
            fileStorage = value
            saveSnapshot()
        } catch {
            DevLog.log("account", "fileStorage failed: \(DevLog.describe(error))", level: error.isCancellation ? .debug : .warning)
        }
    }

    /// Deletes one saved memory in the ChatGPT account. The row leaves right away and comes back
    /// if the account refuses; what's left is read back, so the memory gauge follows.
    func deleteMemory(id: String) async throws {
        let previous = memories
        if var snapshot = memories {
            snapshot.memories.removeAll { $0.id == id }
            memories = snapshot
        }
        guard let service else { return }
        let generation = self.generation
        do {
            try await service.deleteMemory(id: id)
        } catch {
            if generation == self.generation {
                memories = previous
            }
            throw error
        }
        guard generation == self.generation else { return }
        if let fresh = try? await service.memories(), generation == self.generation {
            memories = fresh
        }
        saveSnapshot()
    }

    /// Clears the advertising profile ChatGPT keeps for the account, then reads the settings back,
    /// so the ads switches show what the account kept.
    func deleteAdsProfile() async throws {
        guard let service else { return }
        let generation = self.generation
        try await service.deleteAdsProfile()
        guard generation == self.generation else { return }
        if let fresh = try? await service.settings(), generation == self.generation, savingSettings.isEmpty {
            settings = fresh
            saveSnapshot()
        }
    }

    /// What ChatGPT charges for its plans, for the Upgrade screen. Asked for by that screen only.
    func refreshPricing(ifOlderThan interval: TimeInterval = 0) async {
        guard let service else { return }
        if interval > 0, let lastPricingRefresh, Date().timeIntervalSince(lastPricingRefresh) < interval { return }
        lastPricingRefresh = Date()
        let generation = self.generation
        do {
            let value = try await service.checkoutPricing()
            guard generation == self.generation else { return }
            pricing = value
            saveSnapshot()
        } catch {
            DevLog.log("account", "pricing failed: \(DevLog.describe(error))", level: error.isCancellation ? .debug : .warning)
        }
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

    /// Reads another account's cached data, when you switch to it: what was known about the
    /// previous account is dropped from memory — but left in its own folder, so switching back
    /// shows it again right away — and the new account is read from its folder.
    func use(cache: AccountCache) {
        resetState()
        self.cache = cache
        if let snapshot = cache.loadSnapshot() {
            apply(snapshot)
            state = .loaded
        }
        avatar = cache.loadAvatar().flatMap { UIImage(data: $0) }
    }

    /// Forgets the account on sign-out, cached files included.
    func clear() {
        resetState()
        cache.clear()
    }

    /// Drops what is held about the account in memory, without touching its folder.
    private func resetState() {
        generation += 1
        profile = nil
        avatar = nil
        settings = nil
        subscription = nil
        pricing = nil
        instructions = nil
        personalities = []
        traits = []
        memories = nil
        dataUsagePermitted = nil
        ageStatus = nil
        featureLimits = nil
        devices = nil
        security = nil
        devicesState = .idle
        fileStorage = nil
        savingSettings = []
        avatarURL = nil
        lastRefresh = nil
        lastDevicesRefresh = nil
        lastFileStorageRefresh = nil
        lastPricingRefresh = nil
        state = .idle
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
        pricing = snapshot.pricing
        instructions = snapshot.instructions
        personalities = snapshot.personalities ?? []
        traits = snapshot.traits ?? []
        memories = snapshot.memories
        dataUsagePermitted = snapshot.dataUsagePermitted
        featureLimits = snapshot.featureLimits
        ageStatus = snapshot.ageStatus
        devices = snapshot.devices
        security = snapshot.security
        fileStorage = snapshot.fileStorage
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
            pricing: pricing,
            featureLimits: featureLimits,
            ageStatus: ageStatus,
            devices: devices,
            security: security,
            fileStorage: fileStorage
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
