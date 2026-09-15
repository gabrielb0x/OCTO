import AVFoundation
import ImageIO
import NaturalLanguage
import Observation
import OCTOCore
import Speech
import UIKit

enum ImageProcessing {
    /// Downscales and re-encodes a picked image so requests stay small.
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    static func thumbnail(from data: Data, maxPixelSize: Int = 360) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Downsampled thumbnails of stored attachments.
@MainActor
enum AttachmentThumbnails {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for attachment: MessageAttachment, files: ConversationFiles) -> UIImage? {
        let key = attachment.storedFileName as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = files.attachmentURL(attachment.storedFileName),
              let data = try? Data(contentsOf: url),
              let image = ImageProcessing.thumbnail(from: data)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Voice dictation with Apple's speech recognizer, on device whenever supported.
@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
    }

    private(set) var state: State = .idle
    private(set) var errorMessage: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    var isActive: Bool { state != .idle }

    func start(onTranscript: @escaping @MainActor (String) -> Void) async {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            fail(String(localized: "Allow speech recognition in Settings to dictate."))
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            fail(String(localized: "Allow microphone access in Settings to dictate."))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            fail(String(localized: "Speech recognition is not available right now."))
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            audioEngine = engine
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor in
                    if let transcript { onTranscript(transcript) }
                    if isFinal || failed { self?.stop() }
                }
            }
            state = .listening
        } catch {
            stop()
            fail(error.localizedDescription)
        }
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        audioEngine = nil
        request = nil
        task = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clearError() {
        errorMessage = nil
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .idle
    }
}

/// Reads assistant replies aloud with the system voices (fully on device).
@MainActor
@Observable
final class SpeechPlayer {
    private(set) var speakingMessageID: UUID?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = SynthesizerDelegate()
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?

    init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] identifier in
            guard let self, self.currentUtterance == identifier else { return }
            self.speakingMessageID = nil
            self.currentUtterance = nil
        }
    }

    /// Identifies the sample read from the Voice settings.
    static let sampleID = UUID(uuidString: "0C70C0DE-5A3E-4000-8000-000000000000")!

    func toggle(messageID: UUID, markdown: String, rate: Double, voiceIdentifier: String? = nil) {
        if speakingMessageID == messageID {
            stop()
            return
        }
        stop()
        let text = MarkdownPlainText.strip(markdown)
        guard !text.isEmpty else { return }
        speak(text, id: messageID, rate: rate, voiceIdentifier: voiceIdentifier)
    }

    /// Reads a sentence aloud to try a voice.
    func speakSample(_ text: String, rate: Double, voiceIdentifier: String?) {
        stop()
        speak(text, id: Self.sampleID, rate: rate, voiceIdentifier: voiceIdentifier)
    }

    /// The chosen voice, else a voice matching the language of the text.
    static func voice(identifier: String?, for text: String) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else { return nil }
        return AVSpeechSynthesisVoice(language: language)
    }

    private func speak(_ text: String, id: UUID, rate: Double, voiceIdentifier: String?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(min(max(rate, 0.3), 0.65))
        utterance.voice = Self.voice(identifier: voiceIdentifier, for: text)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        currentUtterance = ObjectIdentifier(utterance)
        speakingMessageID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        speakingMessageID = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor (ObjectIdentifier) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        notify(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        notify(utterance)
    }

    private func notify(_ utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        let handler = onFinish
        Task { @MainActor in
            handler?(identifier)
        }
    }
}
