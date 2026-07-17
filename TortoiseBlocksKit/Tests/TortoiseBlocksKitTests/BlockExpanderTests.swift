import Foundation
import Testing
import TortoiseCore

@testable import TortoiseBlocksKit

/// Deterministic RNG (SplitMix64) so random-value expansion is testable.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("BlockExpander")
struct BlockExpanderTests {
    private func expand(
        _ blocks: [Block], seed: UInt64 = 1, limit: Int = BlockExpander.defaultLimit
    ) throws -> [ExpandedCommand] {
        var rng = SeededRNG(seed: seed)
        return try BlockExpander.expand(blocks, using: &rng, limit: limit)
    }

    @Test("every simple block kind maps to its command")
    func everyKindMapsToCommand() throws {
        let blocks: [Block] = [
            Block(kind: .forward(.literal(100))),
            Block(kind: .backward(.literal(50))),
            Block(kind: .turnRight(.literal(90))),
            Block(kind: .turnLeft(.literal(45))),
            Block(kind: .home),
            Block(kind: .penUp),
            Block(kind: .penDown),
            Block(kind: .penColor(.red)),
            Block(kind: .penWidth(.literal(3))),
            Block(kind: .fillColor(.cyan)),
            Block(kind: .beginFill),
            Block(kind: .endFill),
        ]
        let commands = try expand(blocks).map(\.command)
        #expect(
            commands == [
                .forward(100), .forward(-50), .rotate(90), .rotate(-45),
                .home, .penUp, .penDown, .penColor(.red), .penWidth(3),
                .fillColor(.cyan), .beginFill, .endFill,
            ])
    }

    @Test("repeat expands its body count times, tagging body block IDs")
    func repeatExpandsBody() throws {
        let forward = Block(kind: .forward(.literal(10)))
        let turn = Block(kind: .turnRight(.literal(90)))
        let repeatBlock = Block(kind: .repeatBlock(count: .literal(3), body: [forward, turn]))

        let expanded = try expand([repeatBlock])
        #expect(expanded.map(\.command) == [
            .forward(10), .rotate(90), .forward(10), .rotate(90), .forward(10), .rotate(90),
        ])
        // Highlighting targets the body blocks, not the repeat container.
        #expect(expanded.map(\.blockID) == [
            forward.id, turn.id, forward.id, turn.id, forward.id, turn.id,
        ])
    }

    @Test("nested repeats multiply")
    func nestedRepeats() throws {
        let inner = Block(kind: .repeatBlock(count: .literal(2), body: [Block(kind: .home)]))
        let outer = Block(kind: .repeatBlock(count: .literal(3), body: [inner]))
        let expanded = try expand([outer])
        #expect(expanded.count == 6)
        #expect(expanded.allSatisfy { $0.command == .home })
    }

    @Test("repeat count is rounded and clamped to zero")
    func repeatCountRoundingAndClamping() throws {
        let body = [Block(kind: .home)]
        #expect(try expand([Block(kind: .repeatBlock(count: .literal(2.6), body: body))]).count == 3)
        #expect(try expand([Block(kind: .repeatBlock(count: .literal(-5), body: body))]).isEmpty)
    }

    @Test("the same seed expands to the same commands")
    func seededExpansionIsDeterministic() throws {
        let blocks = SampleBlocks.randomStar()
        let first = try expand(blocks, seed: 42)
        let second = try expand(blocks, seed: 42)
        #expect(first == second)
    }

    @Test("a random value inside a repeat is re-evaluated every iteration")
    func randomInsideRepeatReevaluates() throws {
        let blocks = [
            Block(
                kind: .repeatBlock(
                    count: .literal(3),
                    body: [Block(kind: .forward(.random(min: 0, max: 1000)))]
                ))
        ]
        let distances = try expand(blocks).compactMap { expanded -> Double? in
            guard case .forward(let distance) = expanded.command else { return nil }
            return distance
        }
        #expect(distances.count == 3)
        #expect(Set(distances).count > 1)
    }

    @Test("an inverted random range is normalized instead of trapping")
    func invertedRandomRange() throws {
        let blocks = [Block(kind: .forward(.random(min: 200, max: 100)))]
        guard case .forward(let distance) = try expand(blocks)[0].command else {
            Issue.record("expected forward")
            return
        }
        #expect((100...200).contains(distance))
    }

    @Test("expansion beyond the limit throws")
    func limitExceededThrows() {
        let runaway = [
            Block(
                kind: .repeatBlock(
                    count: .literal(200),
                    body: [
                        Block(
                            kind: .repeatBlock(
                                count: .literal(200),
                                body: [Block(kind: .home)]
                            ))
                    ]
                ))
        ]
        #expect(throws: BlockExpansionError.commandLimitExceeded(limit: 10_000)) {
            try expand(runaway)
        }
    }

    @Test("a custom limit applies")
    func customLimit() {
        let blocks = (0..<6).map { _ in Block(kind: .home) }
        #expect(throws: BlockExpansionError.commandLimitExceeded(limit: 5)) {
            try expand(blocks, limit: 5)
        }
    }
}
