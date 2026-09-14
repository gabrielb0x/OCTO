import OCTOCore
import SwiftUI

/// OCTO's dark palette, modeled on the ChatGPT iOS app: a black canvas, monochrome text
/// and Liquid Glass controls floating on top.
enum Theme {
    static let background = Color.black
    static let sidebarBackground = Color(white: 0.07)
    static let surface = Color(white: 0.11)
    static let surfaceElevated = Color(white: 0.16)
    static let userBubble = Color(white: 0.17)
    static let separator = Color.white.opacity(0.1)
    static let selection = Color.white.opacity(0.1)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let tertiaryText = Color.white.opacity(0.4)

    static let accent = Color.white
    static let link = Color(red: 0.49, green: 0.67, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let success = Color(red: 0.36, green: 0.84, blue: 0.55)

    static let messageSpacing: CGFloat = 28
    static let contentMaxWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 20

    static func syntaxColor(_ kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .plain: return Color.white.opacity(0.88)
        case .keyword: return Color(red: 1.0, green: 0.48, blue: 0.70)
        case .string: return Color(red: 0.99, green: 0.53, blue: 0.43)
        case .number: return Color(red: 0.85, green: 0.79, blue: 0.49)
        case .comment: return Color(red: 0.47, green: 0.53, blue: 0.59)
        case .type: return Color(red: 0.41, green: 0.85, blue: 1.0)
        case .function: return Color(red: 0.51, green: 0.83, blue: 0.72)
        case .property: return Color(red: 0.70, green: 0.60, blue: 1.0)
        case .attribute: return Color(red: 0.93, green: 0.65, blue: 0.42)
        }
    }
}

extension View {
    /// Constrains reading width on iPad and landscape while staying centered.
    func readableWidth() -> some View {
        frame(maxWidth: Theme.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
