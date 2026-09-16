import OCTOCore
import SwiftUI

/// What OCTO keeps, shows and sends, with the switches to keep more to yourself.
struct PrivacyView: View {
    @Environment(AppModel.self) private var app
    @State private var hosts: [NetworkActivity.Host] = []

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No tracking in OCTO", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.success)
                    Text("No analytics, no ads, no third-party code. OCTO only talks to OpenAI for your account and, if you let it, to GitHub for updates.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(selection: $settings.contactVisibility) {
                    ForEach(ContactVisibility.allCases) { visibility in
                        Text(verbatim: visibility.title).tag(visibility)
                    }
                } label: {
                    Label("Email and phone number", systemImage: "eye.slash")
                }
            } header: {
                Text("Your details")
            } footer: {
                Text("How the email address and the phone number of your account show in Settings. Behind dots, a tap shows them for 30 seconds — never while the screen is recorded, mirrored or shared.")
            }

            Section {
                Toggle(isOn: $settings.temporaryChatsByDefault) {
                    Label {
                        Text("Temporary chats by default")
                    } icon: {
                        Image("TemporaryChat")
                    }
                }
                Picker(selection: $settings.localRetention) {
                    ForEach(LocalRetention.allCases) { retention in
                        Text(verbatim: retention.title).tag(retention)
                    }
                } label: {
                    Label("Keep chats on this device", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Chats")
            } footer: {
                Text("Temporary chats leave nothing on the device. When OCTO opens, chats older than the chosen time leave the device, except pinned ones: those of your account stay in your account, those written in OCTO are deleted.")
            }

            Section {
                Toggle(isOn: $settings.hidesWhenScreenCaptured) {
                    Label("Hide chats during screen recording", systemImage: "record.circle")
                }
                Toggle(isOn: $settings.hidesContentInAppSwitcher) {
                    Label("Hide content in the app switcher", systemImage: "rectangle.on.rectangle")
                }
            } header: {
                Text("Screen")
            } footer: {
                Text("OCTO covers your chats while the screen is recorded, mirrored or shared, and when it shows in the app switcher.")
            }

            Section {
                Toggle(isOn: $settings.copiesOnlyOnThisDevice) {
                    Label("Copy only on this device", systemImage: "doc.on.clipboard")
                }
                Picker(selection: $settings.clipboardExpiry) {
                    ForEach(ClipboardExpiry.allCases) { expiry in
                        Text(verbatim: expiry.title).tag(expiry)
                    }
                } label: {
                    Label("Clear copied text", systemImage: "timer")
                }
                Toggle(isOn: $settings.blocksThirdPartyKeyboards) {
                    Label("Block third-party keyboards", systemImage: "keyboard")
                }
            } header: {
                Text("Clipboard and keyboard")
            } footer: {
                Text("Text copied from OCTO doesn't reach your other Apple devices. A third-party keyboard can send what you type to its developer: blocking them takes effect the next time OCTO opens.")
            }

            Section {
                Toggle(isOn: $settings.removesLinkTrackers) {
                    Label("Remove trackers from links", systemImage: "link")
                }
                Toggle(isOn: $settings.checksForUpdates) {
                    Label("Check for updates", systemImage: "arrow.down.app")
                }
                NavigationLink(value: SettingsRoute.voice) {
                    LabeledContent {
                        Text(verbatim: settings.transcriptionEngine.title)
                    } label: {
                        Label("Dictation", systemImage: "mic")
                    }
                }
            } header: {
                Text("Network")
            } footer: {
                Text("Links of replies open, copy and share without their tracking parameters, such as utm_source=chatgpt.com. The update check asks GitHub for the latest release, without any identifier. Dictation with ChatGPT sends your recording to OpenAI; dictation on the device sends nothing.")
            }

            Section {
                NavigationLink(value: SettingsRoute.dataControls) {
                    Label("Data controls", systemImage: "hand.raised")
                }
                NavigationLink(value: SettingsRoute.ageVerification) {
                    Label("Age verification", systemImage: "checkmark.shield")
                }
            } header: {
                Text("Your ChatGPT account")
            }

            Section {
                if hosts.isEmpty {
                    Text("No request yet.")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(hosts) { host in
                    LabeledContent {
                        Text("\(host.requests) requests")
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text(verbatim: host.name)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: Self.symbol(for: host.name))
                        }
                    }
                }
            } header: {
                Text("Since OCTO opened")
            } footer: {
                Text("Every server OCTO has contacted since it opened. Counted on the device, never sent anywhere.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hosts = NetworkActivity.shared.hosts()
        }
        .detachedRefreshable {
            hosts = NetworkActivity.shared.hosts()
        }
    }

    private static func symbol(for host: String) -> String {
        if host.hasSuffix("chatgpt.com") { return "bubble.left.and.bubble.right" }
        if host.hasSuffix("openai.com") { return "person.badge.key" }
        if host.hasSuffix("github.com") { return "arrow.down.app" }
        return "network"
    }
}

extension ContactVisibility {
    var title: String {
        switch self {
        case .always: return String(localized: "Always shown")
        case .tapToReveal: return String(localized: "Tap to show")
        case .whileNotRecording: return String(localized: "Hidden while recording")
        case .never: return String(localized: "Never shown")
        }
    }
}

extension LocalRetention {
    var title: String {
        switch self {
        case .forever: return String(localized: "Always")
        case .oneDay: return String(localized: "1 day")
        case .oneWeek: return String(localized: "1 week")
        case .oneMonth: return String(localized: "1 month")
        }
    }
}

extension ClipboardExpiry {
    var title: String {
        switch self {
        case .never: return String(localized: "Never")
        case .oneMinute: return String(localized: "After 1 minute")
        case .fiveMinutes: return String(localized: "After 5 minutes")
        case .fifteenMinutes: return String(localized: "After 15 minutes")
        }
    }
}

extension TranscriptionEngine {
    var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .onDevice: return String(localized: "On this device")
        }
    }
}
