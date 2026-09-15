import OCTOCore
import SwiftUI
import UIKit

/// OCTO's palette, modeled on the ChatGPT iOS app: a black (or white) canvas, monochrome text
/// and Liquid Glass controls floating on top. Every color follows the light or dark appearance.
enum Theme {
    static let background = dynamic(light: .white, dark: .black)
    static let sidebarBackground = dynamic(light: UIColor(white: 0.975, alpha: 1), dark: UIColor(white: 0.07, alpha: 1))
    static let surface = dynamic(light: UIColor(white: 0.95, alpha: 1), dark: UIColor(white: 0.11, alpha: 1))
    static let surfaceElevated = dynamic(light: UIColor(white: 0.91, alpha: 1), dark: UIColor(white: 0.16, alpha: 1))
    static let userBubble = dynamic(light: UIColor(white: 0.94, alpha: 1), dark: UIColor(white: 0.17, alpha: 1))
    static let separator = dynamic(light: UIColor(white: 0, alpha: 0.1), dark: UIColor(white: 1, alpha: 0.1))
    static let selection = dynamic(light: UIColor(white: 0, alpha: 0.06), dark: UIColor(white: 1, alpha: 0.1))

    static let primaryText = dynamic(light: UIColor(white: 0.05, alpha: 1), dark: .white)
    static let secondaryText = dynamic(light: UIColor(white: 0, alpha: 0.58), dark: UIColor(white: 1, alpha: 0.6))
    static let tertiaryText = dynamic(light: UIColor(white: 0, alpha: 0.38), dark: UIColor(white: 1, alpha: 0.4))

    static let accent = primaryText
    /// Fill of prominent buttons such as Send: white in dark mode, black in light mode.
    static let prominentFill = dynamic(light: UIColor(white: 0.05, alpha: 1), dark: .white)
    /// Content drawn on `prominentFill`.
    static let onProminent = dynamic(light: .white, dark: .black)
    static let link = dynamic(light: UIColor(red: 0.16, green: 0.39, blue: 0.85, alpha: 1), dark: UIColor(red: 0.49, green: 0.67, blue: 1.0, alpha: 1))
    static let danger = dynamic(light: UIColor(red: 0.86, green: 0.2, blue: 0.18, alpha: 1), dark: UIColor(red: 1.0, green: 0.42, blue: 0.40, alpha: 1))
    static let success = dynamic(light: UIColor(red: 0.1, green: 0.6, blue: 0.32, alpha: 1), dark: UIColor(red: 0.36, green: 0.84, blue: 0.55, alpha: 1))
    static let warning = dynamic(light: UIColor(red: 0.85, green: 0.47, blue: 0.0, alpha: 1), dark: UIColor(red: 1.0, green: 0.66, blue: 0.2, alpha: 1))

    static let messageSpacing: CGFloat = 28
    static let contentMaxWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 20

    static func syntaxColor(_ kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .plain: return plainCode
        case .keyword: return keyword
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .type: return type
        case .function: return function
        case .property: return property
        case .attribute: return attribute
        }
    }

    // Xcode's default light and dark themes.
    private static let plainCode = dynamic(light: UIColor(white: 0.1, alpha: 0.92), dark: UIColor(white: 1, alpha: 0.88))
    private static let keyword = dynamic(light: UIColor(red: 0.61, green: 0.14, blue: 0.58, alpha: 1), dark: UIColor(red: 1.0, green: 0.48, blue: 0.70, alpha: 1))
    private static let string = dynamic(light: UIColor(red: 0.77, green: 0.1, blue: 0.09, alpha: 1), dark: UIColor(red: 0.99, green: 0.53, blue: 0.43, alpha: 1))
    private static let number = dynamic(light: UIColor(red: 0.11, green: 0.0, blue: 0.81, alpha: 1), dark: UIColor(red: 0.85, green: 0.79, blue: 0.49, alpha: 1))
    private static let comment = dynamic(light: UIColor(red: 0.36, green: 0.42, blue: 0.47, alpha: 1), dark: UIColor(red: 0.47, green: 0.53, blue: 0.59, alpha: 1))
    private static let type = dynamic(light: UIColor(red: 0.04, green: 0.31, blue: 0.47, alpha: 1), dark: UIColor(red: 0.41, green: 0.85, blue: 1.0, alpha: 1))
    private static let function = dynamic(light: UIColor(red: 0.2, green: 0.43, blue: 0.45, alpha: 1), dark: UIColor(red: 0.51, green: 0.83, blue: 0.72, alpha: 1))
    private static let property = dynamic(light: UIColor(red: 0.22, green: 0.0, blue: 0.63, alpha: 1), dark: UIColor(red: 0.70, green: 0.60, blue: 1.0, alpha: 1))
    private static let attribute = dynamic(light: UIColor(red: 0.51, green: 0.37, blue: 0.01, alpha: 1), dark: UIColor(red: 0.93, green: 0.65, blue: 0.42, alpha: 1))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? light : dark
        })
    }
}

extension AppTheme {
    var title: String {
        switch self {
        case .system: return String(localized: "System")
        // "Light" is already the translated name of a thinking level.
        case .light: return String(localized: "theme.light", defaultValue: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Applies the appearance to every window of the app, sheets and overlays included.
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != interfaceStyle {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

extension AccentChoice {
    var title: String {
        switch self {
        case .default: return String(localized: "Default")
        case .blue: return String(localized: "Blue")
        case .green: return String(localized: "Green")
        case .yellow: return String(localized: "Yellow")
        case .pink: return String(localized: "Pink")
        case .orange: return String(localized: "Orange")
        }
    }

    var uiColor: UIColor? {
        switch self {
        case .default: return nil
        case .blue: return UIColor(red: 0.01, green: 0.52, blue: 1.0, alpha: 1)
        case .green: return UIColor(red: 0.0, green: 0.7, blue: 0.33, alpha: 1)
        case .yellow: return UIColor(red: 0.96, green: 0.74, blue: 0.0, alpha: 1)
        case .pink: return UIColor(red: 1.0, green: 0.38, blue: 0.66, alpha: 1)
        case .orange: return UIColor(red: 1.0, green: 0.53, blue: 0.0, alpha: 1)
        }
    }

    var color: Color? {
        uiColor.map { Color(uiColor: $0) }
    }

    /// Background of the messages you send.
    var bubble: Color {
        color?.opacity(0.3) ?? Theme.userBubble
    }

    /// Fill of the send button.
    var fill: Color {
        color ?? Theme.prominentFill
    }

    /// Icon drawn on `fill`.
    var onFill: Color {
        switch self {
        case .default: return Theme.onProminent
        case .yellow: return .black
        default: return .white
        }
    }

    var link: Color {
        color ?? Theme.link
    }

    /// A round swatch for menus, which only keep the colors of images drawn in their own colors.
    var swatch: UIImage? {
        let name = self == .default ? "circle.lefthalf.filled" : "circle.fill"
        return UIImage(systemName: name)?.withTintColor(uiColor ?? .label, renderingMode: .alwaysOriginal)
    }
}

extension Color {
    /// A color from a "#RRGGBB" string, such as the color of a ChatGPT project.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension View {
    /// Constrains reading width on iPad and landscape while staying centered.
    func readableWidth() -> some View {
        frame(maxWidth: Theme.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Pull to refresh whose work isn't cancelled when the view updates while it runs.
    /// SwiftUI cancels the refresh task when the refreshed content changes, which made
    /// requests fail with "cancelled" as soon as the chat list started to update.
    func detachedRefreshable(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        refreshable {
            await Task { @MainActor in
                await action()
            }.value
        }
    }
}

extension Error {
    /// True for errors that only mean the work was cancelled, which are never shown.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError { return urlError.code == .cancelled }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
