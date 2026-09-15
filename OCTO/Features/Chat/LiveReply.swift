import Observation
import OCTOCore
import QuartzCore
import SwiftUI
import UIKit

/// The reply being streamed. Text from the network is cut into words that wait in a queue and
/// appear a few per second, each fading in on its own, so the reply reads as one calm flow. Only
/// the view of this reply observes it, so the rest of the chat isn't redrawn while it's written.
@MainActor
@Observable
final class LiveReply {
    let messageID: UUID
    private(set) var text = ""
    private(set) var reasoning = ""
    private(set) var reasoningDuration: TimeInterval?
    private(set) var searchQueries: [String] = []
    private(set) var citations: [Citation] = []
    /// When each of the latest words appeared, oldest first, while they fade in.
    private(set) var revealTimes: [TimeInterval] = []

    @ObservationIgnored var usage: TokenUsage?
    @ObservationIgnored private(set) var receivedText = ""
    @ObservationIgnored private(set) var receivedReasoning = ""
    @ObservationIgnored private let speed: RevealSpeed
    @ObservationIgnored private let onWordsRevealed: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var pacer: StreamPacer
    @ObservationIgnored private var tokenizer = RevealTokenizer()
    @ObservationIgnored private var syntax = RevealSyntax()
    @ObservationIgnored private var queue: [Piece] = []
    @ObservationIgnored private var queueStart = 0
    @ObservationIgnored private var waitingWords = 0
    @ObservationIgnored private var hasNewText = false
    @ObservationIgnored private var reasoningChanged = false
    @ObservationIgnored private var reasoningClock: TimeInterval = 0
    @ObservationIgnored private var pruneClock: TimeInterval = 0
    @ObservationIgnored private var isComplete = false
    @ObservationIgnored private var ticker: FrameTicker?

    private struct Piece {
        let text: String
        /// Markdown syntax, such as a bullet, shows along with the word after it.
        let isSyntax: Bool
    }

    init(messageID: UUID, speed: RevealSpeed, onWordsRevealed: (@MainActor (Int) -> Void)? = nil) {
        self.messageID = messageID
        self.speed = speed
        self.onWordsRevealed = onWordsRevealed
        pacer = StreamPacer(speed: speed)
    }

    /// The fade of the latest words, for the text of the reply; nil when text shows as it arrives.
    var reveal: StreamingReveal? {
        speed == .instant ? nil : StreamingReveal(times: revealTimes, duration: speed.fadeDuration)
    }

    func start() {
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] elapsed in
            guard let self else { return false }
            self.advance(by: elapsed)
            return true
        }
        self.ticker = ticker
        ticker.start()
    }

    func stop() {
        ticker?.stop()
        ticker = nil
    }

    func receiveText(_ delta: String) {
        receivedText += delta
        if speed == .instant {
            hasNewText = true
        } else {
            enqueue(tokenizer.append(delta))
        }
    }

    func receiveReasoning(_ delta: String) {
        receivedReasoning += delta
        reasoningChanged = true
    }

    func startReasoningSection() {
        guard !receivedReasoning.isEmpty else { return }
        receivedReasoning += "\n\n"
        reasoningChanged = true
    }

    func recordReasoningDuration(since start: Date?) {
        guard reasoningDuration == nil, let start else { return }
        reasoningDuration = Date().timeIntervalSince(start)
    }

    func addSearchQuery(_ query: String?) {
        guard let query, !query.isEmpty, !searchQueries.contains(query) else { return }
        searchQueries.append(query)
    }

    func addCitations(_ newCitations: [Citation]) {
        for citation in newCitations where !citations.contains(where: { $0.url == citation.url }) {
            citations.append(citation)
        }
    }

    /// Puts everything received on screen at once, e.g. when the reply is stopped.
    func revealEverything() {
        tokenizer = RevealTokenizer()
        queue.removeAll()
        queueStart = 0
        waitingWords = 0
        hasNewText = false
        if text != receivedText {
            text = receivedText
        }
        if !revealTimes.isEmpty {
            revealTimes.removeAll()
        }
        if reasoning != receivedReasoning {
            reasoning = receivedReasoning
        }
        reasoningChanged = false
    }

    /// Waits for the words still queued to be on screen, then for the last ones to finish fading in.
    func finishRevealing() async {
        isComplete = true
        if speed != .instant {
            enqueue(tokenizer.finish())
        }
        let deadline = Date().addingTimeInterval(15)
        while queueStart < queue.count || hasNewText, !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(16))
        }
        if !Task.isCancelled, let last = revealTimes.last {
            let remaining = last + speed.fadeDuration - Date.timeIntervalSinceReferenceDate
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
        }
        revealEverything()
    }

    private func enqueue(_ pieces: [String]) {
        for piece in pieces {
            let isSyntax = syntax.isSyntaxOnly(piece)
            queue.append(Piece(text: piece, isSyntax: isSyntax))
            if !isSyntax {
                waitingWords += 1
            }
        }
    }

    private func advance(by elapsed: TimeInterval) {
        // Reasoning is only summarized on screen, so ten updates a second are plenty.
        reasoningClock += elapsed
        if reasoningChanged, reasoningClock >= 0.1 {
            reasoning = receivedReasoning
            reasoningChanged = false
            reasoningClock = 0
        }

        guard speed != .instant else {
            if hasNewText {
                text = receivedText
                hasNewText = false
            }
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let count = pacer.wordsToReveal(backlog: waitingWords, elapsed: elapsed, isFinished: isComplete)
        let flushesSyntax = isComplete && waitingWords == 0
        if count > 0 || (flushesSyntax && queueStart < queue.count) {
            var remaining = count
            var added = ""
            var times: [TimeInterval] = []
            while queueStart < queue.count {
                let piece = queue[queueStart]
                if piece.isSyntax {
                    if remaining == 0, !flushesSyntax {
                        break
                    }
                } else {
                    guard remaining > 0 else { break }
                    remaining -= 1
                    // Words revealed in the same frame appear a moment apart.
                    times.append(now - elapsed * Double(remaining) / Double(count))
                }
                added += piece.text
                queueStart += 1
            }
            waitingWords -= times.count
            if queueStart >= 256 {
                queue.removeFirst(queueStart)
                queueStart = 0
            }
            if !added.isEmpty {
                text += added
            }
            if !times.isEmpty {
                revealTimes.append(contentsOf: times)
                onWordsRevealed?(times.count)
            }
        }

        // Words done fading in are forgotten, a few times a second.
        pruneClock += elapsed
        if pruneClock >= 0.25 {
            pruneClock = 0
            let cutoff = now - speed.fadeDuration - 0.1
            let expired = revealTimes.prefix { $0 < cutoff }.count
            if expired > 0 {
                revealTimes.removeFirst(expired)
            }
        }
    }
}

/// A light tap every few words while a reply is written.
@MainActor
final class StreamingHaptics {
    private let generator = UIImpactFeedbackGenerator(style: .soft)
    private var words = 0
    private var lastTap: CFTimeInterval = 0

    init() {
        generator.prepare()
    }

    func wordsRevealed(_ count: Int) {
        words += count
        let now = CACurrentMediaTime()
        guard words >= 4, now - lastTap >= 0.08 else { return }
        words = 0
        lastTap = now
        generator.impactOccurred(intensity: 0.45)
    }
}

/// Calls back on every display frame, up to 60 times a second, until the callback returns false.
@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private let onFrame: (TimeInterval) -> Bool

    init(onFrame: @escaping (TimeInterval) -> Bool) {
        self.onFrame = onFrame
        super.init()
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = lastTimestamp.map { link.timestamp - $0 } ?? link.duration
        lastTimestamp = link.timestamp
        if !onFrame(elapsed) {
            stop()
        }
    }
}
