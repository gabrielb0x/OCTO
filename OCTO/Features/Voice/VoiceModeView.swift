import OCTOCore
import SwiftUI

/// ChatGPT-style voice mode: talk, hear the reply read aloud, talk again.
struct VoiceModeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: ChatSession
    @State private var voice = VoiceConversation()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Text(verbatim: session.model.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 12)

                Spacer()

                VoiceOrb(
                    level: voice.level,
                    isSpeaking: voice.phase == .speaking,
                    isThinking: voice.phase == .thinking,
                    animated: !reduceMotion && !app.isDemo
                )
                .frame(width: 250, height: 250)
                .contentShape(Circle())
                .onTapGesture {
                    voice.interrupt()
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(verbatim: voice.statusTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                    Text(verbatim: voice.transcript)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .opacity(voice.transcript.isEmpty ? 0 : 1)
                }
                .frame(minHeight: 110, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .animation(.smooth, value: voice.statusTitle)

                Spacer()

                GlassEffectContainer(spacing: 28) {
                    HStack(spacing: 28) {
                        Button {
                            voice.toggleMute()
                        } label: {
                            Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(voice.isMuted ? Theme.danger : Theme.primaryText)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 68, height: 68)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(voice.isMuted ? Text("Unmute") : Text("Mute"))

                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 68, height: 68)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(Theme.danger.opacity(0.4)).interactive(), in: .circle)
                        .accessibilityLabel(Text("End voice mode"))
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .task {
            await voice.start(session: session, app: app)
        }
        .onDisappear {
            voice.stop()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: voice.phase) { _, _ in
            app.settings.hapticsEnabled
        }
    }

    private func close() {
        voice.stop()
        dismiss()
    }
}

/// Blue sky orb like ChatGPT's voice mode, swelling with the microphone level.
struct VoiceOrb: View {
    var level: Double
    var isSpeaking: Bool
    var isThinking: Bool
    var animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            orb(time: time)
        }
    }

    private func orb(time: Double) -> some View {
        let drift = Float(sin(time * 0.8)) * 0.1
        let sway = Float(cos(time * 0.6)) * 0.08
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + sway), SIMD2(0.5 + drift, 0.5 - sway), SIMD2(1, 0.5 + drift),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
        let deep = Color(red: 0.28, green: 0.40, blue: 1.0)
        let sky = Color(red: 0.46, green: 0.62, blue: 1.0)
        let haze = Color(red: 0.80, green: 0.87, blue: 1.0)
        let colors: [Color] = [
            deep, deep, sky,
            sky, haze, sky,
            .white, haze, .white,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .clipShape(Circle())
            .scaleEffect(scale(time: time))
            .shadow(color: sky.opacity(0.35), radius: 40)
    }

    private func scale(time: Double) -> CGFloat {
        if isSpeaking {
            return 1 + 0.05 * CGFloat(sin(time * 7) * 0.5 + 0.5)
        }
        if isThinking {
            return 0.92 + 0.03 * CGFloat(sin(time * 2))
        }
        return 1 + 0.12 * CGFloat(min(max(level, 0), 1))
    }
}
