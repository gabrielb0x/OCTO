import Foundation

public enum SyntaxTokenKind: String, Sendable {
    case plain
    case keyword
    case string
    case number
    case comment
    case type
    case function
    case property
    case attribute
}

public struct SyntaxToken: Equatable, Sendable {
    public var kind: SyntaxTokenKind
    public var text: String

    public init(kind: SyntaxTokenKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// A small lexical highlighter: good-enough coloring for the languages people
/// usually ask about, without a grammar engine or third-party dependency.
public enum SyntaxHighlighter {
    public static let maximumLength = 60_000

    public static func tokenize(_ code: String, language: String?) -> [SyntaxToken] {
        guard !code.isEmpty else { return [] }
        guard code.utf8.count <= maximumLength, let spec = LanguageSpec.spec(for: language) else {
            return [SyntaxToken(kind: .plain, text: code)]
        }
        var tokenizer = Tokenizer(characters: Array(code), spec: spec)
        return spec.isMarkup ? tokenizer.tokenizeMarkup() : tokenizer.tokenize()
    }
}

struct LanguageSpec {
    var keywords: Set<String> = []
    var builtinTypes: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var stringDelimiters: Set<Character> = ["\"", "'"]
    var tripleQuotedStrings = false
    var capitalizedIdentifiersAreTypes = true
    var caseInsensitiveKeywords = false
    var hashCommentNeedsBoundary = false
    var attributePrefix: Character?
    var variablePrefix: Character?
    var keysAreProperties = false
    var isMarkup = false

    static func spec(for language: String?) -> LanguageSpec? {
        guard let name = language?.lowercased().trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        switch name {
        case "swift": return swift
        case "python", "py", "python3": return python
        case "javascript", "js", "jsx", "mjs", "cjs", "node": return javascript
        case "typescript", "ts", "tsx": return typescript
        case "json", "jsonc", "json5", "jsonl": return json
        case "java": return java
        case "kotlin", "kt", "kts": return kotlin
        case "c", "h", "objc", "objective-c", "objectivec": return c
        case "cpp", "c++", "cc", "cxx", "hpp", "hh", "arduino": return cpp
        case "cs", "csharp", "c#": return csharp
        case "go", "golang": return go
        case "rust", "rs": return rust
        case "ruby", "rb": return ruby
        case "php": return php
        case "bash", "sh", "shell", "zsh", "fish", "console", "terminal", "powershell", "ps1", "dockerfile", "makefile": return shell
        case "sql", "mysql", "postgresql", "postgres", "sqlite", "plsql", "tsql": return sql
        case "yaml", "yml", "toml", "ini", "conf": return yaml
        case "html", "xml", "svg", "xhtml", "plist", "vue", "svelte", "xaml": return markup
        case "css", "scss", "sass", "less": return css
        case "dart": return dart
        case "lua": return lua
        case "text", "txt", "plain", "plaintext", "markdown", "md", "output", "log", "csv", "diff", "patch": return nil
        default: return generic
        }
    }

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(separator: " ").map(String.init))
    }

    static let swift = LanguageSpec(
        keywords: words("actor any as associatedtype async await borrowing break case catch class consuming continue default defer deinit do else enum extension fallthrough false fileprivate final for func guard if import in init inout internal is lazy let mutating nil nonisolated open operator override package private protocol public repeat rethrows return self Self sending some static struct subscript super switch throw throws true try typealias unowned var weak where while"),
        builtinTypes: words("Int Double Float String Bool Character Array Dictionary Set Optional Void Any"),
        lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\""], tripleQuotedStrings: true,
        attributePrefix: "@"
    )

    static let python = LanguageSpec(
        keywords: words("and as assert async await break case class continue def del elif else except False finally for from global if import in is lambda match None nonlocal not or pass raise return self True try while with yield"),
        builtinTypes: words("int float str bool list dict set tuple bytes object type print len range"),
        lineComments: ["#"], tripleQuotedStrings: true, attributePrefix: "@"
    )

    static let javascript = LanguageSpec(
        keywords: words("async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield"),
        lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"]
    )

    static let typescript: LanguageSpec = {
        var spec = javascript
        spec.keywords.formUnion(words("abstract as declare enum implements infer interface is keyof namespace private protected public readonly satisfies type"))
        spec.builtinTypes = words("string number boolean any unknown never object bigint symbol")
        return spec
    }()

    static let json = LanguageSpec(
        keywords: words("true false null"), lineComments: ["//"], stringDelimiters: ["\""],
        capitalizedIdentifiersAreTypes: false, keysAreProperties: true
    )

    static let java = LanguageSpec(
        keywords: words("abstract assert boolean break byte case catch char class const continue default do double else enum extends false final finally float for if implements import instanceof int interface long native new null package permits private protected public record return sealed short static super switch synchronized this throw throws transient true try var void volatile while yield"),
        lineComments: ["//"], blockComment: ("/*", "*/"), attributePrefix: "@"
    )

    static let kotlin = LanguageSpec(
        keywords: words("abstract annotation as break by catch class companion const constructor continue data do else enum false final finally for fun if import in init inline interface internal is lateinit null object open operator out override package private protected public return sealed super suspend this throw true try typealias val var vararg when where while"),
        lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotedStrings: true, attributePrefix: "@"
    )

    static let c = LanguageSpec(
        keywords: words("auto bool break case char const continue default do double else enum extern false float for goto if inline int long NULL register restrict return short signed sizeof static struct switch true typedef union unsigned void volatile while"),
        lineComments: ["//"], blockComment: ("/*", "*/"), capitalizedIdentifiersAreTypes: false, attributePrefix: "#"
    )

    static let cpp: LanguageSpec = {
        var spec = c
        spec.keywords.formUnion(words("alignas alignof catch class co_await co_return co_yield concept const_cast constexpr decltype delete dynamic_cast explicit export friend mutable namespace new noexcept nullptr operator override private protected public reinterpret_cast requires static_cast template this thread_local throw try typeid typename using virtual"))
        spec.builtinTypes = words("std string vector map set size_t unique_ptr shared_ptr")
        spec.capitalizedIdentifiersAreTypes = true
        return spec
    }()

    static let csharp = LanguageSpec(
        keywords: words("abstract as async await base bool break byte case catch char class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach get if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly record ref return sealed set short sizeof static string struct switch this throw true try typeof uint ulong using var virtual void while yield"),
        lineComments: ["//"], blockComment: ("/*", "*/")
    )

    static let go = LanguageSpec(
        keywords: words("break case chan const continue default defer else fallthrough false for func go goto if import interface iota map nil package range return select struct switch true type var"),
        builtinTypes: words("any bool byte complex64 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr"),
        lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"], capitalizedIdentifiersAreTypes: false
    )

    static let rust = LanguageSpec(
        keywords: words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"),
        builtinTypes: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str"),
        lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\""], attributePrefix: "#"
    )

    static let ruby = LanguageSpec(
        keywords: words("alias and attr_accessor attr_reader begin break case class def do else elsif end ensure false for if in module next nil not or puts redo require rescue retry return self super then true undef unless until when while yield"),
        lineComments: ["#"], attributePrefix: ":"
    )

    static let php = LanguageSpec(
        keywords: words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty extends false final finally fn for foreach function global if implements include instanceof interface isset list match namespace new null or print private protected public readonly require return static switch throw trait true try unset use var while yield"),
        lineComments: ["//", "#"], blockComment: ("/*", "*/"), hashCommentNeedsBoundary: true, variablePrefix: "$"
    )

    static let shell = LanguageSpec(
        keywords: words("alias break case cd continue do done echo elif else esac eval exec exit export fi for function if in local readonly return set shift source sudo then trap unset until while"),
        lineComments: ["#"], capitalizedIdentifiersAreTypes: false, hashCommentNeedsBoundary: true, variablePrefix: "$"
    )

    static let sql = LanguageSpec(
        keywords: words("add all alter and as asc avg begin between by case check column commit constraint count create default delete desc distinct drop else end exists false foreign from full group having if in index inner insert into is join key left like limit max min not null offset on or order outer primary references returning right rollback select set sum table then transaction true union unique update values view when where with"),
        builtinTypes: words("bigint blob bool boolean char date datetime decimal double float int integer json jsonb numeric real serial smallint text timestamp uuid varchar"),
        lineComments: ["--"], blockComment: ("/*", "*/"), capitalizedIdentifiersAreTypes: false, caseInsensitiveKeywords: true
    )

    static let yaml = LanguageSpec(
        keywords: words("true false null yes no on off"),
        lineComments: ["#"], capitalizedIdentifiersAreTypes: false, hashCommentNeedsBoundary: true, keysAreProperties: true
    )

    static let css = LanguageSpec(
        keywords: words("important media import keyframes from to and not only supports"),
        lineComments: ["//"], blockComment: ("/*", "*/"), capitalizedIdentifiersAreTypes: false, attributePrefix: "@", keysAreProperties: true
    )

    static let dart = LanguageSpec(
        keywords: words("abstract as assert async await break case catch class const continue default do dynamic else enum export extends extension external factory false final finally for get if implements import in is late library mixin new null on operator part required rethrow return set static super switch sync this throw true try typedef var void while with yield"),
        lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotedStrings: true, attributePrefix: "@"
    )

    static let lua = LanguageSpec(
        keywords: words("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"),
        lineComments: ["--"], blockComment: ("--[[", "]]"), capitalizedIdentifiersAreTypes: false
    )

    static let markup = LanguageSpec(isMarkup: true)

    static let generic = LanguageSpec(
        keywords: words("async await break case catch class const continue def default do else elif end enum export extends false final fn for from func function if import in interface let match new nil null None private protected public return self static struct switch this throw true True False try type use val var void when where while yield"),
        lineComments: ["//", "#"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"], hashCommentNeedsBoundary: true
    )
}

private struct Tokenizer {
    let characters: [Character]
    let spec: LanguageSpec
    private(set) var tokens: [SyntaxToken] = []

    init(characters: [Character], spec: LanguageSpec) {
        self.characters = characters
        self.spec = spec
    }

    mutating func tokenize() -> [SyntaxToken] {
        let count = characters.count
        var index = 0
        while index < count {
            let character = characters[index]

            if let block = spec.blockComment, matches(block.open, at: index) {
                let end = find(block.close, from: index + block.open.count).map { $0 + block.close.count } ?? count
                emit(.comment, index, end)
                index = end
                continue
            }

            if let marker = spec.lineComments.first(where: { matches($0, at: index) }),
               !(marker == "#" && spec.hashCommentNeedsBoundary && index > 0 && !characters[index - 1].isWhitespace) {
                var end = index
                while end < count, characters[end] != "\n" { end += 1 }
                emit(.comment, index, end)
                index = end
                continue
            }

            if spec.stringDelimiters.contains(character) {
                let end = stringEnd(from: index)
                let isKey = spec.keysAreProperties && nextNonSpace(from: end) == ":"
                emit(isKey ? .property : .string, index, end)
                index = end
                continue
            }

            if character.isASCII, character.isNumber, index == 0 || !Self.isIdentifierPart(characters[index - 1]) {
                var end = index + 1
                while end < count, Self.isIdentifierPart(characters[end]) || (characters[end] == "." && end + 1 < count && characters[end + 1].isNumber) {
                    end += 1
                }
                emit(.number, index, end)
                index = end
                continue
            }

            if let prefix = spec.attributePrefix, character == prefix, index + 1 < count, Self.isIdentifierStart(characters[index + 1]) {
                var end = index + 1
                while end < count, Self.isIdentifierPart(characters[end]) { end += 1 }
                emit(.attribute, index, end)
                index = end
                continue
            }

            if let prefix = spec.variablePrefix, character == prefix, index + 1 < count,
               Self.isIdentifierPart(characters[index + 1]) || characters[index + 1] == "{" {
                var end = index + 1
                if characters[end] == "{" {
                    while end < count, characters[end] != "}", characters[end] != "\n" { end += 1 }
                    end = min(end + 1, count)
                } else {
                    while end < count, Self.isIdentifierPart(characters[end]) { end += 1 }
                }
                emit(.property, index, end)
                index = end
                continue
            }

            if Self.isIdentifierStart(character) {
                var end = index + 1
                while end < count, Self.isIdentifierPart(characters[end]) { end += 1 }
                let word = String(characters[index..<end])
                emit(classify(word, next: nextNonSpace(from: end)), index, end)
                index = end
                continue
            }

            emit(.plain, index, index + 1)
            index += 1
        }
        return tokens
    }

    mutating func tokenizeMarkup() -> [SyntaxToken] {
        let count = characters.count
        var index = 0
        while index < count {
            if matches("<!--", at: index) {
                let end = find("-->", from: index + 4).map { $0 + 3 } ?? count
                emit(.comment, index, end)
                index = end
                continue
            }

            if characters[index] == "<", index + 1 < count,
               characters[index + 1].isLetter || "/!?".contains(characters[index + 1]) {
                var cursor = index + 1
                if "/!?".contains(characters[cursor]) { cursor += 1 }
                emit(.plain, index, cursor)
                let nameStart = cursor
                while cursor < count, Self.isIdentifierPart(characters[cursor]) || "-:.".contains(characters[cursor]) { cursor += 1 }
                emit(.keyword, nameStart, cursor)

                while cursor < count, characters[cursor] != ">" {
                    let character = characters[cursor]
                    if character == "\"" || character == "'" {
                        var end = cursor + 1
                        while end < count, characters[end] != character { end += 1 }
                        end = min(end + 1, count)
                        emit(.string, cursor, end)
                        cursor = end
                    } else if Self.isIdentifierStart(character) {
                        var end = cursor + 1
                        while end < count, Self.isIdentifierPart(characters[end]) || "-:".contains(characters[end]) { end += 1 }
                        emit(.type, cursor, end)
                        cursor = end
                    } else {
                        emit(.plain, cursor, cursor + 1)
                        cursor += 1
                    }
                }
                if cursor < count {
                    emit(.plain, cursor, cursor + 1)
                    cursor += 1
                }
                index = cursor
                continue
            }

            var end = index + 1
            while end < count, characters[end] != "<" { end += 1 }
            emit(.plain, index, end)
            index = end
        }
        return tokens
    }

    private func classify(_ word: String, next: Character?) -> SyntaxTokenKind {
        let key = spec.caseInsensitiveKeywords ? word.lowercased() : word
        if spec.keywords.contains(key) { return .keyword }
        if spec.builtinTypes.contains(key) { return .type }
        if spec.keysAreProperties, next == ":" { return .property }
        if next == "(" { return .function }
        if spec.capitalizedIdentifiersAreTypes, let first = word.first, first.isUppercase { return .type }
        return .plain
    }

    private func stringEnd(from start: Int) -> Int {
        let count = characters.count
        let quote = characters[start]
        if spec.tripleQuotedStrings, start + 2 < count, characters[start + 1] == quote, characters[start + 2] == quote {
            let closing = String(repeating: String(quote), count: 3)
            return find(closing, from: start + 3).map { $0 + 3 } ?? count
        }
        var index = start + 1
        while index < count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character == quote { return index + 1 }
            if character == "\n", quote != "`" { return index }
            index += 1
        }
        return count
    }

    private mutating func emit(_ kind: SyntaxTokenKind, _ start: Int, _ end: Int) {
        guard end > start else { return }
        let text = String(characters[start..<min(end, characters.count)])
        if let last = tokens.indices.last, tokens[last].kind == kind {
            tokens[last].text += text
        } else {
            tokens.append(SyntaxToken(kind: kind, text: text))
        }
    }

    private func matches(_ string: String, at index: Int) -> Bool {
        var cursor = index
        for character in string {
            guard cursor < characters.count, characters[cursor] == character else { return false }
            cursor += 1
        }
        return true
    }

    private func find(_ string: String, from index: Int) -> Int? {
        guard let first = string.first else { return nil }
        var cursor = index
        while cursor < characters.count {
            if characters[cursor] == first, matches(string, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    private func nextNonSpace(from index: Int) -> Character? {
        var cursor = index
        while cursor < characters.count, characters[cursor] == " " || characters[cursor] == "\t" { cursor += 1 }
        return cursor < characters.count ? characters[cursor] : nil
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func isIdentifierPart(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
