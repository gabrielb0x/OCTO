import Foundation

/// Decides how much streamed text to reveal on each display frame, so a reply flows at an even
/// pace instead of jumping forward with every network chunk. While streaming, the waiting text
/// is revealed over `catchUpTime`, which keeps it a fraction of a second behind the network;
/// once the reply is complete, the rest is revealed over `finishTime`.
public struct StreamPacer: Sendable {
    /// Characters per second when only a little text is waiting.
    public var minimumRate: Double
    /// Characters per second, at least, once the reply is complete.
    public var finishingRate: Double
    public var catchUpTime: TimeInterval
    public var finishTime: TimeInterval

    private var carry: Double = 0

    public init(minimumRate: Double = 50, finishingRate: Double = 180, catchUpTime: TimeInterval = 0.35, finishTime: TimeInterval = 0.18) {
        self.minimumRate = minimumRate
        self.finishingRate = finishingRate
        self.catchUpTime = catchUpTime
        self.finishTime = finishTime
    }

    public mutating func charactersToReveal(backlog: Int, elapsed: TimeInterval, isFinished: Bool) -> Int {
        guard backlog > 0 else {
            carry = 0
            return 0
        }
        // A long frame (the app was in the background) shouldn't dump everything at once.
        let frame = min(max(elapsed, 0), 1.0 / 20.0)
        let rate = isFinished
            ? max(finishingRate, Double(backlog) / max(finishTime, 0.01))
            : max(minimumRate, Double(backlog) / max(catchUpTime, 0.01))
        carry += rate * frame
        let count = min(backlog, Int(carry))
        carry -= Double(count)
        if count == backlog {
            carry = 0
        }
        return count
    }
}
