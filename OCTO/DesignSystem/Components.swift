import OCTOCore
import SwiftUI
import UIKit

/// Round Liquid Glass button with an SF Symbol, for icon-only controls outside toolbars.
struct GlassIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
    }
}

/// Moving highlight used for "Thinking…" style status labels.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, Theme.primaryText.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: phase * proxy.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

/// ChatGPT-style breathing dot shown while waiting for the first token.
struct PulsingDot: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(Theme.primaryText)
            .frame(width: 13, height: 13)
            .scaleEffect(expanded ? 1 : 0.65)
            .opacity(expanded ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
            .accessibilityLabel(Text("Generating a response"))
    }
}

/// The profile picture of the ChatGPT account, or the account's initial on a gradient.
struct AccountAvatar: View {
    let name: String?
    let email: String?
    let image: UIImage?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.46, blue: 1.0), Color(red: 0.64, green: 0.38, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(verbatim: initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        for source in [name, email] {
            if let letter = source?.first(where: { $0.isLetter || $0.isNumber }) {
                return String(letter).uppercased()
            }
        }
        return "C"
    }
}

/// A settings page for something only the ChatGPT apps can do: what it is, and a way there.
struct ChatGPTOnlyPage: View {
    let title: LocalizedStringKey
    let systemImage: String
    let summary: LocalizedStringKey
    let details: LocalizedStringKey
    var link: URL = URL(string: "https://chatgpt.com/#settings")!
    var linkTitle: LocalizedStringKey = "Open ChatGPT settings"
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 76, height: 76)
                        .glassEffect(.regular, in: .circle)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    openURL(link)
                } label: {
                    Label(linkTitle, systemImage: "arrow.up.right.square")
                }
                .foregroundStyle(Theme.primaryText)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum ReasoningEffortLabel {
    static func title(_ effort: String) -> String {
        switch effort {
        case "none": return String(localized: "Instant")
        case "minimal": return String(localized: "Minimal")
        case "low": return String(localized: "Light")
        case "medium": return String(localized: "Standard")
        case "high": return String(localized: "Extended")
        case "xhigh": return String(localized: "Heavy")
        case "max": return String(localized: "Max")
        case "ultra": return String(localized: "Ultra")
        case "persistent": return String(localized: "Persistent")
        default: return effort.capitalized
        }
    }

    static func systemImage(_ effort: String) -> String {
        switch ReasoningEffortScale.rank(effort) {
        case 0...1: return "hare"
        case 2: return "gauge.with.dots.needle.33percent"
        case 3: return "gauge.with.dots.needle.50percent"
        case 4: return "gauge.with.dots.needle.67percent"
        default: return "brain.head.profile"
        }
    }
}
