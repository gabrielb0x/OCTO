import OCTOCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Developer mode: inspectors, simulations and tools to see exactly what OCTO does.
struct DeveloperView: View {
    @Environment(AppModel.self) private var app
    @State private var showsWhatsNew = false
    @State private var confirmDisable = false

    var body: some View {
        @Bindable var developer = app.developer

        List {
            Section {
                overview
            }

            Section("Inspect") {
                NavigationLink(value: SettingsRoute.developerNetwork) {
                    LabeledContent {
                        Text(verbatim: "\(app.developer.console.network.count)")
                    } label: {
                        Label("Network", systemImage: "network")
                    }
                }
                NavigationLink {
                    EventLogView()
                } label: {
                    LabeledContent {
                        Text(verbatim: "\(app.developer.console.events.count)")
                    } label: {
                        Label("Event log", systemImage: "list.bullet.rectangle")
                    }
                }
                NavigationLink {
                    APIConsoleView()
                } label: {
                    Label("API console", systemImage: "terminal")
                }
                NavigationLink {
                    SessionInspectorView()
                } label: {
                    Label("Session and tokens", systemImage: "key")
                }
                NavigationLink {
                    AccountInspectorView()
                } label: {
                    Label("Account data", systemImage: "person.text.rectangle")
                }
                NavigationLink {
                    ModelsInspectorView()
                } label: {
                    Label("Models", systemImage: "cpu")
                }
                NavigationLink {
                    StorageInspectorView()
                } label: {
                    Label("Files and preferences", systemImage: "folder")
                }
                NavigationLink {
                    EnvironmentInspectorView()
                } label: {
                    Label("Device and build", systemImage: "iphone")
                }
            }

            Section {
                Toggle(isOn: $developer.recordsNetwork) {
                    Label("Record network requests", systemImage: "record.circle")
                }
                Toggle(isOn: $developer.showsPerformanceOverlay) {
                    Label("Performance overlay", systemImage: "gauge.with.dots.needle.67percent")
                }
                Toggle(isOn: $developer.showsMessageDetails) {
                    Label("Message details", systemImage: "info.bubble")
                }
                Toggle(isOn: $developer.showsRawMarkdown) {
                    Label("Raw Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Toggle(isOn: $developer.disablesTextPacing) {
                    Label("Show text as it arrives", systemImage: "text.cursor")
                }
                Toggle(isOn: $developer.slowAnimations) {
                    Label("Slow animations", systemImage: "tortoise")
                }
            } header: {
                Text("Display")
            } footer: {
                Text("The network log keeps the last 250 requests in memory, without tokens or cookies. Nothing is saved or sent.")
            }

            Section {
                Picker(selection: $developer.planOverride) {
                    ForEach(DeveloperSettings.PlanOverride.allCases) { plan in
                        Text(verbatim: plan.title).tag(plan)
                    }
                } label: {
                    Label("Plan", systemImage: "plus.app")
                }
                Toggle(isOn: $developer.forcesModelPicker) {
                    Label("Always show the model picker", systemImage: "cpu")
                }
                Picker(selection: $developer.simulatedFailure) {
                    ForEach(SimulatedFailure.allCases) { failure in
                        Text(verbatim: failure.title).tag(failure)
                    }
                } label: {
                    Label("Simulate a failure", systemImage: "bolt.horizontal.circle")
                }
            } header: {
                Text("Simulation")
            } footer: {
                Text("Simulations last until OCTO restarts.")
            }

            Section("Actions") {
                ActionRow(title: "Sync chats now", systemImage: "arrow.triangle.2.circlepath") {
                    await app.store.syncWithAccount()
                    app.toasts.show(String(localized: "Chats synced"), style: .info)
                }
                ActionRow(title: "Refresh the account", systemImage: "person.crop.circle.badge.checkmark") {
                    await app.account.refresh()
                    app.toasts.show(String(localized: "Account refreshed"), style: .info)
                }
                ActionRow(title: "Refresh tokens now", systemImage: "key") {
                    await app.refreshSession()
                }
                ActionRow(title: "Expire tokens", systemImage: "hourglass.bottomhalf.filled") {
                    await app.auth.vault.markStale()
                    app.toasts.show(String(localized: "The next request will refresh the tokens"), style: .info)
                }
                ActionRow(title: "Send a test notification", systemImage: "bell.badge") {
                    await app.notifications.sendTest()
                    app.toasts.show(String(localized: "Notification in 5 seconds: leave OCTO to see it"), style: .info)
                }
                ActionRow(title: "Try the toasts", systemImage: "capsule") {
                    await playToasts()
                }
                Button {
                    showsWhatsNew = true
                } label: {
                    Label("Show What's New", systemImage: "sparkles")
                }
                ActionRow(title: "Show What's New at next launch", systemImage: "sparkles.rectangle.stack") {
                    UserDefaults.standard.removeObject(forKey: ReleaseNotes.lastSeenVersionKey)
                    app.toasts.show(String(localized: "What's New will show at next launch"), style: .info)
                }
                ActionRow(title: "Clear the model cache", systemImage: "trash") {
                    UserDefaults.standard.removeObject(forKey: AppModel.modelsCacheKey)
                    app.toasts.show(String(localized: "Model cache cleared"), style: .info)
                }
                ActionRow(title: "Check for updates now", systemImage: "arrow.down.app") {
                    await app.updates.check()
                    if let error = app.updates.errorMessage {
                        app.toasts.show(error, style: .failure)
                    } else if let release = app.updates.available {
                        app.toasts.show(String(localized: "OCTO \(release.version) is available"), style: .info)
                    } else {
                        app.toasts.show(String(localized: "OCTO is up to date"), style: .info)
                    }
                }
            }
            .foregroundStyle(Theme.primaryText)

            Section {
                ShareLink(item: diagnosticsReport) {
                    Label("Export diagnostics", systemImage: "square.and.arrow.up")
                }
                .foregroundStyle(Theme.primaryText)
            } footer: {
                Text("A text report with the device details, the event log and the network log, without credentials.")
            }

            Section {
                Button(role: .destructive) {
                    confirmDisable = true
                } label: {
                    DestructiveLabel(title: "Turn off developer mode", systemImage: "hammer.circle")
                }
                .destructiveRow()
            }
        }
        .navigationTitle("Developer mode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView(notes: ReleaseNotes.current)
        }
        .confirmationDialog("Turn off developer mode?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) {
                app.developer.isEnabled = false
                app.toasts.show(String(localized: "Developer mode is off"), style: .info, systemImage: "hammer")
            }
        } message: {
            Text("The logs are cleared and the simulations stop.")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.onProminent)
                    .frame(width: 48, height: 48)
                    .background(Theme.prominentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer mode")
                        .font(.headline)
                    Text(verbatim: "OCTO \(AppInfo.version) (\(AppInfo.build)) · \(DeviceInfo.buildConfiguration) · \(DeviceInfo.modelIdentifier)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 10) {
                StatTile(title: "Plan", value: app.planType ?? "–")
                StatTile(title: "Models", value: "\(app.models.count)")
                StatTile(title: "Chats", value: "\(app.store.summaries.count)")
                StatTile(title: "Requests", value: "\(app.developer.console.network.count)")
                StatTile(title: "Failures", value: "\(app.developer.console.network.filter(\.isFailure).count)")
                StatTile(title: "Memory", value: ByteCountFormatter.string(fromByteCount: Int64(PerformanceMonitor.currentMemoryFootprint() ?? 0), countStyle: .memory))
            }
        }
        .padding(.vertical, 6)
    }

    private var diagnosticsReport: String {
        var lines = ["# OCTO diagnostics", ""]
        for item in DeviceInfo.diagnostics() {
            lines.append("- \(item.label): \(item.value)")
        }
        lines.append("- Plan: \(app.planType ?? "unknown")")
        lines.append("- Models: \(app.models.map(\.id).joined(separator: ", "))")
        lines.append("- Chats: \(app.store.summaries.count), projects: \(app.store.projects.count)")
        lines += ["", "## Events", "", app.developer.console.eventsText(limit: 400), "", "## Network", ""]
        for entry in app.developer.console.network.prefix(150) {
            let status = entry.statusCode.map { String($0) } ?? "-"
            let duration = entry.duration.map { "\(Int(($0 * 1_000).rounded())) ms" } ?? "-"
            var line = "\(entry.startedAt.formatted(.iso8601)) \(entry.method) \(entry.displayURL) → \(status) \(duration) \(entry.responseBytes) B"
            if case .failed(let message) = entry.phase {
                line += " ERROR \(message)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func playToasts() async {
        let samples: [(String, Toast.Style)] = [
            (String(localized: "The chat has been deleted"), .success),
            (String(localized: "Session refreshed"), .info),
            (String(localized: "ChatGPT blocked the request for your account data. Try again later."), .warning),
            (String(localized: "You appear to be offline."), .failure),
        ]
        for (message, style) in samples {
            app.toasts.show(message, style: style, duration: 1.6)
            try? await Task.sleep(for: .seconds(1.9))
        }
    }
}

extension DeveloperSettings.PlanOverride {
    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        default: return ChatGPTPlan.displayName(for: rawValue) ?? rawValue
        }
    }
}

extension SimulatedFailure {
    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .offline: return String(localized: "No connection")
        case .accountBlocked: return String(localized: "Account blocked by Cloudflare")
        case .accountServerError: return String(localized: "Account server error")
        case .repliesConnectionLost: return String(localized: "Replies cut off")
        case .signInTimeout: return String(localized: "Sign-in timeout")
        }
    }
}

/// A button that runs async work and shows a spinner meanwhile.
struct ActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: @MainActor () async -> Void
    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                if isRunning {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isRunning)
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(verbatim: value)
                .font(.body.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A technical name and its value, in monospaced type.
struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(verbatim: value)
                .font(.footnote.monospaced())
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(verbatim: key)
                .font(.footnote.monospaced())
        }
    }
}

/// A value copied to the clipboard when tapped.
struct CopyRow: View {
    @Environment(AppModel.self) private var app
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            app.toasts.show(String(localized: "Copied"), style: .info)
        } label: {
            LabeledContent {
                Text(verbatim: value)
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            } label: {
                Text(title)
            }
        }
        .foregroundStyle(Theme.primaryText)
    }
}

/// A block of code or JSON with a copy button in its header.
struct CodeSection: View {
    @Environment(AppModel.self) private var app
    let title: LocalizedStringKey
    let text: String

    var body: some View {
        Section {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    app.toasts.show(String(localized: "Copied"), style: .info)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(Text("Copy"))
            }
        }
    }
}

struct SessionInspectorView: View {
    @Environment(AppModel.self) private var app
    @State private var info: CredentialVault.SessionInfo?
    @State private var isLoaded = false
    @State private var confirmCopy = false

    var body: some View {
        List {
            if let info {
                Section("Session") {
                    CopyRow(title: "Account ID", value: info.accountID ?? "–")
                    CopyRow(title: "User ID", value: app.auth.account?.userID ?? "–")
                    KeyValueRow(key: "chatgpt_plan_type", value: app.auth.account?.planType ?? "–")
                    KeyValueRow(key: "lastRefresh", value: info.lastRefresh.formatted(date: .abbreviated, time: .standard))
                    if let expiresAt = info.accessTokenExpiresAt {
                        KeyValueRow(key: "accessTokenExpires", value: expiresAt.formatted(date: .abbreviated, time: .standard))
                    }
                }

                Section {
                    Button {
                        confirmCopy = true
                    } label: {
                        DestructiveLabel(title: "Copy the access token", systemImage: "doc.on.doc")
                    }
                    .destructiveRow()
                } footer: {
                    Text("Anyone with this token can use your ChatGPT account until it expires. Never share it.")
                }

                if let claims = JWT.prettyPayload(of: info.idToken) {
                    CodeSection(title: "ID token claims", text: claims)
                }
                if let claims = JWT.prettyPayload(of: info.accessToken) {
                    CodeSection(title: "Access token claims", text: claims)
                }
            } else if isLoaded {
                ContentUnavailableView("No stored session", systemImage: "lock.slash")
            }
        }
        .navigationTitle("Session and tokens")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            info = await app.auth.vault.sessionInfo()
            isLoaded = true
        }
        .confirmationDialog("Copy the access token?", isPresented: $confirmCopy, titleVisibility: .visible) {
            Button("Copy for 2 minutes", role: .destructive) {
                guard let token = info?.accessToken else { return }
                UIPasteboard.general.setItems(
                    [[UTType.plainText.identifier: token]],
                    options: [.expirationDate: Date().addingTimeInterval(120), .localOnly: true]
                )
                app.toasts.show(String(localized: "Token copied for 2 minutes"), style: .warning)
            }
        } message: {
            Text("Anyone with this token can use your ChatGPT account until it expires. Never share it.")
        }
    }
}

struct AccountInspectorView: View {
    @Environment(AppModel.self) private var app
    @State private var snapshot: String?

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "state", value: stateText)
                if let lastRefresh = app.account.lastRefresh {
                    KeyValueRow(key: "lastRefresh", value: lastRefresh.formatted(date: .omitted, time: .standard))
                }
                ActionRow(title: "Refresh the account", systemImage: "arrow.clockwise") {
                    await app.account.refresh()
                    snapshot = loadSnapshot()
                }
                .foregroundStyle(Theme.primaryText)
            }

            if let subscription = app.account.subscription {
                Section("Subscription") {
                    KeyValueRow(key: "plan_type", value: subscription.planType ?? "–")
                    KeyValueRow(key: "has_active_subscription", value: subscription.hasActiveSubscription ? "true" : "false")
                    KeyValueRow(key: "expires_at", value: subscription.expiresAt?.formatted(.iso8601) ?? "–")
                    KeyValueRow(key: "will_renew", value: subscription.willRenew.map { $0 ? "true" : "false" } ?? "–")
                    KeyValueRow(key: "billing_period", value: subscription.billingPeriod ?? "–")
                    KeyValueRow(key: "purchase_origin_platform", value: subscription.purchasePlatform ?? "–")
                    if !subscription.features.isEmpty {
                        DisclosureGroup {
                            ForEach(subscription.features, id: \.self) { feature in
                                Text(verbatim: feature)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        } label: {
                            KeyValueRow(key: "features", value: "\(subscription.features.count)")
                        }
                    }
                }
            }

            if let snapshot {
                CodeSection(title: "Cached account data", text: snapshot)
            }
        }
        .navigationTitle("Account data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            snapshot = loadSnapshot()
        }
    }

    private var stateText: String {
        switch app.account.state {
        case .idle: return "idle"
        case .loading: return "loading"
        case .loaded: return "loaded"
        case .failed(let message): return "failed: \(message)"
        }
    }

    private func loadSnapshot() -> String? {
        guard let data = try? Data(contentsOf: app.account.cache.snapshotURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: pretty, as: UTF8.self)
    }
}

struct ModelsInspectorView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "allowsModelChoice", value: app.allowsModelChoice ? "true" : "false")
                KeyValueRow(key: "planType", value: app.planType ?? "nil")
                KeyValueRow(key: "defaultModel", value: app.defaultModel.id)
                if let updatedAt = app.modelsUpdatedAt {
                    KeyValueRow(key: "updatedAt", value: updatedAt.formatted(date: .omitted, time: .standard))
                }
                if let error = app.modelsError {
                    Text(verbatim: error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
                ActionRow(title: "Reload models", systemImage: "arrow.clockwise") {
                    await app.refreshModels()
                }
                .foregroundStyle(Theme.primaryText)
            }

            ForEach(app.models) { model in
                Section {
                    let efforts = model.reasoningEfforts.map(\.effort).joined(separator: ", ")
                    KeyValueRow(key: "id", value: model.id)
                    KeyValueRow(key: "priority", value: "\(model.priority)")
                    KeyValueRow(key: "contextWindow", value: model.contextWindow.map { "\($0)" } ?? "–")
                    KeyValueRow(key: "reasoningEfforts", value: efforts.isEmpty ? "–" : efforts)
                    KeyValueRow(key: "defaultReasoningEffort", value: model.defaultReasoningEffort ?? "–")
                    KeyValueRow(key: "acceptsImages", value: model.acceptsImages ? "true" : "false")
                    KeyValueRow(key: "supportsVerbosity", value: model.supportsVerbosity ? "true" : "false")
                    KeyValueRow(key: "supportsReasoningSummaries", value: model.supportsReasoningSummaries ? "true" : "false")
                    if let summary = model.summary {
                        Text(verbatim: summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text(verbatim: model.displayName)
                }
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StorageInspectorView: View {
    struct FileItem: Identifiable {
        let id: String
        let bytes: Int64
    }

    struct PreferenceItem: Identifiable {
        let id: String
        let value: String
    }

    @Environment(AppModel.self) private var app
    @State private var files: [FileItem] = []
    @State private var preferences: [PreferenceItem] = []

    var body: some View {
        List {
            Section("Chats") {
                KeyValueRow(key: "summaries", value: "\(app.store.summaries.count)")
                KeyValueRow(key: "accountChats", value: "\(app.store.summaries.filter(\.isAccountChat).count)")
                KeyValueRow(key: "localChats", value: "\(app.store.summaries.filter { !$0.isAccountChat }.count)")
                KeyValueRow(key: "projects", value: "\(app.store.projects.count)")
                KeyValueRow(key: "openedInMemory", value: "\(app.store.cachedConversationCount)")
                KeyValueRow(key: "generating", value: "\(app.liveSessionCount)")
                KeyValueRow(key: "canLoadMore", value: app.store.canLoadMore ? "true" : "false")
                KeyValueRow(key: "nextOffset", value: "\(app.store.nextOffset)")
                KeyValueRow(key: "syncState", value: syncStateText)
                KeyValueRow(key: "lastSync", value: app.store.lastSync?.formatted(date: .omitted, time: .standard) ?? "–")
            }

            Section("Largest files") {
                ForEach(files) { file in
                    KeyValueRow(key: file.id, value: ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                }
            }

            Section {
                ForEach(preferences) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.id)
                            .font(.caption.monospaced().weight(.semibold))
                        Text(verbatim: item.value)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(4)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: item.id)
                            preferences = Self.loadPreferences()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Swipe a preference to delete it. Some only take effect at the next launch.")
            }
        }
        .navigationTitle("Files and preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let root = app.store.files.rootDirectory
            files = await Task.detached(priority: .utility) {
                Self.largestFiles(in: root)
            }.value
            preferences = Self.loadPreferences()
        }
    }

    private var syncStateText: String {
        switch app.store.syncState {
        case .idle: return "idle"
        case .syncing: return "syncing"
        case .failed(let message): return "failed: \(message)"
        }
    }

    nonisolated static func largestFiles(in root: URL) -> [FileItem] {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var items: [FileItem] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let name = url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
            items.append(FileItem(id: name, bytes: Int64(values.totalFileAllocatedSize ?? 0)))
        }
        return Array(items.sorted { $0.bytes > $1.bytes }.prefix(30))
    }

    static func loadPreferences() -> [PreferenceItem] {
        UserDefaults.standard.dictionaryRepresentation()
            .filter { key, _ in AppSettings.keyPrefixes.contains { key.hasPrefix($0) } }
            .map { key, value in PreferenceItem(id: key, value: describe(value)) }
            .sorted { $0.id < $1.id }
    }

    private static func describe(_ value: Any) -> String {
        if let data = value as? Data {
            return "<\(data.count) bytes>"
        }
        return String(String(describing: value).prefix(300))
    }
}

struct EnvironmentInspectorView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section(content: {
                KeyValueRow(key: "version", value: "\(AppInfo.version) (\(AppInfo.build))")
                KeyValueRow(key: "configuration", value: DeviceInfo.buildConfiguration)
                KeyValueRow(key: "bundleIdentifier", value: DeviceInfo.bundleIdentifier)
                KeyValueRow(key: "demo", value: app.isDemo ? "true" : "false")
                KeyValueRow(key: "originator", value: CodexBackend.originator)
                KeyValueRow(key: "clientVersion", value: CodexBackend.clientVersion)
                CopyRow(title: "User agent", value: AppInfo.userAgent)
            }, header: {
                Text(verbatim: "OCTO")
            })

            Section("Device") {
                KeyValueRow(key: "model", value: DeviceInfo.modelIdentifier)
                KeyValueRow(key: "system", value: DeviceInfo.systemVersion)
                KeyValueRow(key: "language", value: AppInfo.languageTag)
                KeyValueRow(key: "locale", value: Locale.current.identifier)
                KeyValueRow(key: "timeZone", value: TimeZone.current.identifier)
                KeyValueRow(key: "processors", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
                KeyValueRow(key: "physicalMemory", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                KeyValueRow(key: "memoryFootprint", value: ByteCountFormatter.string(fromByteCount: Int64(PerformanceMonitor.currentMemoryFootprint() ?? 0), countStyle: .memory))
                KeyValueRow(key: "freeDiskSpace", value: DeviceInfo.freeDiskSpace.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "–")
                KeyValueRow(key: "thermalState", value: DeviceInfo.thermalState)
                KeyValueRow(key: "lowPowerMode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "true" : "false")
                KeyValueRow(key: "notificationAuthorization", value: "\(app.notifications.authorization.rawValue)")
                KeyValueRow(key: "theme", value: app.settings.theme.rawValue)
                KeyValueRow(key: "accent", value: app.settings.accent.rawValue)
            }
        }
        .navigationTitle("Device and build")
        .navigationBarTitleDisplayMode(.inline)
    }
}
