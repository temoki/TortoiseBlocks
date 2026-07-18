import Testing

@testable import TortoiseBlocksKit

@Suite("SwiftCodeGenerator")
struct SwiftCodeGeneratorTests {
    @Test("a program covering every block kind renders as expected source")
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

        let expected = """
            let 🐢 = Tortoise()
            🐢.penColor = .orange
            🐢.penWidth = 2
            🐢.fillColor = .cyan
            🐢.beginFill()
            for _ in 1...4 {
                🐢.forward(100)
                🐢.right(90)
                for _ in 1...Int.random(in: 1...3) {
                    🐢.backward(Double.random(in: 10...20.5))
                    🐢.left(45.5)
                }
            }
            🐢.endFill()
            🐢.penUp()
            🐢.home()
            🐢.penDown()
            """

        #expect(SwiftCodeGenerator.code(for: blocks) == expected)
    }

    @Test("an empty program is just the tortoise declaration")
    func emptyProgram() {
        #expect(SwiftCodeGenerator.code(for: []) == "let 🐢 = Tortoise()")
    }

    @Test("integral literals drop the trailing .0")
    func numberFormatting() {
        let code = SwiftCodeGenerator.code(for: [Block(kind: .forward(.literal(100.0)))])
        #expect(code.hasSuffix("🐢.forward(100)"))
    }

    @Test("variables declare up front, then assign, add, and read as Swift")
    func variableCode() {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(5))),
            Block(
                kind: .repeatBlock(
                    count: .literal(20),
                    body: [
                        Block(kind: .forward(.variable("🌟"))),
                        Block(kind: .turnRight(.literal(92))),
                        Block(kind: .addVariable(name: "🌟", value: .literal(5))),
                    ]
                )),
        ]
        let expected = """
            let 🐢 = Tortoise()
            var 🌟 = 0.0
            🌟 = 5
            for _ in 1...20 {
                🐢.forward(🌟)
                🐢.right(92)
                🌟 += 5
            }
            """
        #expect(SwiftCodeGenerator.code(for: blocks) == expected)
    }

    @Test("a variable repeat count renders as Int(name)")
    func variableCountCode() {
        let code = SwiftCodeGenerator.code(for: [
            Block(kind: .repeatBlock(count: .variable("💖"), body: [Block(kind: .home)]))
        ])
        #expect(code.contains("var 💖 = 0.0"))
        #expect(code.contains("for _ in 1...Int(💖) {"))
    }

    @Test("an if block renders as a Swift if with the comparison operator")
    func ifCode() {
        let blocks = [
            Block(
                kind: .ifBlock(
                    condition: Condition(
                        lhs: .random(min: 1, max: 6), comparison: .greaterOrEqual,
                        rhs: .literal(4)),
                    body: [Block(kind: .penColor(.literal(.red)))]
                ))
        ]
        let expected = """
            let 🐢 = Tortoise()
            if Double.random(in: 1...6) >= 4 {
                🐢.penColor = .red
            }
            """
        #expect(SwiftCodeGenerator.code(for: blocks) == expected)
    }

    @Test("a variable condition declares the variable and renders ==")
    func ifVariableCode() {
        let blocks = [
            Block(
                kind: .ifBlock(
                    condition: Condition(lhs: .variable("🌟"), comparison: .equal, rhs: .literal(3)),
                    body: []
                ))
        ]
        let expected = """
            let 🐢 = Tortoise()
            var 🌟 = 0.0
            if 🌟 == 3 {
            }
            """
        #expect(SwiftCodeGenerator.code(for: blocks) == expected)
    }

    @Test("a random color renders as a pick from every non-white preset")
    func randomColorCode() {
        let code = SwiftCodeGenerator.code(for: [Block(kind: .penColor(.random))])
        #expect(
            code.hasSuffix(
                "🐢.penColor = [.black, .red, .green, .blue, .yellow, .orange, .purple, .cyan, .magenta].randomElement()!"
            ))
    }
}
