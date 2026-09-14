import Foundation

/// Timeline of the welcome screen headline: each phrase is typed, held, erased, then the next
/// one starts. Computing the state from the elapsed time keeps the animation in step with the
/// display instead of depending on timers.
public struct TypingSchedule: Equatable, Sendable {
    public struct Frame: Equatable, Sendable {
        public var phraseIndex: Int
        /// Letters shown; the fractional part is the letter fading in.
        public var visibleCharacters: Double
        public var isErasing: Bool

        public init(phraseIndex: Int, visibleCharacters: Double, isErasing: Bool) {
            self.phraseIndex = phraseIndex
            self.visibleCharacters = visibleCharacters
            self.isErasing = isErasing
        }
    }

    public var lengths: [Int]
    public var typingInterval: TimeInterval
    public var holdDuration: TimeInterval
    public var erasingInterval: TimeInterval
    public var pauseDuration: TimeInterval

    public init(
        lengths: [Int],
        typingInterval: TimeInterval = 0.065,
        holdDuration: TimeInterval = 1.8,
        erasingInterval: TimeInterval = 0.028,
        pauseDuration: TimeInterval = 0.4
    ) {
        self.lengths = lengths
        self.typingInterval = typingInterval
        self.holdDuration = holdDuration
        self.erasingInterval = erasingInterval
        self.pauseDuration = pauseDuration
    }

    public func duration(ofPhraseWithLength length: Int) -> TimeInterval {
        Double(length) * (typingInterval + erasingInterval) + holdDuration + pauseDuration
    }

    public func frame(at elapsed: TimeInterval) -> Frame {
        guard !lengths.isEmpty else {
            return Frame(phraseIndex: 0, visibleCharacters: 0, isErasing: false)
        }
        let cycle = lengths.reduce(0) { $0 + duration(ofPhraseWithLength: $1) }
        guard cycle > 0 else {
            return Frame(phraseIndex: 0, visibleCharacters: Double(lengths[0]), isErasing: false)
        }
        var time = max(elapsed, 0).truncatingRemainder(dividingBy: cycle)
        for (index, length) in lengths.enumerated() {
            let phraseDuration = duration(ofPhraseWithLength: length)
            if time < phraseDuration || index == lengths.count - 1 {
                return frame(phraseIndex: index, length: length, time: min(time, phraseDuration))
            }
            time -= phraseDuration
        }
        return Frame(phraseIndex: 0, visibleCharacters: 0, isErasing: false)
    }

    private func frame(phraseIndex: Int, length: Int, time: TimeInterval) -> Frame {
        let count = Double(length)
        let typing = count * typingInterval
        if time < typing {
            return Frame(phraseIndex: phraseIndex, visibleCharacters: time / typingInterval, isErasing: false)
        }
        let erasingStart = typing + holdDuration
        if time < erasingStart {
            return Frame(phraseIndex: phraseIndex, visibleCharacters: count, isErasing: false)
        }
        let erased = (time - erasingStart) / max(erasingInterval, 0.001)
        return Frame(phraseIndex: phraseIndex, visibleCharacters: max(count - erased, 0), isErasing: true)
    }
}
