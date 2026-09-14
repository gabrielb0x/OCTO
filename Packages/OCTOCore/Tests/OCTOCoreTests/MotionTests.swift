import Foundation
import Testing
@testable import OCTOCore

@Suite struct StreamPacerTests {
    @Test func revealsBurstsAtAnEvenPace() {
        var pacer = StreamPacer()
        #expect(pacer.charactersToReveal(backlog: 0, elapsed: 1.0 / 60, isFinished: false) == 0)

        // Chunks of 40 characters every 0.25 s (160 characters per second), shown at 60 fps.
        let frame = 1.0 / 60
        var received = 0
        var revealed = 0
        var largestStep = 0
        var largestLag = 0
        var nextChunk = 0.0
        var time = 0.0
        var steps: [Int] = []
        while time < 3 {
            if time >= nextChunk {
                received += 40
                nextChunk += 0.25
            }
            let step = pacer.charactersToReveal(backlog: received - revealed, elapsed: frame, isFinished: false)
            revealed += step
            steps.append(step)
            largestStep = max(largestStep, step)
            largestLag = max(largestLag, received - revealed)
            time += frame
        }
        // Never a whole chunk at once, and text keeps moving between chunks.
        #expect(largestStep <= 6)
        #expect(largestLag <= 100)
        #expect(steps.suffix(120).filter { $0 == 0 }.count <= 12)

        // Once the reply is complete, what's left is revealed within a few frames.
        var frames = 0
        while revealed < received, frames < 120 {
            revealed += pacer.charactersToReveal(backlog: received - revealed, elapsed: frame, isFinished: true)
            frames += 1
        }
        #expect(revealed == received)
        #expect(frames <= 30)
    }

    @Test func slowStreamsStillType() {
        var pacer = StreamPacer()
        var revealed = 0
        for _ in 0..<60 {
            revealed += pacer.charactersToReveal(backlog: 3 - revealed, elapsed: 1.0 / 60, isFinished: false)
        }
        #expect(revealed == 3)
        // A frame after a long pause doesn't reveal a huge backlog in one go.
        #expect(pacer.charactersToReveal(backlog: 1_000, elapsed: 5, isFinished: false) < 200)
    }
}

@Suite struct TypingScheduleTests {
    @Test func typesHoldsErasesAndMovesOn() {
        let schedule = TypingSchedule(lengths: [5, 3], typingInterval: 0.1, holdDuration: 1, erasingInterval: 0.05, pauseDuration: 0.5)
        #expect(abs(schedule.duration(ofPhraseWithLength: 5) - 2.25) < 0.0001)
        #expect(schedule.frame(at: 0) == TypingSchedule.Frame(phraseIndex: 0, visibleCharacters: 0, isErasing: false))
        #expect(abs(schedule.frame(at: 0.25).visibleCharacters - 2.5) < 0.0001)
        #expect(schedule.frame(at: 1.2) == TypingSchedule.Frame(phraseIndex: 0, visibleCharacters: 5, isErasing: false))

        let erasing = schedule.frame(at: 1.6)
        #expect(erasing.isErasing)
        #expect(abs(erasing.visibleCharacters - 3) < 0.0001)
        #expect(schedule.frame(at: 1.9).visibleCharacters == 0)

        let second = schedule.frame(at: 2.4)
        #expect(second.phraseIndex == 1)
        #expect(abs(second.visibleCharacters - 1.5) < 0.0001)

        let cycle = schedule.duration(ofPhraseWithLength: 5) + schedule.duration(ofPhraseWithLength: 3)
        #expect(schedule.frame(at: cycle + 0.25).phraseIndex == 0)
        #expect(TypingSchedule(lengths: []).frame(at: 3).visibleCharacters == 0)
    }
}
