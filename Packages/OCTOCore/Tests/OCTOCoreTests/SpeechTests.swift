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
    @Test func presentsItselfAsChatGPTWithTheAccountPersonalization() {
        let personal = PersonalContext(
            nickname: "Gabriel",
            occupation: "Student",
            aboutUser: "I am a developer",
            responseStyle: "Always use tu",
            personality: "cynic",
            traits: ["emoji": "more", "enthusiastic": "default"],
            memories: ["Has a kitten", "  "]
        )
        let written = SystemPrompt.make(personal: personal)
        #expect(written.hasPrefix("You are ChatGPT"))
        #expect(!written.contains("OCTO"))
        #expect(written.contains("Preferred name: Gabriel"))
        #expect(written.contains("Occupation: Student"))
        #expect(written.contains("I am a developer"))
        #expect(written.contains("Always use tu"))
        #expect(written.contains("Cynical"))
        #expect(written.contains("Use more emoji."))
        #expect(!written.contains("enthusiasm"))
        #expect(written.contains("- Has a kitten\n") || written.hasSuffix("- Has a kitten"))
        #expect(!written.contains("read aloud"))

        let plain = SystemPrompt.make()
        #expect(!plain.contains("Personality chosen"))
        #expect(!plain.contains("Saved memories"))
        #expect(SystemPrompt.make(spokenReplies: true).contains("read aloud"))
    }
}
