import Observation
import OCTOCore
import QuartzCore
import SwiftUI

/// The reply being streamed. Text from the network waits in a buffer and is revealed a few
/// letters per display frame, so it reads as one continuous flow. Only the view of this reply
/// observes it, so the rest of the chat isn't redrawn while it's written.
@MainActor
@Observable
final class LiveReply {
    /// Letters at the end of the text that are still fading in.
    static let defaultFadeLength = 12.0

    let messageID: UUID
    private(set) var text = ""
    private(set) var reasoning = ""
    private(set) var reasoningDuration: TimeInterval?
    private(set) var searchQueries: [String] = []
    private(set) var citations: [Citation] = []
    private(set) var fadeLength = LiveReply.defaultFadeLength

    @ObservationIgnored var usage: TokenUsage?
    @ObservationIgnored private(set) var receivedText = ""
    @ObservationIgnored private(set) var receivedReasoning = ""
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var pendingCount = 0
    @ObservationIgnored private var reasoningChanged = false
    @ObservationIgnored private var reasoningClock: TimeInterval = 0
    @ObservationIgnored private var isComplete = false
    @ObservationIgnored private var pacer = StreamPacer()
    @ObservationIgnored private var ticker: FrameTicker?

    init(messageID: UUID) {
        self.messageID = messageID
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
        pendingText += delta
        pendingCount += delta.count
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
        if text != receivedText {
            text = receivedText
        }
        pendingText = ""
        pendingCount = 0
        if reasoning != receivedReasoning {
            reasoning = receivedReasoning
        }
        reasoningChanged = false
        fadeLength = 0
    }

    /// Waits for the buffered text to be on screen, then lets its last letters finish fading in.
    func finishRevealing() async {
        isComplete = true
        let deadline = Date().addingTimeInterval(4)
        while pendingCount > 0, !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(16))
        }
        if !Task.isCancelled, pendingCount == 0, fadeLength > 0, !text.isEmpty {
            withAnimation(.easeOut(duration: 0.3)) {
                fadeLength = 0
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        revealEverything()
    }

    private func advance(by elapsed: TimeInterval) {
        // Reasoning is only summarized on screen, so ten updates a second are plenty.
        reasoningClock += elapsed
        if reasoningChanged, reasoningClock >= 0.1 {
            reasoning = receivedReasoning
            reasoningChanged = false
            reasoningClock = 0
        }

        let count = pacer.charactersToReveal(backlog: pendingCount, elapsed: elapsed, isFinished: isComplete)
        guard count > 0 else { return }
        let end = pendingText.index(pendingText.startIndex, offsetBy: count, limitedBy: pendingText.endIndex) ?? pendingText.endIndex
        text.append(contentsOf: pendingText[..<end])
        pendingText.removeSubrange(..<end)
        // Letters joined across two network chunks can make the count drift: the buffer is the truth.
        pendingCount = pendingText.isEmpty ? 0 : max(pendingCount - count, 1)
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
