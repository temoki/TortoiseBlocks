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

    @Test("a random color renders as a pick from every non-white preset")
    func randomColorCode() {
        let code = SwiftCodeGenerator.code(for: [Block(kind: .penColor(.random))])
        #expect(
            code.hasSuffix(
                "🐢.penColor = [.black, .red, .green, .blue, .yellow, .orange, .purple, .cyan, .magenta].randomElement()!"
            ))
    }
}
