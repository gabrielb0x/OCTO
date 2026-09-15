import OCTOCore
import SwiftUI
import UIKit

/// How chats look: colors, text, and how replies appear.
struct AppearanceView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                ReplyPreview()
            } header: {
                Text("Preview")
            }

            Section {
                Picker(selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { choice in
                        Label {
                            Text(verbatim: choice.title)
                        } icon: {
                            if let swatch = settings.accentStyle(for: choice).swatch {
                                Image(uiImage: swatch)
                            }
                        }
                        .tag(choice)
                    }
                } label: {
                    Label("Accent color", systemImage: "paintpalette")
                }
                .pickerStyle(.navigationLink)
                if settings.accent == .custom {
                    ColorPicker(selection: customColor, supportsOpacity: false) {
                        Label("Your color", systemImage: "eyedropper")
                    }
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Colors your messages, the send button and the controls of the message bar.")
            }

            Section {
                Picker(selection: $settings.chatTextSize) {
                    ForEach(ChatTextSize.allCases) { size in
                        Text(verbatim: size.title).tag(size)
                    }
                } label: {
                    Label("Text size", systemImage: "textformat.size")
                }
                Picker(selection: $settings.chatFont) {
                    ForEach(ChatFont.allCases) { font in
                        Text(verbatim: font.title).tag(font)
                    }
                } label: {
                    Label("Font", systemImage: "textformat")
                }
                Toggle(isOn: $settings.wrapsCodeLines) {
                    Label("Wrap code lines", systemImage: "text.word.spacing")
                }
            } header: {
                Text("Chats")
            } footer: {
                Text("The size moves from the text size chosen in iOS, so accessibility sizes still apply.")
            }

            Section {
                Picker(selection: $settings.revealSpeed) {
                    ForEach(RevealSpeed.allCases) { speed in
                        Text(verbatim: speed.title).tag(speed)
                    }
                } label: {
                    Label("Reply animation", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Toggle(isOn: $settings.streamingHaptics) {
                    Label("Vibrate while ChatGPT writes", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                .disabled(!settings.hapticsEnabled)
            } header: {
                Text("Replies")
            } footer: {
                Text("The words of a reply appear one by one and fade in. Instant shows the text as soon as it arrives.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(hex: app.settings.customAccentHex) ?? .systemPurple) },
            set: { app.settings.customAccentHex = UIColor($0).hexString }
        )
    }
}

/// A short reply written with the chosen colors, text and animation.
private struct ReplyPreview: View {
    @Environment(AppModel.self) private var app
    @State private var reply: LiveReply?
    @State private var replays = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What is a black hole?")
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(app.settings.accentStyle.bubble, in: .rect(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)

            MarkdownView(text: MarkdownStreaming.closingOpenInlineMarkers(reply?.text ?? ""))
                .environment(\.streamingReveal, reply?.reveal)
                .frame(minHeight: 120, alignment: .topLeading)

            Button {
                replays += 1
            } label: {
                Label("Replay", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .chatTextStyle(size: app.settings.chatTextSize, font: app.settings.chatFont)
        .padding(.vertical, 6)
        .task(id: PreviewRun(replays: replays, speed: app.settings.revealSpeed)) {
            await play(speed: app.settings.revealSpeed)
        }
    }

    /// Streams a sample reply the way the network does, in small chunks.
    private func play(speed: RevealSpeed) async {
        let reply = LiveReply(messageID: UUID(), speed: speed)
        self.reply = reply
        reply.start()
        defer { reply.stop() }
        let sample = String(localized: "A **black hole** is a region of space where gravity is so strong that nothing can escape it, not even light. It forms when a very massive star collapses on itself.")
        var index = sample.startIndex
        while index < sample.endIndex {
            guard !Task.isCancelled else { return }
            let end = sample.index(index, offsetBy: 5, limitedBy: sample.endIndex) ?? sample.endIndex
            reply.receiveText(String(sample[index..<end]))
            index = end
            try? await Task.sleep(for: .milliseconds(25))
        }
        await reply.finishRevealing()
    }
}

private struct PreviewRun: Equatable {
    let replays: Int
    let speed: RevealSpeed
}

extension ChatTextSize {
    var title: String {
        switch self {
        case .small: return String(localized: "Small")
        case .standard: return String(localized: "Default")
        case .large: return String(localized: "Large")
        case .extraLarge: return String(localized: "Extra large")
        }
    }
}

extension ChatFont {
    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .rounded: return String(localized: "Rounded")
        case .serif: return String(localized: "Serif")
        case .monospaced: return String(localized: "Monospaced")
        }
    }
}

extension RevealSpeed {
    var title: String {
        switch self {
        case .slow: return String(localized: "Slow")
        case .normal: return String(localized: "Normal")
        case .fast: return String(localized: "Fast")
        case .instant: return String(localized: "speed.instant", defaultValue: "Instant")
        }
    }
}
