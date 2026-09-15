import Foundation
import Testing
@testable import OCTOCore

@Suite struct StreamPacerTests {
    @Test func revealsWordsAtAnEvenPace() {
        var pacer = StreamPacer(speed: .normal)
        #expect(pacer.wordsToReveal(backlog: 0, elapsed: 1.0 / 60, isFinished: false) == 0)

        // Chunks of 8 words every 0.25 s (32 words per second), shown at 60 fps.
        let frame = 1.0 / 60
        var received = 0
        var revealed = 0
        var largestStep = 0
        var nextChunk = 0.0
        var time = 0.0
        var steps: [Int] = []
        while time < 4 {
            if time >= nextChunk {
                received += 8
                nextChunk += 0.25
            }
            let step = pacer.wordsToReveal(backlog: received - revealed, elapsed: frame, isFinished: false)
            revealed += step
            steps.append(step)
            largestStep = max(largestStep, step)
            time += frame
        }
        // One word at a time, words keep coming between chunks, and calmer than the network.
        #expect(largestStep <= 1)
        #expect(steps.suffix(120).filter { $0 > 0 }.count >= 40)
        #expect(revealed < received)
        #expect(revealed <= 24 * 4 + 1)

        // Once the reply is complete, the rest comes a little faster and finishes.
        var frames = 0
        while revealed < received, frames < 60 * 20 {
            revealed += pacer.wordsToReveal(backlog: received - revealed, elapsed: frame, isFinished: true)
            frames += 1
        }
        #expect(revealed == received)
        #expect(frames <= 60 * 5)
    }

    @Test func shortRepliesStillFlow() {
        var pacer = StreamPacer(speed: .normal)
        var revealed = 0
        for _ in 0..<60 {
            revealed += pacer.wordsToReveal(backlog: 3 - revealed, elapsed: 1.0 / 60, isFinished: false)
        }
        #expect(revealed == 3)
        // A frame after a long pause doesn't reveal a huge backlog in one go.
        #expect(pacer.wordsToReveal(backlog: 1_000, elapsed: 5, isFinished: false) <= 10)
    }

    @Test func longRepliesFinishInTime() {
        var pacer = StreamPacer(speed: .slow)
        var revealed = 0
        var frames = 0
        while revealed < 3_000, frames < 60 * 30 {
            revealed += pacer.wordsToReveal(backlog: 3_000 - revealed, elapsed: 1.0 / 60, isFinished: true)
            frames += 1
        }
        #expect(revealed == 3_000)
        #expect(frames <= 60 * 11)
    }

    @Test func speedsKeepTheirOrder() {
        func revealedInOneSecond(_ speed: RevealSpeed) -> Int {
            var pacer = StreamPacer(speed: speed)
            var revealed = 0
            for _ in 0..<60 {
                revealed += pacer.wordsToReveal(backlog: 200 - revealed, elapsed: 1.0 / 60, isFinished: false)
            }
            return revealed
        }
        #expect(revealedInOneSecond(.slow) < revealedInOneSecond(.normal))
        #expect(revealedInOneSecond(.normal) < revealedInOneSecond(.fast))
        #expect(RevealSpeed.slow.fadeDuration > RevealSpeed.fast.fadeDuration)
        #expect(RevealSpeed.instant.fadeDuration == 0)
    }
}

@Suite struct RevealTokenizerTests {
    @Test func cutsWordsWithTheSpacesBeforeThem() {
        var tokenizer = RevealTokenizer()
        #expect(tokenizer.append("Hello wo") == ["Hello"])
        #expect(tokenizer.pending == " wo")
        #expect(tokenizer.append("rld,\n\n- item") == [" world,", "\n\n-"])
        #expect(tokenizer.pending == " item")
        #expect(tokenizer.finish() == [" item"])
        #expect(tokenizer.pending.isEmpty)
    }

    @Test func splitsScriptsWithoutSpacesAndLongRuns() {
        #expect(RevealTokenizer.count(in: "你好世界") == 4)
        let text = "Voir https://example.com/a/very/long/path/that/goes/on ici"
        let pieces = RevealTokenizer.ranges(in: text).map { String(text[$0]) }
        #expect(pieces.joined() == text)
        #expect(pieces.first == "Voir")
        #expect(pieces.last == " ici")
        #expect(pieces.allSatisfy { $0.trimmingCharacters(in: .whitespaces).count <= 24 })
        #expect(RevealTokenizer.count(in: "  a b  ") == 2)
        #expect(RevealTokenizer.count(in: "   ") == 1)
        #expect(RevealTokenizer.count(in: "") == 0)
    }

    @Test func streamingGivesTheSamePiecesAsTheWholeText() {
        let text = "## Titre\n\nUn **mot** et 日本語のテキスト, puis https://example.com/un/lien/assez/long?x=1 et du `code`.\n\n1. Premier\n2. Second"
        let whole = RevealTokenizer.ranges(in: text).map { String(text[$0]) }
        for size in [1, 2, 3, 5, 8, 13] {
            var tokenizer = RevealTokenizer()
            var pieces: [String] = []
            var index = text.startIndex
            while index < text.endIndex {
                let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
                pieces += tokenizer.append(String(text[index..<end]))
                index = end
            }
            pieces += tokenizer.finish()
            #expect(pieces == whole, "chunks of \(size)")
        }
    }

    @Test func recognizesMarkdownSyntax() {
        var syntax = RevealSyntax()
        let text = "## Title\n\nSome - text\n\n- item\n1. first\n> quote\n\n```swift\nlet a = 1\n# not a heading\n```\n\n| a | b |\n|---|---|\n---"
        let pieces = RevealTokenizer.ranges(in: text).map { String(text[$0]) }
        let flagged = pieces.filter { syntax.isSyntaxOnly($0) }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(flagged == ["##", "-", "1.", ">", "```swift", "```", "|", "|", "|", "|---|---|", "---"])
    }

    @Test func closesOpenInlineMarkersWhileStreaming() {
        #expect(MarkdownStreaming.closingOpenInlineMarkers("Voici **Impor") == "Voici **Impor**")
        #expect(MarkdownStreaming.closingOpenInlineMarkers("**Done** and more") == "**Done** and more")
        #expect(MarkdownStreaming.closingOpenInlineMarkers("Use `let x") == "Use `let x`")
        #expect(MarkdownStreaming.closingOpenInlineMarkers("Use `a ** b") == "Use `a ** b`")
        #expect(MarkdownStreaming.closingOpenInlineMarkers("**Old** line\nnew **bold") == "**Old** line\nnew **bold**")
        #expect(MarkdownStreaming.closingOpenInlineMarkers("```swift\nlet **x") == "```swift\nlet **x")
        #expect(MarkdownStreaming.closingOpenInlineMarkers("plain") == "plain")
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
