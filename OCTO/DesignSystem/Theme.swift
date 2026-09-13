import OCTOCore
import SwiftUI

/// OCTO's dark palette: a near-black canvas with Liquid Glass controls on top.
enum Theme {
    static let background = Color(red: 0.020, green: 0.020, blue: 0.024)
    static let sidebarBackground = Color(red: 0.047, green: 0.047, blue: 0.055)
    static let surface = Color(white: 0.105)
    static let surfaceElevated = Color(white: 0.15)
    static let userBubble = Color(white: 0.165)
    static let separator = Color.white.opacity(0.08)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    static let accent = Color.accentColor
    static let link = Color(red: 0.55, green: 0.69, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let success = Color(red: 0.36, green: 0.84, blue: 0.55)

    static let messageSpacing: CGFloat = 26
    static let contentMaxWidth: CGFloat = 780
    static let horizontalPadding: CGFloat = 18

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
