import OCTOCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var settings = app.settings

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AccountAvatar(account: app.auth.account, size: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: app.auth.account?.displayTitle ?? "OCTO")
                                .font(.headline)
                                .lineLimit(1)
                            Text(verbatim: app.auth.account?.displaySubtitle ?? "")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)

                    if app.authMethod == .chatGPT {
                        NavigationLink {
                            UsageView()
                        } label: {
                            Label("Usage limits", systemImage: "chart.bar.fill")
                        }
                    }
                }

                Section("Chats") {
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
                }

                Section("Personalization") {
                    NavigationLink {
                        PersonalizationView()
                    } label: {
                        Label("Custom instructions", systemImage: "person.text.rectangle")
                    }
                }

                Section("Voice & feedback") {
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
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Label("Delete all chats", systemImage: "trash")
                    }
                    .disabled(app.store.summaries.isEmpty)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Chats are stored only on this device. Messages go straight to OpenAI when you send them, with server-side storage turned off.")
                }

                Section {
                    LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                    Link(destination: AppInfo.repositoryURL) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Label("No telemetry, no analytics, no third-party SDKs.", systemImage: "lock.shield")
                        .foregroundStyle(Theme.secondaryText)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all chats?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    app.store.deleteAll()
                }
            } message: {
                Text("Every chat and attachment will be removed from this device.")
            }
            .confirmationDialog("Sign out of OCTO?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    dismiss()
                    Task { await app.signOut() }
                }
            }
        }
    }

    private var defaultModelBinding: Binding<String> {
        Binding(get: { app.defaultModel.id }, set: { app.settings.defaultModelID = $0 })
    }
}

extension Account {
    var displayTitle: String {
        switch method {
        case .apiKey: return String(localized: "OpenAI API key")
        case .chatGPT: return email ?? String(localized: "ChatGPT account")
        }
    }

    var displaySubtitle: String {
        switch method {
        case .apiKey:
            return String(localized: "Pay as you go")
        case .chatGPT:
            if let plan = ChatGPTPlan.displayName(for: planType) {
                return String(localized: "ChatGPT \(plan)")
            }
            return "ChatGPT"
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

struct PersonalizationView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                TextEditor(text: $settings.aboutUser)
                    .frame(minHeight: 120)
            } header: {
                Text("What should OCTO know about you?")
            } footer: {
                Text("For example your job, your interests or the languages you speak.")
            }

            Section {
                TextEditor(text: $settings.responseStyle)
                    .frame(minHeight: 120)
            } header: {
                Text("How should OCTO respond?")
            } footer: {
                Text("For example: concise, friendly, with examples, always in French.")
            }
        }
        .navigationTitle("Custom instructions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
