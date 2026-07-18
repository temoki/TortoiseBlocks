import Testing

@testable import TortoiseBlocksKit

@Suite("CodeTokenizer")
struct CodeTokenizerTests {
    private func describe(_ token: CodeToken, in code: String) -> String {
        "\(token.kind):\(code[token.range])"
    }

    @Test("keywords match at word boundaries, not inside identifiers")
    func keywordBoundaries() {
        // "in" appears both as the loop keyword and inside "Int" — only the
        // former should be tagged; "Int" itself stays plain.
        let code = "for _ in 1...Int.random(in: 1...3) {}"
        let tokens = CodeTokenizer.tokenize(code).filter { $0.kind == .keyword }
        #expect(tokens.map { describe($0, in: code) } == ["keyword:for", "keyword:in", "keyword:in"])
    }

    @Test("integers and decimals, including a leading minus, are numbers")
    func numbers() {
        let code = "🐢.forward(100)\n🐢.left(45.5)\n🐢.right(-90)"
        let tokens = CodeTokenizer.tokenize(code).filter { $0.kind == .number }
        #expect(
            tokens.map { describe($0, in: code) } == [
                "number:100", "number:45.5", "number:-90",
            ])
    }

    @Test("🐢. calls and leading-dot enum cases are methodOrProperty; plain member access is not")
    func methodOrProperty() {
        let code = "🐢.penColor = .orange\n🐢.backward(Double.random(in: 10...20.5))"
        let tokens = CodeTokenizer.tokenize(code).filter { $0.kind == .methodOrProperty }
        // "Double" and "random" (member access, not 🐢. or leading-dot) stay untagged,
        // so exactly these three should show up.
        #expect(
            tokens.map { describe($0, in: code) } == [
                "methodOrProperty:penColor", "methodOrProperty:orange", "methodOrProperty:backward",
            ])
    }

    @Test("var is a keyword; variable lines stay fully covered")
    func variableTokens() {
        let code = SwiftCodeGenerator.code(for: [
            Block(kind: .setVariable(name: "🌟", value: .literal(5))),
            Block(kind: .addVariable(name: "🌟", value: .literal(5))),
        ])
        let tokens = CodeTokenizer.tokenize(code)
        let keywords = tokens.filter { $0.kind == .keyword }
        #expect(keywords.map { describe($0, in: code) } == ["keyword:let", "keyword:var"])
        #expect(tokens.map { String(code[$0.range]) }.joined() == code)
    }

    @Test("tokens fully cover the input with no gaps or overlaps")
    func fullCoverage() {
        let code = SwiftCodeGenerator.code(for: SampleBlocks.randomStar())
        let tokens = CodeTokenizer.tokenize(code)
        #expect(tokens.map { String(code[$0.range]) }.joined() == code)
        for (a, b) in zip(tokens, tokens.dropFirst()) {
            #expect(a.range.upperBound == b.range.lowerBound)
        }
    }

    @Test("a full program snapshot tokenizes as expected")
    func fullProgramSnapshot() {
        let blocks: [Block] = [
            Block(kind: .penColor(.literal(.orange))),
            Block(kind: .penWidth(.literal(2))),
            Block(kind: .fillColor(.literal(.cyan))),
            Block(kind: .beginFill),
            Block(
                kind: .repeatBlock(
                    count: .literal(4),
                    body: [
                        Block(kind: .forward(.literal(100))),
                        Block(kind: .turnRight(.literal(90))),
                        Block(
                            kind: .repeatBlock(
                                count: .random(min: 1, max: 3),
                                body: [
                                    Block(kind: .backward(.random(min: 10, max: 20.5))),
                                    Block(kind: .turnLeft(.literal(45.5))),
                                ]
                            )),
                    ]
                )),
            Block(kind: .endFill),
            Block(kind: .penUp),
            Block(kind: .home),
            Block(kind: .penDown),
        ]
        let code = SwiftCodeGenerator.code(for: blocks)

        let nonPlain = CodeTokenizer.tokenize(code).filter { $0.kind != .plain }

        #expect(
            nonPlain.map { describe($0, in: code) } == [
                "keyword:let",
                "methodOrProperty:penColor", "methodOrProperty:orange",
                "methodOrProperty:penWidth", "number:2",
                "methodOrProperty:fillColor", "methodOrProperty:cyan",
                "methodOrProperty:beginFill",
                "keyword:for", "keyword:in", "number:1", "number:4",
                "methodOrProperty:forward", "number:100",
                "methodOrProperty:right", "number:90",
                "keyword:for", "keyword:in", "number:1",
                "keyword:in", "number:1", "number:3",
                "methodOrProperty:backward", "keyword:in", "number:10", "number:20.5",
                "methodOrProperty:left", "number:45.5",
                "methodOrProperty:endFill",
                "methodOrProperty:penUp",
                "methodOrProperty:home",
                "methodOrProperty:penDown",
            ])
    }
}
