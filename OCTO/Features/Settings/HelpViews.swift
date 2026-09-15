import OCTOCore
import SwiftUI
import UIKit

/// Prefills a GitHub issue with the problem and, if allowed, non-personal device details.
struct ReportProblemView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var title = ""
    @State private var details = ""
    @State private var includesDeviceDetails = true
    @State private var includesLog = false

    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                ZStack(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Describe what happened and what you expected.")
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $details)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                }
            } header: {
                Text("What happened?")
            }

            Section {
                Toggle(isOn: $includesDeviceDetails) {
                    Label("Include device details", systemImage: "iphone")
                }
                if app.developer.isEnabled {
                    Toggle(isOn: $includesLog) {
                        Label("Include the developer log", systemImage: "list.bullet.rectangle")
                    }
                }
            } footer: {
                Text("Device details are the versions of OCTO and iOS, the device model and the language. Nothing about your account or your chats is included.")
            }

            Section {
                Button(action: openIssue) {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                }
                Button(action: copyReport) {
                    Label("Copy the report", systemImage: "doc.on.doc")
                }
            } footer: {
                Text("The report opens as a new issue on OCTO's GitHub page, where you can check it before sending it. A GitHub account is needed.")
            }
            .foregroundStyle(Theme.primaryText)
            .disabled(isEmpty)
        }
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reportText: String {
        IssueReport.body(
            description: details,
            diagnostics: includesDeviceDetails ? DeviceInfo.diagnostics() : [],
            log: includesLog ? app.developer.console.eventsText(limit: 60) : nil
        )
    }

    private var issueTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bug report" : trimmed
    }

    private func openIssue() {
        openURL(IssueReport.newIssueURL(repository: AppInfo.repositoryURL, title: issueTitle, body: reportText))
    }

    private func copyReport() {
        Clipboard.copy("# \(issueTitle)\n\n\(reportText)", settings: app.settings, cleansLinks: false)
        app.toasts.show(String(localized: "Report copied"))
    }
}

/// Answers to common questions, and where to find more help.
struct HelpCenterView: View {
    var body: some View {
        List {
            Section("Frequently asked questions") {
                QuestionRow(
                    question: "Why aren't my messages on chatgpt.com?",
                    answer: "OCTO shows the chats of your account, but its replies are generated through the Codex backend of your plan. The messages you write in OCTO stay on this device, and a note shows where they start in a chat from your account."
                )
                QuestionRow(
                    question: "What counts toward my limits?",
                    answer: "Messages sent from OCTO count toward the Codex usage limits of your ChatGPT plan. You can follow them in Settings → Subscription."
                )
                QuestionRow(
                    question: "Why can't I choose the model?",
                    answer: "Like in ChatGPT, choosing the model needs a subscription. On the free plan, ChatGPT uses the model available for you."
                )
                QuestionRow(
                    question: "Does OCTO collect my data?",
                    answer: "No. OCTO has no telemetry, analytics or third-party SDK. Requests go straight from your device to OpenAI, and to GitHub to look for updates if you allow it. Your sign-in tokens stay in the iOS keychain, and Settings → Privacy lists every server OCTO contacted."
                )
                QuestionRow(
                    question: "How do I update OCTO?",
                    answer: "OCTO tells you when a new version is published on GitHub. Install its IPA with AltStore, SideStore or Sideloadly over the current app: your chats and settings stay."
                )
                QuestionRow(
                    question: "My chats don't load",
                    answer: "Pull down on the chat list to try again. If it keeps failing, turn on developer mode by tapping the build number 8 times in About: the network log shows the exact error."
                )
            }

            Section("Links") {
                LinkRow(title: "OCTO on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: AppInfo.repositoryURL)
                LinkRow(title: "OpenAI Help Center", systemImage: "questionmark.circle", url: URL(string: "https://help.openai.com")!)
                LinkRow(title: "OpenAI status", systemImage: "waveform.path.ecg", url: URL(string: "https://status.openai.com")!)
            }
        }
        .navigationTitle("Help center")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuestionRow: View {
    let question: LocalizedStringKey
    let answer: LocalizedStringKey
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .padding(.vertical, 4)
        } label: {
            Text(question)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.primaryText)
        }
    }
}

/// A link that opens in the browser, with an arrow.
struct LinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .foregroundStyle(Theme.primaryText)
    }
}

/// About OCTO. Tapping the version shows what's new; tapping the build eight times in a row
/// turns on developer mode.
struct AboutView: View {
    @Environment(AppModel.self) private var app
    @State private var unlock = DeveloperUnlock()
    @State private var showsWhatsNew = false
    @State private var buildTaps = 0

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 88, height: 88)
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                    VStack(spacing: 4) {
                        Text(verbatim: "OCTO")
                            .font(.title2.weight(.bold))
                        Text("An open-source ChatGPT client for iOS")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    showsWhatsNew = true
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(verbatim: AppInfo.version)
                            Image(systemName: "sparkles")
                                .font(.footnote)
                        }
                    } label: {
                        Label("Version", systemImage: "info.circle")
                    }
                }
                Button(action: tapBuild) {
                    LabeledContent {
                        Text(verbatim: AppInfo.build)
                    } label: {
                        Label("Build", systemImage: "hammer")
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: buildTaps) { _, _ in
                    app.settings.hapticsEnabled
                }
            } footer: {
                Text("Tap the version to see what's new.")
            }
            .foregroundStyle(Theme.primaryText)

            UpdateStatusSection()

            Section {
                LinkRow(title: "Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: AppInfo.repositoryURL)
                LinkRow(title: "Changelog", systemImage: "clock.arrow.circlepath", url: AppInfo.repositoryURL.appendingPathComponent("blob/main/CHANGELOG.md"))
                LinkRow(title: "MIT license", systemImage: "doc.text", url: AppInfo.repositoryURL.appendingPathComponent("blob/main/LICENSE"))
                Label("No telemetry, no analytics, no third-party SDKs.", systemImage: "lock.shield")
                    .foregroundStyle(Theme.secondaryText)
            } footer: {
                Text("OCTO is an independent open-source project, not affiliated with or endorsed by OpenAI. ChatGPT is a trademark of OpenAI.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView(notes: ReleaseNotes.current)
        }
    }

    private func tapBuild() {
        buildTaps += 1
        switch unlock.registerTap() {
        case .unlocked:
            if app.developer.isEnabled {
                app.toasts.show(String(localized: "Developer mode is already on"), style: .info, systemImage: "hammer.fill")
            } else {
                app.developer.isEnabled = true
                DevLog.log("developer", "Developer mode turned on")
                app.toasts.show(String(localized: "Developer mode is on"), systemImage: "hammer.fill")
            }
        case .counting(let remaining):
            guard remaining <= 4, !app.developer.isEnabled else { return }
            app.toasts.show(String(localized: "\(remaining) more taps to turn on developer mode"), style: .info, systemImage: "hammer", duration: 1.4)
        }
    }
}
