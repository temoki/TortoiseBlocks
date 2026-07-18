import Testing
import TortoiseCore

@testable import TortoiseBlocksKit

@Suite("SampleBlocks")
struct SampleBlocksTests {
    @Test("star expands to the same deterministic 36-point stream every time")
    func starExpansion() throws {
        let expanded = try BlockExpander.expand(SampleBlocks.star())
        let commands = expanded.map(\.command)
        #expect(commands.count == 2 + 36 * 2)
        #expect(commands.first == .penColor(.orange))
        #expect(commands[2] == .forward(200))
        #expect(commands.last == .rotate(170))
    }

    @Test("filledSquare is fill color, begin fill, four repeated sides, end fill")
    func filledSquareStructure() {
        let blocks = SampleBlocks.filledSquare()
        #expect(blocks.map(\.kind.category) == [.fill, .fill, .control, .fill])
        #expect(blocks[0].kind == .fillColor(.literal(.cyan)))
        #expect(blocks[1].kind == .beginFill)
        #expect(blocks[3].kind == .endFill)
        guard case .repeatBlock(let count, let body) = blocks[2].kind else {
            Issue.record("expected a repeat block")
            return
        }
        #expect(count == .literal(4))
        #expect(body.map(\.kind) == [.forward(.literal(100)), .turnRight(.literal(90))])
    }

    @Test("spiral expands to steps growing out of the box every lap")
    func spiralExpansion() throws {
        let expanded = try BlockExpander.expand(SampleBlocks.spiral())
        let commands = expanded.map(\.command)
        // Pen color + pen width + 40 × (forward + rotate); the set/add
        // blocks emit nothing.
        #expect(commands.count == 2 + 40 * 2)
        let distances = commands.compactMap { command -> Double? in
            guard case .forward(let distance) = command else { return nil }
            return distance
        }
        #expect(distances.first == 5)
        // 5 + 39 × 5 — spelled as a Double so the macro-split inference
        // can't demote the literal to Int (Double? == Int compares false).
        #expect(distances.last == 200.0)
        #expect(distances == distances.sorted())
    }

    @Test("filledSquare expands to a fill-wrapped square")
    func filledSquareExpansion() throws {
        let expanded = try BlockExpander.expand(SampleBlocks.filledSquare())
        let commands = expanded.map(\.command)
        #expect(
            commands == [
                .fillColor(.cyan),
                .beginFill,
                .forward(100), .rotate(90),
                .forward(100), .rotate(90),
                .forward(100), .rotate(90),
                .forward(100), .rotate(90),
                .endFill,
            ])
    }
}
