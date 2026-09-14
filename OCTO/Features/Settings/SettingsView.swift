import OCTOCore
import SwiftUI
import UIKit

/// Settings sheet organized like the ChatGPT app. The account sections show the ChatGPT account;
/// the others are preferences of this device.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var settings = app.settings

        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AccountAvatar(name: app.account.profile?.name, email: app.accountEmail, image: app.account.avatar, size: 76)
                        VStack(spacing: 3) {
                            Text(verbatim: app.accountName)
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                            Text(verbatim: app.planName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                accountStatus

                Section("Account") {
                    if let name = app.account.profile?.name {
                        LabeledContent {
                            Text(verbatim: name)
                                .lineLimit(1)
                        } label: {
                            Label("Name", systemImage: "person")
                        }
                    }
                    if let email = app.accountEmail {
                        LabeledContent {
                            Text(verbatim: email)
                                .lineLimit(1)
                        } label: {
                            Label("Email", systemImage: "envelope")
                        }
                    }
                    LabeledContent {
                        Text(verbatim: app.planName)
                    } label: {
                        Label("Subscription", systemImage: "plus.circle")
                    }
                    NavigationLink {
                        UsageView()
                    } label: {
                        Label("Usage limits", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        PersonalizationView()
                    } label: {
                        Label("Personalization", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        DataControlsView()
                    } label: {
                        Label("Data controls", systemImage: "externaldrive")
                    }
                }

                Section {
                    Picker(selection: defaultModelBinding) {
                        ForEach(app.models) { model in
                            Text(verbatim: model.displayName).tag(model.id)
                        }
                    } label: {
                        Label("Default model", systemImage: "cpu")
                    }
                    Toggle(isOn: $settings.webSearchByDefault) {
                        Label("Web search by default", systemImage: "globe")
                    }
                    Toggle(isOn: $settings.showReasoning) {
                        Label("Show reasoning", systemImage: "brain")
                    }
                    Toggle(isOn: $settings.autoGenerateTitles) {
                        Label("Generate chat titles", systemImage: "character.cursor.ibeam")
                    }
                } header: {
                    Text("Chats")
                } footer: {
                    Text("Used for the messages you write in OCTO.")
                }

                Section("App") {
                    Button(action: openSystemSettings) {
                        LabeledContent {
                            Text(verbatim: languageName)
                        } label: {
                            Label("App language", systemImage: "character.bubble")
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label("Haptic feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Read aloud speed", systemImage: "speaker.wave.2")
                        Slider(value: $settings.speechRate, in: 0.35...0.6) {
                            Text("Read aloud speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                        .foregroundStyle(Theme.secondaryText)
                    }
                }

                Section {
                    Link(destination: AppInfo.repositoryURL) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .foregroundStyle(Theme.primaryText)
                    Label("No telemetry, no analytics, no third-party SDKs.", systemImage: "lock.shield")
                        .foregroundStyle(Theme.secondaryText)
                    LabeledContent {
                        Text(verbatim: "\(AppInfo.version) (\(AppInfo.build))")
                    } label: {
                        Label("Version", systemImage: "info.circle")
                    }
                } header: {
                    Text("About OCTO")
                } footer: {
                    Text("OCTO is an independent open-source project, not affiliated with or endorsed by OpenAI. ChatGPT is a trademark of OpenAI.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
            .refreshable {
                await app.account.refresh()
            }
            .task {
                await app.account.refresh(ifOlderThan: 120)
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

    @ViewBuilder
    private var accountStatus: some View {
        switch app.account.state {
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't load your ChatGPT settings", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
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

    private var defaultModelBinding: Binding<String> {
        Binding(get: { app.defaultModel.id }, set: { app.settings.defaultModelID = $0 })
    }

    private var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: Locale.current) ?? code
    }

    /// iOS manages per-app languages in the Settings app, as for ChatGPT.
    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

struct UsageView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if let usage = app.usage {
                if let plan = ChatGPTPlan.displayName(for: usage.planType) {
                    Section {
                        LabeledContent("Plan", value: "ChatGPT \(plan)")
                    }
                }
                Section {
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
                } footer: {
                    Text("Messages sent from OCTO count toward the Codex usage limits included in your ChatGPT plan.")
                }
            } else if let error = app.usageError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.danger)
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Usage limits")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await app.refreshUsage()
        }
        .task {
            await app.refreshUsage()
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
        case ..<85: return .orange
        default: return Theme.danger
        }
    }
}
