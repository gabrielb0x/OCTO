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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text(verbatim: "ChatGPT")
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
                }
                .controlSize(.extraLarge)
            }

            Text("Your chats and settings come from your ChatGPT account. Not affiliated with OpenAI.")
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
/// The text is laid out once per phrase: every frame only changes which letters are drawn,
/// so letters fade in and the dot glides along at the display's refresh rate.
struct TypingHeadline: View {
    let phrases: [String]
    let animated: Bool
    @State private var start = Date()

    var body: some View {
        Group {
            if animated, !phrases.isEmpty {
                TimelineView(.animation) { context in
                    let schedule = TypingSchedule(lengths: phrases.map(\.count))
                    let frame = schedule.frame(at: context.date.timeIntervalSince(start))
                    headline(phrases[frame.phraseIndex], visibleCharacters: frame.visibleCharacters)
                }
            } else {
                headline(phrases.first ?? "", visibleCharacters: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
    }

    private func headline(_ phrase: String, visibleCharacters: Double) -> some View {
        // A no-break space keeps the dot on the same line as the last word.
        let dot = Text(verbatim: "\u{00A0}●")
            .font(.system(size: 30))
            .customAttribute(TypingCursor())
        // Interpolated without a string literal, so no "%@%@" key lands in the string catalog.
        var content = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: 2)
        content.appendInterpolation(Text(verbatim: phrase))
        content.appendInterpolation(dot)
        return Text(LocalizedStringKey(stringInterpolation: content))
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .textRenderer(TypewriterRenderer(visibleCharacters: visibleCharacters))
            .accessibilityLabel(Text(verbatim: phrase))
    }
}

/// Marks the dot that follows the typed headline.
struct TypingCursor: TextAttribute {}

/// Draws the letters typed so far, each fading in, and moves the dot right after the last one.
struct TypewriterRenderer: TextRenderer {
    /// Letters shown; the fractional part is how far the next letter has appeared.
    var visibleCharacters: Double
    /// Letters over which a new letter fades in.
    var fadeLength = 1.5

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        var caret: CGPoint?
        var start: CGPoint?
        var cursorRuns: [Text.Layout.Run] = []

        for line in layout {
            for run in line {
                if run[TypingCursor.self] != nil {
                    cursorRuns.append(run)
                    continue
                }
                for slice in run {
                    let bounds = slice.typographicBounds
                    if start == nil {
                        start = CGPoint(x: bounds.rect.minX, y: bounds.origin.y)
                    }
                    let shown = visibleCharacters - Double(index)
                    if shown > 0 {
                        var letter = context
                        letter.opacity = min(shown / fadeLength, 1)
                        letter.draw(slice)
                        caret = CGPoint(x: bounds.rect.minX + bounds.width * min(shown, 1), y: bounds.origin.y)
                    }
                    index += 1
                }
            }
        }

        let target = caret ?? start
        for run in cursorRuns {
            let bounds = run.typographicBounds
            var cursor = context
            if let target {
                cursor.translateBy(x: target.x - bounds.rect.minX, y: target.y - bounds.origin.y)
            }
            cursor.draw(run)
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
