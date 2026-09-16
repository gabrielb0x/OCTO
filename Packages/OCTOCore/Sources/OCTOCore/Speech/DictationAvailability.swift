import Foundation

/// What iOS answers when asked for speech recognition, mapped here so this logic can be tested
/// without the Speech framework. The app translates `SFSpeechRecognizerAuthorizationStatus` into it.
public enum SpeechAuthorization: String, Sendable {
    case notDetermined
    case denied
    /// iOS doesn't allow speech recognition on this device: dictation is turned off in its
    /// settings, or Screen Time forbids it. Asking for permission changes nothing.
    case restricted
    case authorized
}

/// Whether dictation on the device can write down what is said, and why not when it can't.
/// iOS reports dictation turned off in Settings as a restriction, which is worth telling apart
/// from a refused permission: one is fixed in Settings → General → Keyboard, the other in OCTO's
/// own settings page.
public enum DictationAvailability: Equatable, Sendable {
    case available
    /// Dictation is turned off in the settings of the device.
    case turnedOffOnDevice
    /// Speech recognition was refused to OCTO.
    case permissionDenied
    /// Nothing is turned off: no recognizer for the language, or it can't run right now.
    case unavailable

    /// `hasRecognizer` is false when iOS offers no recognizer at all, `isRecognizerAvailable`
    /// when the one it offers can't be used at this moment.
    public static func check(
        authorization: SpeechAuthorization,
        hasRecognizer: Bool,
        isRecognizerAvailable: Bool
    ) -> DictationAvailability {
        switch authorization {
        case .restricted:
            return .turnedOffOnDevice
        case .denied:
            return .permissionDenied
        case .notDetermined, .authorized:
            break
        }
        guard hasRecognizer else { return .unavailable }
        return isRecognizerAvailable ? .available : .unavailable
    }

    public var isAvailable: Bool {
        self == .available
    }

    /// True when the way out is the Settings app rather than OCTO.
    public var isFixedInSystemSettings: Bool {
        self == .turnedOffOnDevice || self == .permissionDenied
    }
}
