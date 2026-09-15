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

/// Dictation in the message bar. With ChatGPT, your voice is recorded and then written down by
/// ChatGPT like in its apps; on the device, Apple's speech recognition writes as you speak.
@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        /// On-device recognition, writing as you speak.
        case listening
        /// Recording for ChatGPT.
        case recording
        case transcribing
    }

    static let levelCount = 64

    private(set) var state: State = .idle
    private(set) var errorMessage: String?
    /// Loudness of the microphone over the last moments, 0...1, oldest first.
    private(set) var levels: [Double] = []
    private(set) var recordingStartedAt: Date?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?

    var isActive: Bool { state != .idle }

    /// Recording or transcribing for ChatGPT: the message bar shows the recording.
    var showsRecording: Bool { state == .recording || state == .transcribing }

    // MARK: On the device

    func startOnDevice(onTranscript: @escaping @MainActor (String) -> Void) async {
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
        guard state == .starting else { return }
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

    // MARK: With ChatGPT

    /// Starts recording. `onLimit` runs if the recording reaches ChatGPT's 10-minute limit.
    func startRecording(onLimit: @escaping @MainActor () -> Void) async {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            fail(String(localized: "Allow microphone access in Settings to dictate."))
            return
        }
        guard state == .starting else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000,
            ])
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: ChatGPTTranscription.maximumDuration) else {
                throw CocoaError(.fileWriteUnknown)
            }
            // Unreadable while the device is locked, and deleted once transcribed.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            self.recorder = recorder
            recordingURL = url
            recordingStartedAt = Date()
            levels = Array(repeating: 0, count: Self.levelCount)
            state = .recording
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard let self, self.state == .recording, let recorder = self.recorder else { return }
                    guard recorder.isRecording else {
                        onLimit()
                        return
                    }
                    recorder.updateMeters()
                    let decibels = Double(recorder.averagePower(forChannel: 0))
                    var levels = self.levels
                    levels.removeFirst()
                    levels.append(min(max((decibels + 50) / 45, 0), 1))
                    self.levels = levels
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            deactivateAudioSession()
            DevLog.log("dictation", "Recording failed: \(DevLog.describe(error))", level: .error)
            fail(String(localized: "The microphone couldn't start recording."))
        }
    }

    /// Stops recording and has the recording written down. When ChatGPT can't do it, the device
    /// tries, without sending anything; the recording is deleted either way.
    func finishRecording(
        transcribe: @escaping @MainActor (Data, Int) async throws -> String,
        onTranscript: @escaping @MainActor (String, Bool) -> Void
    ) {
        guard state == .recording, let recorder, let url = recordingURL else { return }
        let duration = recorder.currentTime
        recorder.stop()
        meterTask?.cancel()
        meterTask = nil
        self.recorder = nil
        recordingURL = nil
        deactivateAudioSession()
        guard duration >= 0.3 else {
            try? FileManager.default.removeItem(at: url)
            state = .idle
            errorMessage = TranscriptionError.tooShort.localizedDescription
            return
        }
        state = .transcribing
        transcriptionTask = Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: url) }
            var text: String?
            var failure: Error?
            do {
                let audio = try Data(contentsOf: url)
                text = try await transcribe(audio, Int((duration * 1_000).rounded()))
            } catch {
                failure = error
            }
            guard !Task.isCancelled else { return }
            var onDevice = false
            if text == nil, let failure, !(failure is TranscriptionError), !failure.isCancellation {
                DevLog.log("dictation", "ChatGPT couldn't transcribe: \(DevLog.describe(failure))", level: .warning)
                text = await Self.transcribeOnDevice(url)
                onDevice = text != nil
            }
            guard let self, !Task.isCancelled else { return }
            self.transcriptionTask = nil
            self.state = .idle
            self.recordingStartedAt = nil
            if let text {
                onTranscript(text, onDevice)
            } else if let failure, !failure.isCancellation {
                self.errorMessage = ChatSession.describe(failure)
            }
        }
    }

    /// Ends dictation without keeping anything.
    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        meterTask?.cancel()
        meterTask = nil
        if let recorder {
            recorder.stop()
            recorder.deleteRecording()
            deactivateAudioSession()
        }
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        recordingStartedAt = nil
        levels = []
        stopListening()
        state = .idle
    }

    /// Ends dictation: what on-device recognition wrote stays, a ChatGPT recording is dropped.
    func stop() {
        if showsRecording {
            cancel()
        } else {
            stopListening()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func stopListening() {
        let wasListening = audioEngine != nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        audioEngine = nil
        request = nil
        task = nil
        if state == .listening || state == .starting {
            state = .idle
        }
        if wasListening {
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .idle
    }

    /// Apple's speech recognition on a recording, only when it runs on the device.
    nonisolated private static func transcribeOnDevice(_ url: URL) async -> String? {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            let result = RecognitionResult(continuation)
            let task = recognizer.recognitionTask(with: request) { recognition, error in
                if let recognition, recognition.isFinal {
                    result.finish(recognition.bestTranscription.formattedString)
                } else if error != nil {
                    result.finish(nil)
                }
            }
            result.keep(task)
        }
    }
}

/// Resumes once with the text of a recognition, and keeps its task alive until then.
private final class RecognitionResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var task: SFSpeechRecognitionTask?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func keep(_ task: SFSpeechRecognitionTask) {
        lock.withLock {
            if continuation != nil {
                self.task = task
            }
        }
    }

    func finish(_ text: String?) {
        let pending: CheckedContinuation<String?, Never>? = lock.withLock {
            let pending = continuation
            continuation = nil
            task = nil
            return pending
        }
        pending?.resume(returning: text)
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
