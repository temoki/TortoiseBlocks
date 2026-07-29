import Foundation
import Testing
import TortoiseCore

@testable import TortoiseBlocksKit

/// Numeric limits (#27). The first four tests are the crashes and the freeze
/// that unbounded input made reachable from ordinary editing — each one
/// trapped or spun forever before `NumberDomain` existed.
@Suite("NumberDomain")
struct NumberDomainTests {
    private func expand(
        _ blocks: [Block], seed: UInt64 = 1, limit: Int = BlockExpander.defaultLimit
    ) throws -> [ExpandedCommand] {
        var rng = SeededRNG(seed: seed)
        return try BlockExpander.expand(blocks, using: &rng, limit: limit)
    }

    // MARK: - The four reachable failures

    @Test("a repeat count beyond Int's range expands instead of trapping")
    func hugeRepeatCount() throws {
        let commands = try expand([
            Block(kind: .repeatBlock(count: .literal(1e300), body: [Block(kind: .home)]))
        ])
        #expect(commands.count == 1000)
    }

    @Test("a box driven to infinity is still usable as a repeat count")
    func infiniteBoxAsRepeatCount() throws {
        // `*=` reaches infinity in a few iterations without the write-back
        // saturation; `Int(inf)` then traps.
        let commands = try expand([
            Block(kind: .setVariable(name: "x", value: .literal(1000))),
            Block(kind: .multiplyVariable(name: "x", value: .literal(1000))),
            Block(kind: .multiplyVariable(name: "x", value: .literal(1000))),
            Block(kind: .repeatBlock(count: .variable("x"), body: [Block(kind: .home)])),
        ])
        #expect(commands.count == 1000)
    }

    @Test("dice bounds too wide to represent roll instead of trapping")
    func infiniteDiceRange() throws {
        // Double.random(in:) traps on an infinite range, before there is any
        // result to clamp — so the *bounds* have to be clamped.
        let commands = try expand([
            Block(kind: .forward(.random(min: -1e308, max: 1e308)))
        ])
        guard case .forward(let distance) = commands[0].command else {
            Issue.record("expected a forward command")
            return
        }
        #expect(NumberDomain.distance.range.contains(distance))
    }

    @Test("an empty repeat body with a huge count terminates")
    func emptyBodyHugeCount() throws {
        // An empty body charges no step, so `limit` never fires: this spun on
        // 1e11 iterations until the count itself was bounded.
        let commands = try expand([
            Block(kind: .repeatBlock(count: .literal(1e11), body: []))
        ])
        #expect(commands.isEmpty)
    }

    // MARK: - Saturation

    @Test("values saturate into their slot's domain")
    func valuesSaturate() throws {
        let commands = try expand([
            Block(kind: .forward(.literal(1e7))),
            Block(kind: .backward(.literal(1e7))),
            Block(kind: .turnRight(.literal(1e9))),
            Block(kind: .penWidth(.literal(1e9))),
        ])
        #expect(
            commands.map(\.command) == [
                .forward(1000), .forward(-1000), .rotate(360), .penWidth(100),
            ])
    }

    @Test("box arithmetic stays finite however long it runs")
    func boxArithmeticStaysFinite() throws {
        let blocks: [Block] = [
            Block(kind: .setVariable(name: "x", value: .literal(1000))),
            Block(
                kind: .repeatBlock(
                    count: .literal(500),
                    body: [Block(kind: .multiplyVariable(name: "x", value: .literal(1000)))])),
            Block(kind: .forward(.variable("x"))),
        ]
        let commands = try expand(blocks)
        #expect(commands.last?.command == .forward(1000))
    }

    @Test("an unbounded accumulator pins at the bound")
    func accumulatorPins() throws {
        let blocks: [Block] = [
            Block(
                kind: .repeatBlock(
                    count: .literal(1000),
                    body: [Block(kind: .addVariable(name: "x", value: .literal(100)))])),
            Block(kind: .forward(.variable("x"))),
        ]
        #expect(try expand(blocks).last?.command == .forward(1000))
    }

    @Test("subtracting past the lower bound pins there too")
    func subtractPins() throws {
        let blocks: [Block] = [
            Block(
                kind: .repeatBlock(
                    count: .literal(100),
                    body: [Block(kind: .subtractVariable(name: "x", value: .literal(1000)))])),
            Block(kind: .forward(.variable("x"))),
        ]
        #expect(try expand(blocks).last?.command == .forward(-1000))
    }

    // MARK: - clamp

    @Test("clamp always yields a finite value inside the range")
    func clampIsTotal() {
        for domain in NumberDomain.allCases {
            for value: Double in [
                -.infinity, .infinity, .nan, -1e308, 1e308, 0, -1, 1,
            ] {
                let clamped = domain.clamp(value)
                #expect(clamped.isFinite)
                #expect(domain.range.contains(clamped))
            }
            #expect(domain.clamp(.nan) == 0)
            #expect(domain.clamp(-.infinity) == domain.range.lowerBound)
            #expect(domain.clamp(.infinity) == domain.range.upperBound)
        }
    }

    @Test("iterationCount converts safely at and beyond the extremes")
    func iterationCountIsSafe() {
        #expect(NumberDomain.iterationCount(.nan) == 0)
        #expect(NumberDomain.iterationCount(-.infinity) == 0)
        #expect(NumberDomain.iterationCount(.infinity) == 1000)
        #expect(NumberDomain.iterationCount(-5) == 0)
        #expect(NumberDomain.iterationCount(3.6) == 4)
        #expect(NumberDomain.iterationCount(1e300) == 1000)
    }

    // MARK: - Slot mapping

    @Test("every block kind's number slot has a domain")
    func kindsMapToDomains() {
        #expect(BlockKind.forward(.literal(1)).numberDomain == .distance)
        #expect(BlockKind.backward(.literal(1)).numberDomain == .distance)
        #expect(BlockKind.turnRight(.literal(1)).numberDomain == .angle)
        #expect(BlockKind.turnLeft(.literal(1)).numberDomain == .angle)
        #expect(BlockKind.penWidth(.literal(1)).numberDomain == .penWidth)
        #expect(BlockKind.repeatBlock(count: .literal(1), body: []).numberDomain == .repeatCount)
        #expect(BlockKind.setVariable(name: "x", value: .literal(1)).numberDomain == .general)
        #expect(BlockKind.home.numberDomain == nil)
    }

    // MARK: - The frozen format is untouched

    @Test("out-of-range values survive a document round trip unchanged")
    func decodePreservesOutOfRangeValues() throws {
        // Storage never validates or rewrites: a document written by an older
        // build loads exactly as saved, and only saturates when it runs.
        let blocks = [
            Block(kind: .forward(.literal(1e7))),
            Block(kind: .repeatBlock(count: .literal(1e11), body: [])),
        ]
        let data = try JSONEncoder().encode(blocks)
        let decoded = try JSONDecoder().decode([Block].self, from: data)
        #expect(decoded.map(\.kind) == blocks.map(\.kind))
    }
}
