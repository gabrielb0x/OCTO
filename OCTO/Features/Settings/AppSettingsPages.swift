import AVFoundation
import OCTOCore
import SwiftUI
import UIKit

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
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
                Toggle(isOn: $settings.correctsSpelling) {
                    Label("Correct spelling automatically", systemImage: "textformat.abc.dottedunderline")
                }
                Toggle(isOn: $settings.sendsWithReturn) {
                    Label("Send with Return", systemImage: "return")
                }
            }

            Section {
                // The models Codex offers the account, which one new chats start with, and
                // what isn't included in the plan.
                NavigationLink(value: SettingsRoute.models) {
                    LabeledContent {
                        Text(verbatim: app.defaultModel.displayName)
                    } label: {
                        Label("Default model", systemImage: "cpu")
                    }
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
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
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

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                Toggle(isOn: repliesBinding) {
                    Label("Replies", systemImage: "bubble.left.and.text.bubble.right")
                }
                Toggle(isOn: $settings.showsNotificationPreviews) {
                    Label("Show previews", systemImage: "text.bubble")
                }
                .disabled(!settings.notifiesReplies)
            } footer: {
                Text("Get a notification when ChatGPT finishes a reply while OCTO is in the background. iOS lets a reply keep generating for about 30 seconds after you leave the app.")
            }

            if app.notifications.authorization == .denied {
                Section {
                    Label("Notifications are turned off for OCTO in iOS Settings.", systemImage: "bell.slash")
                        .foregroundStyle(Theme.warning)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.notifications.refreshAuthorization()
        }
    }

    /// Turning replies on asks iOS for permission first.
    private var repliesBinding: Binding<Bool> {
        Binding(
            get: { app.settings.notifiesReplies },
            set: { isOn in
                guard isOn else {
                    app.settings.notifiesReplies = false
                    return
                }
                Task {
                    var allowed = app.notifications.isAuthorized
                    if !allowed {
                        allowed = await app.notifications.requestAuthorization()
                    }
                    app.settings.notifiesReplies = allowed
                }
            }
        )
    }
}

struct VoiceSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [AVSpeechSynthesisVoice] = []
    /// What iOS says about dictation on the device, looked at again on the way back from Settings.
    @State private var dictationOnDevice: DictationAvailability = .available

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                Picker(selection: $settings.voiceIdentifier) {
                    Text("Automatic").tag(String?.none)
                    ForEach(voices, id: \.identifier) { voice in
                        Text(verbatim: title(of: voice)).tag(Optional(voice.identifier))
                    }
                } label: {
                    Label("Voice", systemImage: "person.wave.2")
                }
                .pickerStyle(.navigationLink)

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

                Button {
                    app.speech.speakSample(String(localized: "Hi! This is how I'll read ChatGPT's replies to you."), rate: settings.speechRate, voiceIdentifier: settings.voiceIdentifier)
                } label: {
                    Label("Listen", systemImage: "play.circle")
                }
                .foregroundStyle(Theme.primaryText)
            } header: {
                Text("Read aloud")
            } footer: {
                Text("OCTO reads replies with the voices of your device, without sending anything. More voices can be downloaded in iOS Settings → Accessibility → Spoken Content.")
            }

            Section {
                Picker(selection: $settings.voicePause) {
                    ForEach(VoicePause.allCases) { pause in
                        Text(verbatim: pause.title).tag(pause)
                    }
                } label: {
                    Label("Send after a pause of", systemImage: "timer")
                }
            } header: {
                Text("Voice mode")
            } footer: {
                Text("How long voice mode waits once you stop talking before it sends what you said.")
            }

            Section {
                Picker(selection: $settings.transcriptionEngine) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(verbatim: engine.title).tag(engine)
                    }
                } label: {
                    Label("Dictation", systemImage: "mic")
                }
                // Dictation turned off in iOS Settings stops the recognition of the device: better
                // said here than discovered when nothing gets written down.
                if !dictationOnDevice.isAvailable {
                    Label(Self.title(for: dictationOnDevice), systemImage: "mic.slash")
                        .foregroundStyle(Theme.warning)
                    if dictationOnDevice.isFixedInSystemSettings {
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Dictation")
            } footer: {
                Text(settings.transcriptionEngine == .chatGPT
                    ? LocalizedStringKey("Your recording is sent to ChatGPT, which writes it down like in its apps, then deleted from the device. If ChatGPT can't, the device transcribes it.")
                    : LocalizedStringKey("Apple's speech recognition writes as you speak, on the device, without sending anything."))
            }

            if let voiceName = app.account.settings?.voiceName, !voiceName.isEmpty {
                Section {
                    LabeledContent {
                        Text(verbatim: voiceName.capitalized)
                    } label: {
                        Label("ChatGPT voice", systemImage: "waveform")
                    }
                } footer: {
                    Text("The voice of your account in ChatGPT's own voice mode. OCTO speaks with the voices of your device.")
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            voices = Self.voicesForAppLanguage()
            dictationOnDevice = .current
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dictationOnDevice = .current
            }
        }
        .onDisappear {
            app.speech.stop()
        }
    }

    private static func title(for availability: DictationAvailability) -> LocalizedStringKey {
        switch availability {
        case .turnedOffOnDevice: return "Dictation is turned off on this iPhone"
        case .permissionDenied: return "Speech recognition is turned off for OCTO"
        case .unavailable, .available: return "Dictation on this device isn't available right now"
        }
    }

    private func title(of voice: AVSpeechSynthesisVoice) -> String {
        var parts = [voice.name]
        if let region = Locale.current.localizedString(forIdentifier: voice.language) {
            parts.append(region)
        }
        switch voice.quality {
        case .premium: parts.append(String(localized: "Premium"))
        case .enhanced: parts.append(String(localized: "Enhanced"))
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// Voices speaking the language of the app, best quality first.
    private static func voicesForAppLanguage() -> [AVSpeechSynthesisVoice] {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

extension VoicePause {
    var title: String {
        let seconds = self.seconds.formatted(.number.precision(.fractionLength(1)))
        switch self {
        case .short: return String(localized: "Short (\(seconds) s)")
        case .normal: return String(localized: "Normal (\(seconds) s)")
        case .long: return String(localized: "Long (\(seconds) s)")
        }
    }
}

struct ProtectionSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var isChangingLock = false

    var body: some View {
        @Bindable var settings = app.settings
        let biometry = AppProtection.biometry

        Form {
            Section {
                Toggle(isOn: lockBinding) {
                    Label(String(localized: "Lock with \(biometry.name)"), systemImage: biometry.systemImage)
                }
                .disabled(isChangingLock)
                if settings.locksWithFaceID {
                    Picker(selection: $settings.lockTimeout) {
                        ForEach(LockTimeout.allCases) { timeout in
                            Text(verbatim: timeout.title).tag(timeout)
                        }
                    } label: {
                        Label("Require", systemImage: "timer")
                    }
                }
            } footer: {
                Text("OCTO asks for \(biometry.name) or your passcode when it opens.")
            }

            if let error = app.protection.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
            }
            // Hiding the chats in the app switcher is in Privacy, with the other screen switches.
        }
        .navigationTitle("Protection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { app.settings.locksWithFaceID },
            set: { isOn in
                isChangingLock = true
                Task {
                    await app.protection.setLock(enabled: isOn)
                    isChangingLock = false
                }
            }
        )
    }
}

extension LockTimeout {
    var title: String {
        switch self {
        case .immediately: return String(localized: "Immediately")
        case .oneMinute: return String(localized: "After 1 minute")
        case .fiveMinutes: return String(localized: "After 5 minutes")
        case .fifteenMinutes: return String(localized: "After 15 minutes")
        case .oneHour: return String(localized: "After 1 hour")
        }
    }
}

struct SecuritySettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var session: CredentialVault.SessionInfo?
    @State private var isRefreshing = false

    var body: some View {
        Form {
            // The email address is on the first page of Settings, with the rest of the account.
            Section("Sign-in") {
                LabeledContent {
                    Text(signInMethodTitle)
                } label: {
                    Label("Method", systemImage: "person.badge.key")
                }
                if let signedInAt = app.auth.signedInAt {
                    LabeledContent {
                        Text(signedInAt, format: .dateTime.day().month().year().hour().minute())
                    } label: {
                        Label("Signed in", systemImage: "calendar")
                    }
                }
                if let mfaEnabled = app.account.profile?.mfaEnabled {
                    LabeledContent {
                        Text(mfaEnabled ? LocalizedStringKey("On") : LocalizedStringKey("Off"))
                    } label: {
                        Label("Multi-factor authentication", systemImage: "key")
                    }
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.devices) {
                    Label("Devices", systemImage: "laptopcomputer.and.iphone")
                }
            } footer: {
                Text("The devices signed into your ChatGPT account, where they last connected from, and how your account is protected.")
            }

            Section {
                if let session {
                    LabeledContent {
                        Text(session.lastRefresh, format: .relative(presentation: .named))
                    } label: {
                        Label("Last refreshed", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if let expiresAt = session.accessTokenExpiresAt {
                        LabeledContent {
                            Text(expiresAt, format: .dateTime.day().month().hour().minute())
                        } label: {
                            Label("Access expires", systemImage: "hourglass")
                        }
                    }
                }
                Button(action: refresh) {
                    HStack {
                        Label("Refresh session", systemImage: "arrow.clockwise")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isRefreshing)
            } header: {
                Text("Session")
            } footer: {
                // Signing out is at the bottom of the first page of Settings, as in the ChatGPT app.
                Text("Your sign-in tokens stay in the keychain of this device and are refreshed automatically. Signing out, at the bottom of Settings, revokes the session of this device; to sign out everywhere, use ChatGPT.")
            }
        }
        .navigationTitle("Security and login")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            session = await app.auth.vault.sessionInfo()
        }
    }

    private var signInMethodTitle: LocalizedStringKey {
        switch app.auth.signInMethod {
        case .browser?: return "ChatGPT in the browser"
        case .deviceCode?: return "Code on another device"
        case nil: return "ChatGPT"
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await app.refreshSession()
            session = await app.auth.vault.sessionInfo()
            isRefreshing = false
        }
    }
}

struct StorageSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var usage: StorageUsage?
    @State private var confirmRemoval = false

    var body: some View {
        Form {
            Section {
                if let usage {
                    usageBar(usage)
                    usageRow("Chats", color: Theme.link, bytes: usage.chatsBytes, detail: String(localized: "\(app.store.summaries.count) chats"))
                    usageRow("Attachments", color: Theme.warning, bytes: usage.attachmentsBytes, detail: String(localized: "\(usage.attachmentFiles) files"))
                    usageRow("Account data", color: Theme.success, bytes: usage.accountBytes, detail: nil)
                    if let free = DeviceInfo.freeDiskSpace {
                        LabeledContent {
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                        } label: {
                            Text("Available on this device")
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } footer: {
                Text("Chats from your account are kept on this device so they open instantly and offline.")
            }

            if let storage = app.account.fileStorage {
                Section {
                    accountStorageBar(storage)
                    ForEach(storage.byFileType) { bucket in
                        LabeledContent {
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: bucket.bytes, countStyle: .file))
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Self.title(forFileType: bucket.key))
                                    if let count = bucket.count, count > 0 {
                                        Text("\(count) files")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                }
                            } icon: {
                                Image(systemName: Self.systemImage(forFileType: bucket.key))
                            }
                        }
                    }
                } header: {
                    Text("In your ChatGPT account")
                } footer: {
                    Text("The photos and files of your chats, kept by ChatGPT. They stay in your account; this is the room they take there.")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmRemoval = true
                } label: {
                    DestructiveLabel(title: "Remove downloaded chats", systemImage: "arrow.down.circle.dotted")
                }
                .destructiveRow()
            } footer: {
                Text("Frees the space of chats downloaded from your account. They stay in your history and download again when you open them. Chats continued in OCTO are kept.")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            await app.account.refreshFileStorage(ifOlderThan: 300)
        }
        .confirmationDialog("Remove downloaded chats?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: removeDownloads)
        }
    }

    /// What ChatGPT keeps for the account, out of the room its plan gives it.
    private func accountStorageBar(_ storage: AccountFileStorage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: ByteCountFormatter.string(fromByteCount: storage.usedBytes, countStyle: .file))
                    .font(.title2.weight(.semibold))
                if let allowed = storage.allowedBytes {
                    Text("of \(ByteCountFormatter.string(fromByteCount: allowed, countStyle: .file))")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if let fraction = storage.usedFraction {
                ProgressView(value: fraction)
                    .tint(storage.isOverLimit || fraction >= 0.9 ? Theme.danger : Theme.link)
            }
        }
        .padding(.vertical, 6)
    }

    static func title(forFileType key: String) -> LocalizedStringKey {
        switch key {
        case "image": return "Images"
        case "text": return "Text files"
        case "audio": return "Audio"
        case "video": return "Video"
        case "other": return "Other files"
        default: return LocalizedStringKey(key.capitalized)
        }
    }

    static func systemImage(forFileType key: String) -> String {
        switch key {
        case "image": return "photo"
        case "text": return "doc.text"
        case "audio": return "waveform"
        case "video": return "video"
        default: return "doc"
        }
    }

    private func usageBar(_ usage: StorageUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: ByteCountFormatter.string(fromByteCount: usage.totalBytes, countStyle: .file))
                    .font(.title2.weight(.semibold))
                Text("used by OCTO")
                    .foregroundStyle(Theme.secondaryText)
            }
            GeometryReader { proxy in
                let total = max(Double(usage.totalBytes), 1)
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.link)
                        .frame(width: proxy.size.width * Double(usage.chatsBytes) / total)
                    Rectangle()
                        .fill(Theme.warning)
                        .frame(width: proxy.size.width * Double(usage.attachmentsBytes) / total)
                    Rectangle()
                        .fill(Theme.success)
                        .frame(width: proxy.size.width * Double(usage.accountBytes) / total)
                }
            }
            .frame(height: 10)
            .background(Theme.surfaceElevated)
            .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }

    private func usageRow(_ title: LocalizedStringKey, color: Color, bytes: Int64, detail: String?) -> some View {
        LabeledContent {
            Text(verbatim: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private func load() async {
        usage = await app.store.storageUsage(accountDirectory: app.account.cache.directory)
    }

    private func removeDownloads() {
        let count = app.store.removeDownloadedCopies()
        app.toasts.show(String(localized: "\(count) downloaded chats removed"))
        Task { await load() }
    }
}
