import OCTOCore
import SwiftUI

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
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
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
            .fill(Color.white)
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

struct AccountAvatar: View {
    let account: Account?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.36, green: 0.46, blue: 1.0), Color(red: 0.64, green: 0.38, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            if account?.method == .apiKey {
                Image(systemName: "key.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
            } else {
                Text(verbatim: initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = account?.email?.first else { return "O" }
        return String(first).uppercased()
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
