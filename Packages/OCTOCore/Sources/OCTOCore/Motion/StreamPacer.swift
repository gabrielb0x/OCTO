import Foundation

/// How fast replies appear on screen.
public enum RevealSpeed: String, CaseIterable, Codable, Sendable, Identifiable {
    case slow
    case normal
    case fast
    /// Text shows as soon as it arrives, without fading.
    case instant

    public var id: String { rawValue }

    /// How long each word takes to fade in.
    public var fadeDuration: TimeInterval {
        switch self {
        case .slow: return 0.9
        case .normal: return 0.65
        case .fast: return 0.4
        case .instant: return 0
        }
    }
}

/// Decides how many words to reveal on each display frame, so a reply flows word by word at an
/// even pace instead of jumping forward with every network chunk. The pace follows the words
/// waiting to be shown, up to a ceiling that keeps the reply calm to read; the screen never falls
/// more than `longestLag` behind, and once the reply is complete the rest comes a little faster.
public struct StreamPacer: Sendable {
    /// Words per second when only a few words are waiting.
    public var minimumRate: Double
    /// Words per second at most while the reply is still arriving.
    public var maximumRate: Double
    /// Words per second at most once the reply is complete.
    public var finishingRate: Double
    /// While streaming, the waiting words are spread over this time.
    public var catchUpTime: TimeInterval
    /// Once complete, the rest is spread over this time.
    public var finishTime: TimeInterval
    public var longestLag: TimeInterval
    /// Once complete, the words that were waiting take at most this long to show.
    public var longestFinish: TimeInterval

    private var carry: Double = 0
    private var finishingBacklog: Int?

    public init(
        minimumRate: Double = 10,
        maximumRate: Double = 24,
        finishingRate: Double = 42,
        catchUpTime: TimeInterval = 2.5,
        finishTime: TimeInterval = 2,
        longestLag: TimeInterval = 8,
        longestFinish: TimeInterval = 7
    ) {
        self.minimumRate = minimumRate
        self.maximumRate = maximumRate
        self.finishingRate = finishingRate
        self.catchUpTime = catchUpTime
        self.finishTime = finishTime
        self.longestLag = longestLag
        self.longestFinish = longestFinish
    }

    public init(speed: RevealSpeed) {
        switch speed {
        case .slow:
            self.init(minimumRate: 6, maximumRate: 14, finishingRate: 24, catchUpTime: 4, finishTime: 3, longestLag: 14, longestFinish: 10)
        case .normal:
            self.init()
        case .fast, .instant:
            self.init(minimumRate: 18, maximumRate: 70, finishingRate: 120, catchUpTime: 1, finishTime: 0.8, longestLag: 4, longestFinish: 3)
        }
    }

    public mutating func wordsToReveal(backlog: Int, elapsed: TimeInterval, isFinished: Bool) -> Int {
        guard backlog > 0 else {
            carry = 0
            return 0
        }
        // A long frame (the app was in the background) shouldn't dump everything at once.
        let frame = min(max(elapsed, 0), 1.0 / 20.0)
        let waiting = Double(backlog)
        var floor = minimumRate
        var budget = 0.0
        if isFinished {
            let start = finishingBacklog ?? backlog
            finishingBacklog = start
            floor = max(minimumRate, finishingRate / 3)
            budget = Double(start) / max(longestFinish, 0.01)
        }
        let ceiling = isFinished ? finishingRate : maximumRate
        let spread = max(isFinished ? finishTime : catchUpTime, 0.01)
        let rate = max(min(max(floor, waiting / spread), ceiling), budget, waiting / max(longestLag, 0.01))
        carry += rate * frame
        let count = min(backlog, Int(carry))
        carry -= Double(count)
        if count == backlog {
            carry = 0
        }
        return count
    }
}
