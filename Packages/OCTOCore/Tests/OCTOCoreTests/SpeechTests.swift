import Foundation
import Testing
@testable import OCTOCore

@Suite struct SpeechChunkerTests {
    @Test func handsOutCompleteSentencesWhileStreaming() {
        var chunker = SpeechChunker()
        #expect(chunker.nextChunk(in: "Bonjour", isFinal: false) == nil)
        #expect(chunker.nextChunk(in: "Bonjour ! Comment", isFinal: false) == "Bonjour !")
        #expect(chunker.nextChunk(in: "Bonjour ! Comment vas-tu ?", isFinal: false) == nil)
        #expect(chunker.nextChunk(in: "Bonjour ! Comment vas-tu ? Moi", isFinal: false) == "Comment vas-tu ?")
        #expect(chunker.nextChunk(in: "Bonjour ! Comment vas-tu ? Moi ça va.", isFinal: true) == "Moi ça va.")
        #expect(chunker.nextChunk(in: "Bonjour ! Comment vas-tu ? Moi ça va.", isFinal: true) == nil)
    }

    @Test func keepsDecimalsAndStripsMarkdown() {
        var chunker = SpeechChunker()
        #expect(chunker.nextChunk(in: "Version 3.5 is", isFinal: false) == nil)
        #expect(chunker.nextChunk(in: "## Steps\n1. **Boil** water\n2. Add", isFinal: false) == "Steps Boil water")
        #expect(chunker.nextChunk(in: "## Steps\n1. **Boil** water\n2. Add `pasta`", isFinal: true) == "Add pasta")
    }

    @Test func skipsChunksWithNothingToSay() {
        var chunker = SpeechChunker()
        #expect(chunker.nextChunk(in: "---\n", isFinal: false) == nil)
        #expect(chunker.consumedCount == 4)
        #expect(chunker.nextChunk(in: "---\nOK", isFinal: true) == "OK")
    }
}

@Suite struct SystemPromptTests {
    @Test func addsVoiceGuidanceOnlyForSpokenReplies() {
        let written = SystemPrompt.make(aboutUser: "I am a developer")
        #expect(written.contains("I am a developer"))
        #expect(!written.contains("read aloud"))
        #expect(SystemPrompt.make(spokenReplies: true).contains("read aloud"))
    }
}
