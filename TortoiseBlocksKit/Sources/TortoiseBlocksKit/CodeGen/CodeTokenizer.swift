/// A syntax color category for one span of generated Swift source.
public enum CodeTokenKind: Sendable, Equatable {
    case keyword
    case number
    case methodOrProperty
    case plain
}

/// One colored span of source. `CodeTokenizer.tokenize` covers the whole
/// input, so a caller can walk the list and paint each range without
/// computing the "everything else" gaps itself.
public struct CodeToken: Equatable, Sendable {
    public let kind: CodeTokenKind
    public let range: Range<String.Index>

    public init(kind: CodeTokenKind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}

/// Lightweight highlighter for `SwiftCodeGenerator`'s output only — not a
/// general Swift lexer. Recognizes exactly what the generator emits: the
/// `let`/`for`/`in` keywords, numeric literals, and member references
/// (`🐢.forward`, `.orange`) written with the turtle receiver or Swift's
/// leading-dot enum shorthand.
public enum CodeTokenizer {
    public static func tokenize(_ code: String) -> [CodeToken] {
        let keywordPattern = /\b(let|for|in)\b/
        let numberPattern = /-?[0-9]+(\.[0-9]+)?/
        // A dot followed by an identifier, where the character right before
        // the dot is neither an identifier character nor another dot —
        // excludes `Double.random` (member access on a preceding name) and
        // the `...` range operator, while matching both `🐢.forward` and
        // the bare `.orange` enum shorthand. Swift's regex literals don't
        // support lookbehind, so the preceding boundary is captured as part
        // of the match instead and just not included in the token range.
        let methodOrPropertyPattern = /(?:^|[^A-Za-z0-9_.])\.([A-Za-z_][A-Za-z0-9_]*)/

        var matches: [(range: Range<String.Index>, kind: CodeTokenKind)] = []

        for match in code.matches(of: keywordPattern) {
            matches.append((match.range, .keyword))
        }
        for match in code.matches(of: numberPattern) {
            matches.append((match.range, .number))
        }
        for match in code.matches(of: methodOrPropertyPattern) {
            let identifierRange = match.output.1.startIndex..<match.output.1.endIndex
            matches.append((identifierRange, .methodOrProperty))
        }
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }

        var tokens: [CodeToken] = []
        var cursor = code.startIndex
        for match in matches {
            guard match.range.lowerBound >= cursor else { continue }
            if cursor < match.range.lowerBound {
                tokens.append(CodeToken(kind: .plain, range: cursor..<match.range.lowerBound))
            }
            tokens.append(CodeToken(kind: match.kind, range: match.range))
            cursor = match.range.upperBound
        }
        if cursor < code.endIndex {
            tokens.append(CodeToken(kind: .plain, range: cursor..<code.endIndex))
        }
        return tokens
    }
}
