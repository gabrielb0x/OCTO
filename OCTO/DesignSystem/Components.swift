import OCTOCore
import SwiftUI

/// Round Liquid Glass button with an SF Symbol.
struct GlassIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 44
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(.white).interactive() : .regular.interactive(), in: .circle)
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

/// Animated dark mesh behind the onboarding glass.
struct WelcomeBackdrop: View {
    var animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let dx = Float(sin(time * 0.33)) * 0.14
            let dy = Float(cos(time * 0.27)) * 0.12
            let points: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.5 + dx, 0.42 + dy), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
            ]
            let colors: [Color] = [
                .black, Color(red: 0.06, green: 0.06, blue: 0.14), .black,
                Color(red: 0.03, green: 0.08, blue: 0.14), Color(red: 0.21, green: 0.16, blue: 0.44), Color(red: 0.04, green: 0.05, blue: 0.12),
                .black, Color(red: 0.05, green: 0.04, blue: 0.10), .black,
            ]
            MeshGradient(width: 3, height: 3, points: points, colors: colors)
        }
        .ignoresSafeArea()
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
