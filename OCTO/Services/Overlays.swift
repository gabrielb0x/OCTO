import SwiftUI
import UIKit

/// A short confirmation shown at the top of the screen, such as "The chat has been deleted".
struct Toast: Identifiable, Equatable {
    enum Style: Equatable {
        case success
        case info
        case warning
        case failure
    }

    let id = UUID()
    let style: Style
    let message: String
    let systemImage: String
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .success, systemImage: String? = nil, duration: TimeInterval = 2.6) {
        let toast = Toast(style: style, message: message, systemImage: systemImage ?? Self.defaultSymbol(for: style))
        current = toast
        UIAccessibility.post(notification: .announcement, argument: message)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.current?.id == toast.id else { return }
            self.current = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    private static func defaultSymbol(for style: Toast.Style) -> String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }
}

/// Windows above the app, so toasts and the lock stay on top of sheets:
/// one ignoring touches for toasts and the performance overlay, one for the privacy cover.
@MainActor
final class OverlayWindows {
    private var overlayWindow: UIWindow?
    private var coverWindow: UIWindow?

    func install(app: AppModel) {
        guard overlayWindow == nil, let scene = Self.activeScene else { return }

        let overlayHost = UIHostingController(rootView: OverlayRoot().environment(app))
        overlayHost.view.backgroundColor = .clear
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        overlay.rootViewController = overlayHost
        overlay.isHidden = false
        overlayWindow = overlay

        let coverHost = UIHostingController(rootView: ProtectionCover().environment(app))
        coverHost.view.backgroundColor = .clear
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert
        cover.backgroundColor = .clear
        cover.rootViewController = coverHost
        cover.isHidden = true
        coverWindow = cover

        app.settings.theme.apply()
        app.developer.applyAnimationSpeed()
    }

    func setCoverVisible(_ visible: Bool) {
        guard let coverWindow, coverWindow.isHidden == visible else { return }
        if visible {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            coverWindow.isHidden = false
            coverWindow.makeKey()
        } else {
            coverWindow.isHidden = true
            Self.activeScene?.windows.first { $0.windowLevel == .normal && !$0.isHidden }?.makeKey()
        }
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

private struct OverlayRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let toast = app.toasts.current {
                ToastView(toast: toast)
                    .id(toast.id)
                    // Below the navigation bar, so the toast doesn't cover its title and buttons.
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .overlay(alignment: .topLeading) {
            if app.developer.isEnabled, app.developer.showsPerformanceOverlay {
                PerformanceHUD(monitor: app.developer.performance)
                    .padding(.leading, 16)
                    .padding(.top, 54)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.22), value: app.toasts.current)
        .sensoryFeedback(trigger: app.toasts.current?.id) { _, id in
            guard id != nil, app.settings.hapticsEnabled, let style = app.toasts.current?.style else { return nil }
            switch style {
            case .success: return .success
            case .warning: return .warning
            case .failure: return .error
            case .info: return nil
            }
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(Theme.background.opacity(0.35)), in: .capsule)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch toast.style {
        case .success: return Theme.success
        case .info: return Theme.link
        case .warning: return Theme.warning
        case .failure: return Theme.danger
        }
    }
}

/// Frame rate, memory and CPU in a small glass capsule, for developer mode.
struct PerformanceHUD: View {
    let monitor: PerformanceMonitor

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(monitor.framesPerSecond) FPS")
                .foregroundStyle(frameRateColor)
            Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(monitor.memoryFootprint), countStyle: .memory))
            Text(verbatim: "CPU \(Int(monitor.cpuUsage.rounded())) %")
        }
        .font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var frameRateColor: Color {
        switch monitor.framesPerSecond {
        case 55...: return Theme.success
        case 40..<55: return Theme.warning
        default: return Theme.danger
        }
    }
}
