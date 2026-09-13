import Foundation
import Testing
@testable import OCTOCore

@Suite struct ServerSentEventParserTests {
    @Test func parsesEventsSeparatedByBlankLines() {
        var parser = ServerSentEventParser()
        let events = parser.consume(Array("event: response.created\ndata: {\"a\":1}\n\ndata: hello\ndata: world\n\n".utf8))
        #expect(events == [
            ServerSentEvent(event: "response.created", data: "{\"a\":1}"),
            ServerSentEvent(event: nil, data: "hello\nworld"),
        ])
    }

    @Test func handlesCRLFSplitChunksAndComments() {
        var parser = ServerSentEventParser()
        let input = Array(": keep-alive\r\ndata: first\r\n\r\ndata:second\r\n\r\n".utf8)
        var events: [ServerSentEvent] = []
        for start in stride(from: 0, to: input.count, by: 3) {
            events += parser.consume(input[start..<min(start + 3, input.count)])
        }
        #expect(events.map(\.data) == ["first", "second"])
    }

    @Test func flushesTrailingEventOnFinish() {
        var parser = ServerSentEventParser()
        #expect(parser.consume(Array("data: tail".utf8)).isEmpty)
        #expect(parser.finish()?.data == "tail")
    }
}

@Suite struct MarkdownParserTests {
    @Test func parsesHeadingsParagraphsAndRules() {
        #expect(MarkdownParser.parse("# Title\n\nFirst line\nsecond line\n\n---\n## Sub ##") == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line\nsecond line"),
            .rule,
            .heading(level: 2, text: "Sub"),
        ])
    }

    @Test func parsesFencedCodeIncludingUnclosedFence() {
        #expect(MarkdownParser.parse("```swift\nlet x = 1\n\nprint(x)\n```\nAfter") == [
            .code(language: "swift", code: "let x = 1\n\nprint(x)"),
            .paragraph("After"),
        ])
        #expect(MarkdownParser.parse("Intro\n```python\ndef f():") == [
            .paragraph("Intro"),
            .code(language: "python", code: "def f():"),
        ])
    }

    @Test func parsesNestedListsWithContinuationAndCode() {
        let text = """
        1. **Install**
           - run `brew install`
           - check version
        2. Configure

           ```bash
           export A=1
           ```
        - other list
        """
        let blocks = MarkdownParser.parse(text)
        #expect(blocks.count == 2)
        guard blocks.count == 2, case .list(let ordered) = blocks[0], case .list(let bullets) = blocks[1] else {
            Issue.record("expected two lists, got \(blocks)")
            return
        }
        #expect(ordered.ordered)
        #expect(ordered.items.count == 2)
        #expect(ordered.items.first?.blocks == [
            .paragraph("**Install**"),
            .list(MarkdownList(ordered: false, startNumber: 1, items: [
                MarkdownListItem(blocks: [.paragraph("run `brew install`")], isChecked: nil),
                MarkdownListItem(blocks: [.paragraph("check version")], isChecked: nil),
            ])),
        ])
        #expect(ordered.items.last?.blocks == [.paragraph("Configure"), .code(language: "bash", code: "export A=1")])
        #expect(!bullets.ordered)
        #expect(bullets.items.count == 1)
    }

    @Test func parsesTablesWithAlignmentAndEscapedPipes() {
        #expect(MarkdownParser.parse("| Name | Value |\n|:-----|------:|\n| a \\| b | `x|y` |\n| c |") == [
            .table(MarkdownTable(header: ["Name", "Value"], alignments: [.leading, .trailing], rows: [["a | b", "`x|y`"], ["c", ""]])),
        ])
    }

    @Test func parsesQuotesTaskListsAndMath() {
        #expect(MarkdownParser.parse("> quoted\ncontinued\n\n- [x] done\n- [ ] todo\n\n$$\na^2 + b^2\n$$") == [
            .quote([.paragraph("quoted\ncontinued")]),
            .list(MarkdownList(ordered: false, startNumber: 1, items: [
                MarkdownListItem(blocks: [.paragraph("done")], isChecked: true),
                MarkdownListItem(blocks: [.paragraph("todo")], isChecked: false),
            ])),
            .math("a^2 + b^2"),
        ])
    }

    @Test func keepsEmphasisLinesAsParagraphs() {
        #expect(MarkdownParser.parse("**Bold** start\n*italic* line\n-5 degrees") == [
            .paragraph("**Bold** start\n*italic* line\n-5 degrees"),
        ])
    }

    @Test func stripsMarkdownToPlainText() {
        let text = "## Hello **world**\n- item with [link](https://x.com)\n```\ncode\n```\n> *quote* and `code`"
        #expect(MarkdownPlainText.strip(text) == "Hello world\nitem with link\ncode\nquote and code")
    }
}

@Suite struct SyntaxHighlighterTests {
    @Test func highlightsSwift() {
        let source = "let name = \"OCTO\" // hi\nprint(42)"
        let tokens = SyntaxHighlighter.tokenize(source, language: "swift")
        #expect(tokens.map(\.text).joined() == source)
        #expect(tokens.contains(SyntaxToken(kind: .keyword, text: "let")))
        #expect(tokens.contains(SyntaxToken(kind: .string, text: "\"OCTO\"")))
        #expect(tokens.contains(SyntaxToken(kind: .comment, text: "// hi")))
        #expect(tokens.contains(SyntaxToken(kind: .function, text: "print")))
        #expect(tokens.contains(SyntaxToken(kind: .number, text: "42")))
    }

    @Test func highlightsJSONKeysAndMarkup() {
        let json = SyntaxHighlighter.tokenize("{\"key\": true}", language: "json")
        #expect(json.contains(SyntaxToken(kind: .property, text: "\"key\"")))
        #expect(json.contains(SyntaxToken(kind: .keyword, text: "true")))

        let html = SyntaxHighlighter.tokenize("<a href=\"/\">Hi</a>", language: "html")
        #expect(html.map(\.text).joined() == "<a href=\"/\">Hi</a>")
        #expect(html.contains(SyntaxToken(kind: .keyword, text: "a")))
        #expect(html.contains(SyntaxToken(kind: .type, text: "href")))
        #expect(html.contains(SyntaxToken(kind: .string, text: "\"/\"")))
    }

    @Test func shellHashInsideWordsIsNotAComment() {
        let tokens = SyntaxHighlighter.tokenize("echo $#args # note", language: "bash")
        #expect(tokens.map(\.text).joined() == "echo $#args # note")
        #expect(tokens.last == SyntaxToken(kind: .comment, text: "# note"))
    }

    @Test func plainLanguagesStayPlain() {
        #expect(SyntaxHighlighter.tokenize("hello", language: "text") == [SyntaxToken(kind: .plain, text: "hello")])
        #expect(SyntaxHighlighter.tokenize("hello", language: nil) == [SyntaxToken(kind: .plain, text: "hello")])
    }
}
