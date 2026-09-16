import OCTOCore
import SwiftUI

/// Every device signed into the ChatGPT account, and how the account is protected. Read from the
/// account like ChatGPT's own "Devices" screen: OCTO shows them so you can spot a sign-in that
/// isn't yours, and sends you to ChatGPT to sign one out.
struct DevicesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    private var account: AccountStore { app.account }

    var body: some View {
        List {
            switch account.devicesState {
            case .loading where account.devices == nil:
                loadingSection
            case .failed(let message) where account.devices == nil:
                failureSection(message)
            default:
                devicesSection
                protectionSection
                manageSection
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .detachedRefreshable {
            await account.refreshDevices()
        }
        .task {
            await account.refreshDevices(ifOlderThan: 60)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var devicesSection: some View {
        let devices = account.devices?.devices ?? []
        Section {
            if devices.isEmpty {
                Text("No device is signed into your account.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(devices) { device in
                    DeviceRow(device: device)
                }
            }
        } header: {
            // Not "Signed in": that string is already the account's last sign-in date elsewhere.
            Text("Signed-in devices")
        } footer: {
            Text("Every device signed into your ChatGPT account, wherever it last connected from. If one isn't yours, change your password in ChatGPT: it signs the others out.")
        }
    }

    @ViewBuilder
    private var protectionSection: some View {
        if let security = account.security, !security.isEmpty {
            Section {
                if let enabled = security.multiFactorEnabled {
                    LabeledContent {
                        Text(enabled ? LocalizedStringKey("On") : LocalizedStringKey("Off"))
                            .foregroundStyle(enabled ? Theme.success : Theme.warning)
                    } label: {
                        Label("Multi-factor authentication", systemImage: "key")
                    }
                }
                ForEach(security.factors) { factor in
                    LabeledContent {
                        if let name = factor.name {
                            Text(verbatim: name)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    } label: {
                        Label(Self.title(for: factor.kind), systemImage: Self.systemImage(for: factor.kind))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .font(.subheadline)
                }
                if let mode = security.loginNotificationMode {
                    LabeledContent {
                        Text(Self.title(forAlerts: mode))
                    } label: {
                        Label("Sign-in alerts", systemImage: "bell.badge")
                    }
                }
                if let advanced = security.advancedProtectionEnabled {
                    LabeledContent {
                        Text(advanced ? LocalizedStringKey("On") : LocalizedStringKey("Off"))
                    } label: {
                        Label("Advanced protection", systemImage: "lock.shield")
                    }
                }
            } header: {
                Text("Protection")
            } footer: {
                Text("How your ChatGPT account proves it's you. These are changed in ChatGPT.")
            }
        }
    }

    private var manageSection: some View {
        Section {
            Button {
                if let url = URL(string: "https://chatgpt.com/#settings/Security") {
                    openURL(url)
                }
            } label: {
                Label("Manage in ChatGPT", systemImage: "arrow.up.right.square")
            }
            .foregroundStyle(Theme.primaryText)
        } footer: {
            if case .failed(let message) = account.devicesState {
                Text(verbatim: message)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                Button("Try again") {
                    Task { await account.refreshDevices() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }

    // MARK: Labels

    static func title(for kind: SecurityFactor.Kind) -> LocalizedStringKey {
        switch kind {
        case .authenticator: return "Authenticator app"
        case .passkey: return "Passkey"
        case .sms: return "Text message"
        case .push: return "Push notification"
        }
    }

    static func systemImage(for kind: SecurityFactor.Kind) -> String {
        switch kind {
        case .authenticator: return "123.rectangle"
        case .passkey: return "person.badge.key"
        case .sms: return "message"
        case .push: return "bell"
        }
    }

    static func title(forAlerts mode: String) -> LocalizedStringKey {
        switch mode.lowercased() {
        case "new_devices": return "New devices"
        case "all", "always": return "Every sign-in"
        case "off", "none", "disabled": return "Off"
        default: return LocalizedStringKey(mode.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }
}

/// One device of the account: what it is, where it last signed in from, and with which apps.
struct DeviceRow: View {
    let device: AccountDevice

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.systemImage(for: device))
                .font(.title3)
                .foregroundStyle(device.isCurrentDevice ? Theme.success : Theme.secondaryText)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: device.summary?.isEmpty == false ? device.summary! : device.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if device.isCurrentDevice {
                        Text("This device")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.15), in: .capsule)
                    }
                }
                if let location = device.location() {
                    Text(verbatim: location)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let lastSignedInAt = device.lastSignedInAt {
                    Text("Last used \(lastSignedInAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                if !device.apps.isEmpty {
                    Text(verbatim: device.apps.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// The device as iOS would draw it. The platform says what it is; on iOS the name tells an iPad apart.
    static func systemImage(for device: AccountDevice) -> String {
        switch device.platform {
        case "ios", "ipados":
            return device.name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone"
        case "macos":
            return "laptopcomputer"
        case "windows":
            return "pc"
        case "linux":
            return "desktopcomputer"
        case "android":
            return "candybarphone"
        default:
            return "display"
        }
    }
}
