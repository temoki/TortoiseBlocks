import Testing
import TortoiseCore

@testable import TortoiseBlocksKit

@Suite("SampleProgram")
struct SampleProgramTests {
    @Test("star produces the expected command stream")
    func starStream() {
        let commands = SampleProgram.star()
        #expect(commands.count == 2 + 36 * 2)
        #expect(commands.first == .penColor(.orange))
        #expect(commands[2] == .forward(200))
        #expect(commands.last == .rotate(170))
    }

    @Test("filledSquare wraps its strokes in beginFill/endFill")
    func filledSquareStream() {
        let commands = SampleProgram.filledSquare()
        #expect(commands.contains(.beginFill))
        #expect(commands.last == .endFill)
    }
}

@Suite("Tortoise.apply")
@MainActor
struct TortoiseApplyTests {
    @Test("a well-formed stream round-trips through the Tortoise API")
    func applyRoundTrip() {
        // currentCommandIndex-based block highlighting relies on the recorded
        // stream being identical to the input, index by index.
        let input = SampleProgram.star() + SampleProgram.filledSquare()
        let tortoise = Tortoise()
        tortoise.apply(input)
        #expect(tortoise.commands == input)
    }

    @Test("every command case is applied faithfully")
    func applyAllCases() {
        let input: [TortoiseCommand] = [
            .forward(10), .rotate(45), .home, .setPosition(Point(x: 1, y: 2)),
            .setHeading(90), .penDown, .penUp, .penColor(.red), .penWidth(2),
            .fillColor(.green), .beginFill, .endFill, .showTortoise,
            .hideTortoise, .speed(3), .backgroundColor(.white), .clear,
            .arc(radius: 50, extent: 180), .dot(8),
        ]
        let tortoise = Tortoise()
        tortoise.apply(input)
        #expect(tortoise.commands == input)
    }
}
