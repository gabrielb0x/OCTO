import OCTOCore
import SwiftUI
import UIKit

/// Sign-in screen modeled on ChatGPT's: a typed headline and stacked Liquid Glass buttons.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showDeviceCode = false
    @State private var showAPIKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text(verbatim: "OCTO")
                    .font(.title3.weight(.bold))
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.top, 8)

            Spacer(minLength: 24)

            TypingHeadline(phrases: Self.phrases, animated: !reduceMotion && !app.isDemo)

            Spacer(minLength: 24)

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    Button(action: signIn) {
                        HStack(spacing: 10) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Continue with ChatGPT")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .disabled(isSigningIn)

                    Button {
                        showDeviceCode = true
                    } label: {
                        Label("Sign in with a code", systemImage: "number")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button {
                        showAPIKey = true
                    } label: {
                        Label("Use an OpenAI API key", systemImage: "key")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.extraLarge)
            }

            Text("Not affiliated with OpenAI. Your chats stay on this device.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .alert("Sign-in failed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showDeviceCode) {
            DeviceCodeSheet()
        }
        .sheet(isPresented: $showAPIKey) {
            APIKeySheet()
        }
    }

    private static var phrases: [String] {
        [
            String(localized: "Let's brainstorm"),
            String(localized: "Let's write together"),
            String(localized: "Let's plan a trip"),
            String(localized: "Let's debug some code"),
            String(localized: "Let's learn something new"),
        ]
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func signIn() {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await app.auth.signInWithChatGPT()
                await app.didSignIn()
            } catch AuthError.cancelled {
                // The user closed the sheet.
            } catch {
                errorMessage = ChatSession.describe(error)
            }
        }
    }
}

/// Large headline typed and erased letter by letter, ending with ChatGPT's white dot.
struct TypingHeadline: View {
    let phrases: [String]
    let animated: Bool
    @State private var phraseIndex = 0
    @State private var typedCount = Int.max

    var body: some View {
        let phrase = phrases.isEmpty ? "" : phrases[phraseIndex % phrases.count]
        Text(headline(String(phrase.prefix(typedCount))))
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .accessibilityLabel(Text(verbatim: phrase))
            .task(id: animated) {
                guard animated, !phrases.isEmpty else { return }
                await typeForever()
            }
    }

    private func headline(_ typed: String) -> AttributedString {
        var text = AttributedString(typed)
        var dot = AttributedString(" ●")
        dot.font = .system(size: 30)
        text.append(dot)
        return text
    }

    private func typeForever() async {
        while !Task.isCancelled {
            let phrase = phrases[phraseIndex % phrases.count]
            for count in 0...phrase.count {
                typedCount = count
                try? await Task.sleep(for: .milliseconds(55))
            }
            try? await Task.sleep(for: .seconds(1.6))
            for count in stride(from: phrase.count, through: 0, by: -1) {
                typedCount = count
                try? await Task.sleep(for: .milliseconds(22))
            }
            phraseIndex += 1
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

struct DeviceCodeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var challenge: DeviceCodeChallenge?
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "rectangle.and.hand.point.up.left.filled")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.top, 8)

                    Text("Open the page below on any device, sign in to ChatGPT and enter this code.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)

                    if let challenge {
                        codeCard(challenge)
                    } else if let errorMessage {
                        VStack(spacing: 14) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.center)
                            Button("Try again") { attempt += 1 }
                                .buttonStyle(.glass)
                        }
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .padding(.vertical, 30)
                    }

                    Text("If the page says codes are disabled, turn on device code authorization for Codex in ChatGPT → Settings → Security.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle("Sign in with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: attempt) {
            await run()
        }
    }

    private func codeCard(_ challenge: DeviceCodeChallenge) -> some View {
        VStack(spacing: 18) {
            Text(verbatim: challenge.userCode)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .tracking(2)
                .textSelection(.enabled)
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = challenge.userCode
                        copied = true
                    } label: {
                        Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy code"), systemImage: copied ? "checkmark" : "square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Button {
                        UIPasteboard.general.string = challenge.userCode
                        openURL(challenge.verificationURL)
                    } label: {
                        Label("Open page", systemImage: "safari")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .controlSize(.large)
                }
            }

            HStack(spacing: 10) {
                ProgressView()
                Text("Waiting for approval…")
                    .foregroundStyle(Theme.secondaryText)
            }
            .font(.subheadline)
        }
    }

    private func run() async {
        challenge = nil
        errorMessage = nil
        do {
            let challenge = try await app.auth.requestDeviceCode()
            self.challenge = challenge
            try await app.auth.completeDeviceCode(challenge)
            await app.didSignIn()
            dismiss()
        } catch is CancellationError {
            // Sheet dismissed.
        } catch {
            self.challenge = nil
            errorMessage = ChatSession.describe(error)
        }
    }
}

struct APIKeySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var hasKey: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(text: $key) {
                        Text(verbatim: "sk-…")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                } footer: {
                    Text("The key is stored in the iOS Keychain and only sent to api.openai.com. API usage is billed by OpenAI, separately from ChatGPT plans.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("Create an API key", systemImage: "arrow.up.right.square")
                    }
                    .foregroundStyle(Theme.primaryText)
                }
            }
            .navigationTitle("OpenAI API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isValidating {
                        ProgressView()
                    } else {
                        Button(action: save) {
                            Text("Save")
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .disabled(!hasKey)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !isValidating, hasKey else { return }
        isValidating = true
        errorMessage = nil
        Task {
            defer { isValidating = false }
            do {
                try await app.auth.signIn(apiKey: key)
                await app.didSignIn()
                dismiss()
            } catch {
                errorMessage = ChatSession.describe(error)
            }
        }
    }
}
