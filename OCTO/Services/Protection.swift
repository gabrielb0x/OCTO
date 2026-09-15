import LocalAuthentication
import Observation
import OCTOCore
import SwiftUI

/// Locks OCTO behind Face ID (or the passcode), hides its content in the app switcher and while
/// the screen is recorded or shared.
@MainActor
@Observable
final class AppProtection {
    private(set) var isLocked: Bool
    private(set) var isObscured = false
    private(set) var isAuthenticating = false
    /// The screen is being recorded, mirrored or shared.
    private(set) var isScreenCaptured = false
    private(set) var lastError: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var backgroundedAt: Date?

    init(settings: AppSettings, isDemo: Bool) {
        self.settings = settings
        isLocked = !isDemo && settings.locksWithFaceID
    }

    var showsCover: Bool {
        isLocked || isObscured || hidesForScreenCapture
    }

    var hidesForScreenCapture: Bool {
        isScreenCaptured && settings.hidesWhenScreenCaptured
    }

    /// Face ID, Touch ID or Optic ID, with its symbol, or the passcode on devices without biometrics.
    static var biometry: (name: String, systemImage: String) {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return ("Face ID", "faceid")
        case .touchID: return ("Touch ID", "touchid")
        case .opticID: return ("Optic ID", "opticid")
        default: return (String(localized: "Passcode"), "lock")
        }
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            if let backgroundedAt,
               AppLockPolicy.requiresUnlock(isEnabled: settings.locksWithFaceID, backgroundedAt: backgroundedAt, now: Date(), timeout: TimeInterval(settings.lockTimeout.rawValue)) {
                isLocked = true
            }
            backgroundedAt = nil
            isObscured = false
            if isLocked, !isAuthenticating {
                Task { await unlock() }
            }
        case .inactive:
            if settings.hidesContentInAppSwitcher, !isAuthenticating {
                isObscured = true
            }
        case .background:
            backgroundedAt = backgroundedAt ?? Date()
            if settings.hidesContentInAppSwitcher || settings.locksWithFaceID {
                isObscured = true
            }
        @unknown default:
            break
        }
    }

    /// The screen started or stopped being recorded, mirrored or shared.
    func screenCaptureChanged(isCaptured: Bool) {
        guard isCaptured != isScreenCaptured else { return }
        isScreenCaptured = isCaptured
        DevLog.log("protection", isCaptured ? "The screen is being captured" : "Screen capture ended")
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate(reason: String(localized: "Unlock OCTO")) {
            isLocked = false
        }
    }

    /// Turning the lock on asks for Face ID first, so it never locks out someone who can't unlock.
    func setLock(enabled: Bool) async {
        guard enabled != settings.locksWithFaceID else { return }
        if enabled {
            guard await authenticate(reason: String(localized: "Turn on the lock for OCTO")) else { return }
        }
        settings.locksWithFaceID = enabled
        DevLog.log("protection", "Lock \(enabled ? "enabled" : "disabled")")
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            lastError = String(localized: "Set a passcode on this device to lock OCTO.")
            DevLog.log("protection", "Can't evaluate policy: \(policyError.map { DevLog.describe($0) } ?? "unknown")", level: .warning)
            // Without a passcode the lock can't work: the chats must stay reachable.
            isLocked = false
            return false
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastError = nil
            return success
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            return false
        } catch {
            lastError = error.localizedDescription
            DevLog.log("protection", "Authentication failed: \(DevLog.describe(error))", level: .warning)
            return false
        }
    }
}

/// Covers the app while it's locked, shown in the app switcher or while the screen is captured.
struct ProtectionCover: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .foregroundStyle(Theme.primaryText)
                if app.protection.isLocked {
                    Text("OCTO is locked")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Button {
                        Task { await app.protection.unlock() }
                    } label: {
                        Label("Unlock", systemImage: AppProtection.biometry.systemImage)
                            .font(.headline)
                            .foregroundStyle(Theme.onProminent)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentFill)
                    .controlSize(.large)
                    .disabled(app.protection.isAuthenticating)
                    if let error = app.protection.lastError {
                        Text(verbatim: error)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else if app.protection.hidesForScreenCapture {
                    VStack(spacing: 6) {
                        Text("Hidden while the screen is recorded")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Your chats show again once the recording or sharing stops.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                }
            }
        }
        .opacity(app.protection.showsCover ? 1 : 0)
        .animation(.smooth(duration: 0.2), value: app.protection.showsCover)
    }
}
