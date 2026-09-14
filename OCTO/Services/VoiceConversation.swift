import AVFoundation
import NaturalLanguage
import Observation
import OCTOCore
import Speech

/// Voice mode engine: listens with on-device speech recognition, sends the transcript once
/// the user pauses, then reads the streamed reply aloud sentence by sentence and listens again.
@MainActor
@Observable
final class VoiceConversation {
    enum Phase: Equatable {
        case starting
        case listening
        case thinking
        case speaking
        case muted
        case failed(String)
    }

    private(set) var phase: Phase = .starting
    private(set) var level: Double = 0
    private(set) var transcript = ""
    private(set) var isMuted = false

    @ObservationIgnored private weak var session: ChatSession?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let synthesizerDelegate = VoiceSynthesizerDelegate()
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var replyVoice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var queuedUtterances = 0
    @ObservationIgnored private var isReplyComplete = true
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var listenGeneration = 0
    @ObservationIgnored private var listenStartedAt = Date()
    @ObservationIgnored private var quickFailures = 0
    @ObservationIgnored private var speechRate = 0.5

    init() {
        synthesizer.delegate = synthesizerDelegate
        synthesizerDelegate.onFinish = { [weak self] in
            self?.utteranceDidFinish()
        }
    }

    var statusTitle: String {
        switch phase {
        case .starting: return String(localized: "Starting…")
        case .listening: return String(localized: "Listening")
        case .thinking: return String(localized: "Thinking")
        case .speaking: return String(localized: "Tap to interrupt")
        case .muted: return String(localized: "Microphone off")
        case .failed(let message): return message
        }
    }

    // MARK: Lifecycle

    func start(session: ChatSession, app: AppModel) async {
        guard !isRunning else { return }
        isRunning = true
        self.session = session
        speechRate = app.settings.speechRate
        app.speech.stop()
        session.isVoiceConversation = true

        #if OCTO_DEMO
        if app.isDemo {
            phase = .listening
            level = 0.3
            return
        }
        #endif

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard isRunning else { return }
        guard speechStatus == .authorized else {
            fail(String(localized: "Allow speech recognition in Settings to use voice mode."))
            return
        }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard isRunning else { return }
        guard microphoneAllowed else {
            fail(String(localized: "Allow microphone access in Settings to use voice mode."))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            fail(String(localized: "Speech recognition is not available right now."))
            return
        }
        self.recognizer = recognizer

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            fail(error.localizedDescription)
            return
        }
        listen()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        silenceTask?.cancel()
        replyTask?.cancel()
        stopListening()
        queuedUtterances = 0
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        session?.isVoiceConversation = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggleMute() {
        isMuted.toggle()
        guard isRunning else { return }
        if isMuted, phase == .listening {
            silenceTask?.cancel()
            stopListening()
            level = 0
            phase = .muted
        } else if !isMuted, phase == .muted {
            listen()
        }
    }

    /// Tapping the orb while a reply is read aloud goes straight back to listening.
    func interrupt() {
        guard isRunning, phase == .speaking else { return }
        replyTask?.cancel()
        isReplyComplete = true
        queuedUtterances = 0
        synthesizer.stopSpeaking(at: .immediate)
        listen()
    }

    // MARK: Listening

    private func listen() {
        guard isRunning, let recognizer else { return }
        stopListening()
        transcript = ""
        guard !isMuted else {
            phase = .muted
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail(String(localized: "No microphone is available."))
            return
        }

        let generation = listenGeneration
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = VoiceConversation.normalizedLevel(of: buffer)
            Task { @MainActor in
                self?.updateLevel(level, generation: generation)
            }
        }
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handleRecognition(text: text, isFinal: isFinal, failed: failed, generation: generation)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            recognitionTask?.cancel()
            recognitionTask = nil
            fail(error.localizedDescription)
            return
        }
        audioEngine = engine
        self.request = request
        listenStartedAt = Date()
        phase = .listening
    }

    private func stopListening() {
        listenGeneration += 1
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        request = nil
        recognitionTask = nil
    }

    private func updateLevel(_ value: Double, generation: Int) {
        guard generation == listenGeneration, phase == .listening else { return }
        level = level * 0.6 + value * 0.4
    }

    private func handleRecognition(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard isRunning, generation == listenGeneration, phase == .listening else { return }
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            quickFailures = 0
            waitForPause()
        }
        if isFinal {
            finishListening()
        } else if failed {
            guard transcript.isEmpty else {
                finishListening()
                return
            }
            // Recognition stops after a long silence: listen again, unless it keeps failing right away.
            let failedRightAway = Date().timeIntervalSince(listenStartedAt) < 1.5
            quickFailures = failedRightAway ? quickFailures + 1 : 0
            if quickFailures >= 3 {
                fail(String(localized: "Speech recognition is not available right now."))
            } else {
                listen()
            }
        }
    }

    /// The user is done talking once the transcript stops changing for a moment.
    private func waitForPause() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            self?.finishListening()
        }
    }

    private func finishListening() {
        guard isRunning, phase == .listening else { return }
        silenceTask?.cancel()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        level = 0
        guard let session, !text.isEmpty, !session.isStreaming else {
            listen()
            return
        }
        phase = .thinking
        session.sendVoiceMessage(text)
        followReply(of: session)
    }

    // MARK: Speaking

    private func followReply(of session: ChatSession) {
        replyTask?.cancel()
        isReplyComplete = false
        replyVoice = nil
        replyTask = Task { [weak self, weak session] in
            var chunker = SpeechChunker()
            while !Task.isCancelled {
                guard let self, let session else { return }
                let isStreaming = session.isStreaming
                if let reply = session.messages.last, reply.role == .assistant {
                    if let chunk = chunker.nextChunk(in: reply.text, isFinal: !isStreaming) {
                        self.speak(chunk)
                    }
                    if !isStreaming, reply.status == .failed, let error = reply.errorMessage {
                        self.speak(error)
                    }
                }
                if !isStreaming {
                    self.isReplyComplete = true
                    self.resumeListeningIfDone()
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func speak(_ text: String) {
        guard isRunning, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(min(max(speechRate, 0.3), 0.65))
        if replyVoice == nil, let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue {
            replyVoice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.voice = replyVoice
        queuedUtterances += 1
        phase = .speaking
        synthesizer.speak(utterance)
    }

    private func utteranceDidFinish() {
        queuedUtterances = max(0, queuedUtterances - 1)
        resumeListeningIfDone()
    }

    private func resumeListeningIfDone() {
        guard isRunning, isReplyComplete, queuedUtterances == 0, phase == .speaking || phase == .thinking else { return }
        listen()
    }

    private func fail(_ message: String) {
        silenceTask?.cancel()
        stopListening()
        level = 0
        phase = .failed(message)
    }

    /// Microphone loudness mapped to 0...1, computed on the audio thread.
    nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return Double(min(max((decibels + 50) / 40, 0), 1))
    }
}

private final class VoiceSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        notify()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        notify()
    }

    private func notify() {
        let handler = onFinish
        Task { @MainActor in
            handler?()
        }
    }
}
