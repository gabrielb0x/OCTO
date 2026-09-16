import OCTOCore
import SwiftUI
import UIKit

/// Pages of the settings sheet.
enum SettingsRoute: Hashable {
    case personalization
    case memory
    case plugins
    case subscription
    case ageVerification
    case appearance
    case general
    case notifications
    case voice
    case privacy
    case protection
    case security
    case remoteControl
    case storage
    case dataControls
    case ads
    case reportProblem
    case helpCenter
    case about
    case developer
    case developerNetwork
}

/// Parts of the settings sheet a screenshot can scroll to.
enum SettingsSection: String, Hashable {
    case theme
    case appSettings
    case help
}

/// Settings sheet organized like the ChatGPT app's. The account sections show the ChatGPT
/// account; the others are preferences of this device.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsRoute]
    @State private var confirmSignOut = false
    @State private var isRestoring = false
    @State private var showsWhatsNew = false
    @State private var updateToShow: AppRelease?
    private let initialSection: SettingsSection?

    init(initialPath: [SettingsRoute] = [], initialSection: SettingsSection? = nil) {
        _path = State(initialValue: initialPath)
        self.initialSection = initialSection
    }

    var body: some View {
        @Bindable var settings = app.settings

        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    profileHeader
                    accountStatus
                    updateBanner

                    Section("Customize ChatGPT") {
                        row(.personalization, "Personalization", systemImage: "smiley")
                        row(.memory, "Memory", systemImage: "book")
                        row(.plugins, "Plugins", systemImage: "at")
                    }

                    Section("Account") {
                        if let email = app.accountEmail {
                            ContactRow(title: "Email address", systemImage: "envelope", value: email, kind: .email)
                        }
                        if let phone = app.account.profile?.phoneNumber {
                            ContactRow(title: "Phone number", systemImage: "phone", value: phone, kind: .phone)
                        }
                        NavigationLink(value: SettingsRoute.subscription) {
                            LabeledContent {
                                Text(verbatim: app.planShortName)
                            } label: {
                                Label("Subscription", systemImage: "plus.app")
                            }
                        }
                        Button(action: restorePurchases) {
                            HStack {
                                Label("Restore purchases", systemImage: "arrow.clockwise")
                                if isRestoring {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .foregroundStyle(Theme.primaryText)
                        .disabled(isRestoring)
                        row(.ageVerification, "Age verification", systemImage: "checkmark.shield")
                    }

                    Section("Theme") {
                        Picker(selection: $settings.theme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(verbatim: theme.title).tag(theme)
                            }
                        } label: {
                            Label("Theme", systemImage: "moon")
                        }
                        .pickerStyle(.menu)
                        .id(SettingsSection.theme)
                        accentRow
                        row(.appearance, "Appearance", systemImage: "paintbrush")
                    }

                    Section("App settings") {
                        row(.general, "General", systemImage: "gearshape")
                            .id(SettingsSection.appSettings)
                        row(.notifications, "Notifications", systemImage: "bell")
                        row(.voice, "Voice", systemImage: "waveform")
                        row(.privacy, "Privacy", systemImage: "eye.slash")
                        row(.protection, "Protection", systemImage: "lock.shield")
                        row(.security, "Security and login", systemImage: "lock")
                        row(.remoteControl, "Remote control", systemImage: "tv")
                        row(.storage, "Storage", systemImage: "externaldrive")
                        row(.dataControls, "Data controls", systemImage: "hand.raised")
                        row(.ads, "Ads management", systemImage: "megaphone")
                    }

                    if app.developer.isEnabled {
                        Section("Developer") {
                            row(.developer, "Developer mode", systemImage: "hammer")
                        }
                    }

                    Section("Help") {
                        row(.reportProblem, "Report a problem with the app", systemImage: "flag")
                            .id(SettingsSection.help)
                        row(.helpCenter, "Help center", systemImage: "questionmark.circle")
                        row(.about, "About", systemImage: "info.circle")
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmSignOut = true
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } footer: {
                        Button {
                            showsWhatsNew = true
                        } label: {
                            Text(verbatim: "OCTO \(AppInfo.version) (\(AppInfo.build))")
                                .font(.footnote)
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Shows what's new in this version"))
                    }
                }
                .task {
                    guard let initialSection else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(initialSection, anchor: .top)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
            .detachedRefreshable {
                await app.account.refresh()
            }
            .task {
                await app.account.refresh(ifOlderThan: 120)
            }
            .sheet(isPresented: $showsWhatsNew) {
                WhatsNewView(notes: ReleaseNotes.current)
            }
            .sheet(item: $updateToShow) { release in
                UpdateView(release: release)
            }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    dismiss()
                    Task { await app.signOut() }
                }
            } message: {
                Text("The chats of your ChatGPT account will be removed from this device.")
            }
        }
    }

    private var profileHeader: some View {
        Section {
            VStack(spacing: 10) {
                AccountAvatar(name: app.account.profile?.name, email: app.accountEmail, image: app.account.avatar, size: 76)
                VStack(spacing: 3) {
                    Text(verbatim: app.shieldedAccountName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: app.planName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if app.showsUpgradeOffer {
                    Button {
                        path.append(.subscription)
                    } label: {
                        Label("Upgrade", systemImage: "sparkle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(app.settings.accentStyle.link)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var accountStatus: some View {
        switch app.account.state {
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't load your ChatGPT settings", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                    Text(verbatim: message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Try again") {
                        Task { await app.account.refresh() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        case .loading where app.account.profile == nil:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading your ChatGPT account…")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        default:
            EmptyView()
        }
    }

    /// A newer OCTO found on GitHub.
    @ViewBuilder
    private var updateBanner: some View {
        if let release = app.updates.available {
            Section {
                Button {
                    updateToShow = release
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.title2)
                            .foregroundStyle(app.settings.accentStyle.link)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update available")
                                .font(.body.weight(.semibold))
                            Text("OCTO \(release.version) is ready to install")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(Theme.primaryText)
            }
        }
    }

    /// Accent color, shown like ChatGPT with a dot next to its name.
    @ViewBuilder
    private var accentRow: some View {
        @Bindable var settings = app.settings
        LabeledContent {
            Menu {
                Picker(selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { choice in
                        Label {
                            Text(verbatim: choice.title)
                        } icon: {
                            if let swatch = settings.accentStyle(for: choice).swatch {
                                Image(uiImage: swatch)
                            }
                        }
                        .tag(choice)
                    }
                } label: {
                    Text("Accent color")
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.accentStyle.color ?? Theme.primaryText)
                        .frame(width: 10, height: 10)
                    Text(verbatim: settings.accent.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.secondaryText)
            }
        } label: {
            Label("Accent color", systemImage: "paintpalette")
        }
    }

    private func row(_ route: SettingsRoute, _ title: LocalizedStringKey, systemImage: String) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .personalization: PersonalizationView()
        case .memory: MemoryView()
        case .plugins: PluginsView()
        case .subscription: SubscriptionView()
        case .ageVerification: AgeVerificationView()
        case .appearance: AppearanceView()
        case .general: GeneralSettingsView()
        case .notifications: NotificationSettingsView()
        case .voice: VoiceSettingsView()
        case .privacy: PrivacyView()
        case .protection: ProtectionSettingsView()
        case .security: SecuritySettingsView()
        case .remoteControl: RemoteControlView()
        case .storage: StorageSettingsView()
        case .dataControls: DataControlsView()
        case .ads: AdsSettingsView()
        case .reportProblem: ReportProblemView()
        case .helpCenter: HelpCenterView()
        case .about: AboutView()
        case .developer: DeveloperView()
        case .developerNetwork: NetworkLogView()
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            await app.restorePurchases()
            isRestoring = false
        }
    }
}

/// The plan of the account, when an active subscription renews, and the limits of the account.
struct SubscriptionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: app.planName)
                        .font(.title2.weight(.semibold))
                    Text(planSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 6)

                if let subscription = app.account.subscription {
                    if let workspace = subscription.workspaceName {
                        LabeledContent("Workspace", value: workspace)
                    }
                    // ChatGPT keeps the dates of a subscription that ended: they only show while one is active.
                    if subscription.hasActiveSubscription {
                        if let renewal = subscription.renewalDate {
                            LabeledContent {
                                Text(renewal, format: .dateTime.day().month(.wide).year())
                            } label: {
                                Text("Renews on")
                            }
                        }
                        if let end = subscription.endDate {
                            LabeledContent {
                                Text(end, format: .dateTime.day().month(.wide).year())
                            } label: {
                                Text("Ends on")
                            }
                        }
                        if let period = subscription.billingPeriod {
                            LabeledContent("Billing", value: billingTitle(period))
                        }
                        if let store = subscription.store {
                            LabeledContent("Bought on", value: storeTitle(store))
                        }
                    }
                }
            } footer: {
                Text("Subscriptions are managed in ChatGPT.")
            }

            if let limits = app.account.featureLimits, !limits.isEmpty {
                Section {
                    ForEach(limits.features) { limit in
                        FeatureLimitRow(limit: limit)
                    }
                } header: {
                    Text("Feature limits")
                } footer: {
                    Text("The limits of your ChatGPT account, read live like on the website. These features run in ChatGPT.")
                }
            }

            Section {
                if let usage = app.usage {
                    if let primary = usage.primary {
                        UsageWindowRow(title: windowTitle(primary), window: primary)
                    }
                    if let secondary = usage.secondary {
                        UsageWindowRow(title: windowTitle(secondary), window: secondary)
                    }
                    if usage.primary == nil, usage.secondary == nil {
                        Text("No limits were reported for your plan.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let error = app.usageError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.danger)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } header: {
                Text("Usage limits")
            } footer: {
                Text("Messages sent from OCTO count toward the Codex usage limits included in your ChatGPT plan.")
            }

            Section {
                Button {
                    if let url = URL(string: "https://chatgpt.com/#settings") {
                        openURL(url)
                    }
                } label: {
                    Label("Manage in ChatGPT", systemImage: "arrow.up.right.square")
                }
                .foregroundStyle(Theme.primaryText)
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .detachedRefreshable {
            await app.refreshUsage()
            await app.account.refresh()
        }
        .task {
            await app.refreshUsage()
            // Pulls the account's feature limits (conversation/init) when they haven't refreshed recently.
            await app.account.refresh(ifOlderThan: 60)
        }
    }

    private var planSummary: LocalizedStringKey {
        switch ChatGPTPlan.isPaid(app.planType) {
        case false?: return "You're on the free plan: ChatGPT picks the model for you."
        case true?: return "Your subscription lets you choose the model of each chat."
        case nil: return "OCTO couldn't tell which plan your account has."
        }
    }

    private func billingTitle(_ period: String) -> String {
        switch period.lowercased() {
        case "monthly", "month": return String(localized: "Monthly")
        case "yearly", "annual", "year": return String(localized: "Yearly")
        default: return period.capitalized
        }
    }

    private func storeTitle(_ store: AccountSubscription.Store) -> String {
        switch store {
        case .web: return String(localized: "The web")
        case .appStore: return "App Store"
        case .googlePlay: return "Google Play"
        }
    }

    private func windowTitle(_ window: UsageSnapshot.Window) -> String {
        guard let seconds = window.windowSeconds, seconds > 0 else {
            return String(localized: "Usage")
        }
        let hours = seconds / 3_600
        if hours >= 24 * 6 {
            return String(localized: "Weekly limit")
        }
        if hours >= 24 {
            return String(localized: "\(hours / 24)-day limit")
        }
        return String(localized: "\(max(hours, 1))-hour limit")
    }
}

/// One feature of the ChatGPT account with how many uses are left, like ChatGPT shows.
struct FeatureLimitRow: View {
    let limit: FeatureLimit

    var body: some View {
        LabeledContent {
            if limit.isBlocked || limit.remaining == 0 {
                Text("Limit reached")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.warning)
            } else if let remaining = limit.remaining {
                Text("\(remaining) left")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: FeatureLimitLabel.title(limit.feature))
                } icon: {
                    Image(systemName: FeatureLimitLabel.systemImage(limit.feature))
                }
                if let resetsAt = limit.resetsAt {
                    Text("Resets \(resetsAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }
}

/// Names and icons for the ChatGPT feature keys returned by `conversation/init`.
enum FeatureLimitLabel {
    static func title(_ feature: String) -> String {
        switch feature {
        case "deep_research": return "Deep Research"
        case "image_gen": return String(localized: "Image generation")
        case "file_upload": return String(localized: "File uploads")
        case "paste_text_to_file": return String(localized: "Paste as file")
        case "reason": return String(localized: "Extended thinking")
        default: return feature.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func systemImage(_ feature: String) -> String {
        switch feature {
        case "deep_research": return "text.magnifyingglass"
        case "image_gen": return "photo"
        case "file_upload": return "paperclip"
        case "paste_text_to_file": return "doc.on.clipboard"
        case "reason": return "brain"
        default: return "gauge.with.dots.needle.50percent"
        }
    }
}

struct UsageWindowRow: View {
    let title: String
    let window: UsageSnapshot.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: title)
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(Int(window.usedPercent.rounded())) %")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(tint)
            }
            ProgressView(value: window.usedPercent, total: 100)
                .tint(tint)
            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        switch window.usedPercent {
        case ..<60: return Theme.success
        case ..<85: return Theme.warning
        default: return Theme.danger
        }
    }
}
