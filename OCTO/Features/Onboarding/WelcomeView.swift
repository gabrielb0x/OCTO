import OCTOCore
import SwiftUI
import UIKit

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showDeviceCode = false
    @State private var showAPIKey = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            WelcomeBackdrop(animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                VStack(spacing: 16) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.3), radius: 28)
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)
                    Text(verbatim: "OCTO")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .tracking(3)
                    Text("Your ChatGPT, open source and private.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                FeatureHighlights()
                    .padding(.top, 30)
                    .padding(.horizontal, 16)

                Spacer(minLength: 32)

                VStack(spacing: 12) {
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
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.white).interactive(), in: .capsule)
                    .disabled(isSigningIn)

                    Button {
                        showDeviceCode = true
                    } label: {
                        Text("Sign in with a code")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button {
                        showAPIKey = true
                    } label: {
                        Text("Use an OpenAI API key")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)

                Text("Not affiliated with OpenAI. Your chats stay on this device.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: 520)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.35)) {
                appeared = true
            }
        }
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

private struct FeatureHighlights: View {
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pills }
                VStack(spacing: 8) { pills }
            }
        }
    }

    @ViewBuilder
    private var pills: some View {
        pill("lock.shield.fill", "No telemetry")
        pill("chevron.left.forwardslash.chevron.right", "Open source")
        pill("bolt.fill", "Direct to OpenAI")
    }

    private func pill(_ systemImage: String, _ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
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
                        .foregroundStyle(Theme.accent)
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
                    Button("Cancel") { dismiss() }
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
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
                }
            }
            .navigationTitle("OpenAI API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isValidating {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !isValidating, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
