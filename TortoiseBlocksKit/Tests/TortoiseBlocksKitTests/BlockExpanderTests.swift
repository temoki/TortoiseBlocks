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
        _ blocks: [Block], seed: UInt64 = 1, limit: Int = BlockExpander.defaultLimit,
        nestingLimit: Int = BlockExpander.defaultNestingLimit
    ) throws -> [ExpandedCommand] {
        var rng = SeededRNG(seed: seed)
        return try BlockExpander.expand(
            blocks, using: &rng, limit: limit, nestingLimit: nestingLimit)
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
            Block(kind: .penColor(.literal(.red))),
            Block(kind: .penWidth(.literal(3))),
            Block(kind: .fillColor(.literal(.cyan))),
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
        #expect(
            expanded.map(\.command) == [
                .forward(10), .rotate(90), .forward(10), .rotate(90), .forward(10), .rotate(90),
            ])
        // Highlighting targets the body blocks, not the repeat container.
        #expect(
            expanded.map(\.blockID) == [
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
        #expect(
            try expand([Block(kind: .repeatBlock(count: .literal(2.6), body: body))]).count == 3)
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

    @Test("a random color inside a repeat is re-evaluated every iteration, never white")
    func randomColorInsideRepeatReevaluates() throws {
        let blocks = [
            Block(
                kind: .repeatBlock(
                    count: .literal(50),
                    body: [Block(kind: .penColor(.random))]
                ))
        ]
        let colors = try expand(blocks).compactMap { expanded -> TortoiseCore.Color? in
            guard case .penColor(let color) = expanded.command else { return nil }
            return color
        }
        #expect(colors.count == 50)
        #expect(!colors.contains(BlockColor.white.tortoiseColor))
        #expect(Set(colors).count > 1)
    }

    @Test("subtract, multiply, and divide do box arithmetic in order")
    func arithmeticOperations() throws {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(20))),
            Block(kind: .subtractVariable(name: "🌟", value: .literal(4))),
            Block(kind: .multiplyVariable(name: "🌟", value: .literal(3))),
            Block(kind: .divideVariable(name: "🌟", value: .literal(2))),
            Block(kind: .forward(.variable("🌟"))),
        ]
        // (20 − 4) × 3 ÷ 2 = 24
        #expect(try expand(blocks).map(\.command) == [.forward(24)])
    }

    @Test("unset boxes start at 0 for every operation")
    func arithmeticOnUnsetBoxes() throws {
        let blocks = [
            Block(kind: .subtractVariable(name: "あ", value: .literal(5))),
            Block(kind: .multiplyVariable(name: "い", value: .literal(5))),
            Block(kind: .forward(.variable("あ"))),
            Block(kind: .forward(.variable("い"))),
        ]
        #expect(try expand(blocks).map(\.command) == [.forward(-5), .forward(0)])
    }

    @Test("dividing by zero is a no-op — the box keeps its value")
    func divideByZero() throws {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(12))),
            Block(kind: .divideVariable(name: "🌟", value: .literal(0))),
            // A dice that can only roll zero is guarded too.
            Block(kind: .divideVariable(name: "🌟", value: .random(min: 0, max: 0))),
            Block(kind: .forward(.variable("🌟"))),
        ]
        #expect(try expand(blocks).map(\.command) == [.forward(12)])
    }

    @Test("an unset variable reads 0; a set one reads its stored value")
    func variableSetAndRead() throws {
        let blocks = [
            Block(kind: .forward(.variable("🌟"))),
            Block(kind: .setVariable(name: "🌟", value: .literal(60))),
            Block(kind: .forward(.variable("🌟"))),
        ]
        #expect(try expand(blocks).map(\.command) == [.forward(0), .forward(60)])
    }

    @Test("set/add emit no command — the highlight stream skips them")
    func assignmentsEmitNothing() throws {
        let forward = Block(kind: .forward(.literal(10)))
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(1))),
            forward,
            Block(kind: .addVariable(name: "🌟", value: .literal(1))),
        ]
        #expect(try expand(blocks).map(\.blockID) == [forward.id])
    }

    @Test("add accumulates across iterations — the spiral grows")
    func addInsideRepeatAccumulates() throws {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(5))),
            Block(
                kind: .repeatBlock(
                    count: .literal(3),
                    body: [
                        Block(kind: .forward(.variable("🌟"))),
                        Block(kind: .addVariable(name: "🌟", value: .literal(10))),
                    ]
                )),
        ]
        let distances = try expand(blocks).compactMap { expanded -> Double? in
            guard case .forward(let distance) = expanded.command else { return nil }
            return distance
        }
        #expect(distances == [5, 15, 25])
    }

    @Test("a variable repeat count is evaluated once at entry")
    func variableCountEvaluatedOnce() throws {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(3))),
            Block(
                kind: .repeatBlock(
                    count: .variable("🌟"),
                    body: [
                        Block(kind: .home),
                        Block(kind: .setVariable(name: "🌟", value: .literal(100))),
                    ]
                )),
        ]
        #expect(try expand(blocks).count == 3)
    }

    @Test("a dice stored in a box is rolled once and reused")
    func randomStoredInVariableRollsOnce() throws {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .random(min: 0, max: 1000))),
            Block(
                kind: .repeatBlock(
                    count: .literal(3),
                    body: [Block(kind: .forward(.variable("🌟")))]
                )),
        ]
        let distances = try expand(blocks).compactMap { expanded -> Double? in
            guard case .forward(let distance) = expanded.command else { return nil }
            return distance
        }
        #expect(distances.count == 3)
        #expect(Set(distances).count == 1)
        #expect((0...1000).contains(distances[0]))
    }

    @Test("an assignment-only runaway loop still hits the step limit")
    func assignmentOnlyRunaway() {
        let runaway = [
            Block(
                kind: .repeatBlock(
                    count: .literal(200),
                    body: [
                        Block(
                            kind: .repeatBlock(
                                count: .literal(200),
                                body: [
                                    Block(kind: .addVariable(name: "🌟", value: .literal(1)))
                                ]
                            ))
                    ]
                ))
        ]
        #expect(throws: BlockExpansionError.commandLimitExceeded(limit: 10_000)) {
            try expand(runaway)
        }
    }

    @Test(
        "every comparison operator matches its truth table",
        arguments: [
            (Comparison.less, true, false, false),
            (.lessOrEqual, true, true, false),
            (.equal, false, true, false),
            (.greaterOrEqual, false, true, true),
            (.greater, false, false, true),
        ])
    func comparisonTruthTable(op: Comparison, below: Bool, equal: Bool, above: Bool) {
        #expect(op.holds(1, 2) == below)
        #expect(op.holds(2, 2) == equal)
        #expect(op.holds(3, 2) == above)
    }

    @Test("an if runs its body exactly when the condition holds")
    func ifBranches() throws {
        func ifBlock(_ comparison: Comparison) -> Block {
            Block(
                kind: .ifBlock(
                    condition: Condition(
                        lhs: .literal(1), comparison: comparison, rhs: .literal(2)),
                    body: [Block(kind: .home)], elseBody: nil))
        }
        #expect(try expand([ifBlock(.less)]).map(\.command) == [.home])
        #expect(try expand([ifBlock(.greater)]).isEmpty)
    }

    @Test("a counter-gated if fires from the matching iteration on")
    func counterGatedIf() throws {
        // くりかえし×5 { 🌟 に 1 をたす / もし 🌟 ≥ 3 なら { home } }
        let blocks = [
            Block(
                kind: .repeatBlock(
                    count: .literal(5),
                    body: [
                        Block(kind: .addVariable(name: "🌟", value: .literal(1))),
                        Block(
                            kind: .ifBlock(
                                condition: Condition(
                                    lhs: .variable("🌟"), comparison: .greaterOrEqual,
                                    rhs: .literal(3)),
                                body: [Block(kind: .home)], elseBody: nil)),
                    ]
                ))
        ]
        // Fires on iterations 3, 4, 5.
        #expect(try expand(blocks).map(\.command) == [.home, .home, .home])
    }

    @Test("dice in a condition re-roll on every encounter")
    func diceConditionRerolls() throws {
        let blocks = [
            Block(
                kind: .repeatBlock(
                    count: .literal(50),
                    body: [
                        Block(
                            kind: .ifBlock(
                                condition: Condition(
                                    lhs: .random(min: 0, max: 1), comparison: .greaterOrEqual,
                                    rhs: .literal(0.5)),
                                body: [Block(kind: .home)], elseBody: nil))
                    ]
                ))
        ]
        let count = try expand(blocks).count
        // A single evaluation would give 0 or 50; re-rolling lands between.
        #expect(count > 0 && count < 50)
    }

    @Test("the else mouth runs exactly when the condition fails")
    func elseBranches() throws {
        func ifElse(_ comparison: Comparison) -> Block {
            Block(
                kind: .ifBlock(
                    condition: Condition(
                        lhs: .literal(1), comparison: comparison, rhs: .literal(2)),
                    body: [Block(kind: .home)],
                    elseBody: [Block(kind: .penUp)]
                ))
        }
        #expect(try expand([ifElse(.less)]).map(\.command) == [.home])
        #expect(try expand([ifElse(.greater)]).map(\.command) == [.penUp])
    }

    @Test("one roll decides both mouths — then/else always sum to the iterations")
    func diceElseExclusivity() throws {
        let blocks = [
            Block(
                kind: .repeatBlock(
                    count: .literal(50),
                    body: [
                        Block(
                            kind: .ifBlock(
                                condition: Condition(
                                    lhs: .random(min: 0, max: 1), comparison: .greaterOrEqual,
                                    rhs: .literal(0.5)),
                                body: [Block(kind: .home)],
                                elseBody: [Block(kind: .penUp)]
                            ))
                    ]
                ))
        ]
        let commands = try expand(blocks).map(\.command)
        // Two separate ifs with complementary dice conditions could emit
        // anywhere from 0 to 100 commands; the else guarantees exactly one
        // mouth per iteration.
        #expect(commands.count == 50)
        #expect(commands.contains(.home))
        #expect(commands.contains(.penUp))
    }

    @Test("a counter flips from else to then at the boundary")
    func counterBoundaryElse() throws {
        let blocks = [
            Block(
                kind: .repeatBlock(
                    count: .literal(5),
                    body: [
                        Block(kind: .addVariable(name: "🌟", value: .literal(1))),
                        Block(
                            kind: .ifBlock(
                                condition: Condition(
                                    lhs: .variable("🌟"), comparison: .greaterOrEqual,
                                    rhs: .literal(3)),
                                body: [Block(kind: .home)],
                                elseBody: [Block(kind: .penUp)]
                            )),
                    ]
                ))
        ]
        #expect(try expand(blocks).map(\.command) == [.penUp, .penUp, .home, .home, .home])
    }

    @Test("a false-branch-only runaway loop still hits the step limit")
    func falseBranchRunaway() {
        let runaway = [
            Block(
                kind: .repeatBlock(
                    count: .literal(200),
                    body: [
                        Block(
                            kind: .repeatBlock(
                                count: .literal(200),
                                body: [
                                    Block(
                                        kind: .ifBlock(
                                            condition: Condition(
                                                lhs: .literal(1), comparison: .greater,
                                                rhs: .literal(2)),
                                            body: [Block(kind: .home)], elseBody: nil))
                                ]
                            ))
                    ]
                ))
        ]
        #expect(throws: BlockExpansionError.commandLimitExceeded(limit: 10_000)) {
            try expand(runaway)
        }
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

    // MARK: - My blocks (define / call)

    @Test("a call expands the definition's body, tagged with the body's IDs")
    func callExpandsDefinition() throws {
        let forward = Block(kind: .forward(.literal(10)))
        let turn = Block(kind: .turnRight(.literal(90)))
        let define = Block(kind: .defineBlock(name: "き", body: [forward, turn]))
        let call = Block(kind: .callBlock(name: "き"))

        let expanded = try expand([define, call])
        #expect(expanded.map(\.command) == [.forward(10), .rotate(90)])
        // The definition's rows light up during playback, not the call —
        // a call emits no command of its own (like set/add and the if test).
        #expect(expanded.map(\.blockID) == [forward.id, turn.id])
    }

    @Test("a call above the block it calls still works (two passes)")
    func callBeforeDefinition() throws {
        let call = Block(kind: .callBlock(name: "き"))
        let define = Block(
            kind: .defineBlock(name: "き", body: [Block(kind: .forward(.literal(10)))]))
        #expect(try expand([call, define]).map(\.command) == [.forward(10)])
    }

    @Test("a definition nested inside a container is still collected")
    func definitionInsideContainer() throws {
        let define = Block(
            kind: .defineBlock(name: "き", body: [Block(kind: .home)]))
        let outer = Block(kind: .repeatBlock(count: .literal(1), body: [define]))
        #expect(try expand([Block(kind: .callBlock(name: "き")), outer]).count == 1)
    }

    @Test("a call to a name nothing defines is a no-op")
    func undefinedCallIsNoOp() throws {
        let blocks = [
            Block(kind: .callBlock(name: "ない")),
            Block(kind: .home),
        ]
        #expect(try expand(blocks).map(\.command) == [.home])
    }

    @Test("the first definition of a name wins")
    func firstDefinitionWins() throws {
        let blocks = [
            Block(kind: .defineBlock(name: "き", body: [Block(kind: .forward(.literal(1)))])),
            Block(kind: .defineBlock(name: "き", body: [Block(kind: .forward(.literal(2)))])),
            Block(kind: .callBlock(name: "き")),
        ]
        #expect(try expand(blocks).map(\.command) == [.forward(1)])
    }

    @Test("reaching a definition draws nothing but charges a step")
    func definitionDrawsNothingAndCharges() throws {
        let define = Block(kind: .defineBlock(name: "き", body: [Block(kind: .home)]))
        #expect(try expand([define]).isEmpty)
        // A step each, though neither draws: one definition fits under a limit
        // of 1 and two do not.
        #expect(throws: BlockExpansionError.commandLimitExceeded(limit: 1)) {
            try expand([define, define], limit: 1)
        }
    }

    @Test("recursion terminated by a condition draws a fractal")
    func boundedRecursionDrawsFractal() throws {
        // The whole point of the feature: a block that calls itself, held to a
        // depth by a box and an if — a two-branch tree. Halving rather than
        // the ×0.6 a child would actually pick, so the arithmetic is exact in
        // binary and the assertions below can be equalities.
        let define = Block(
            kind: .defineBlock(
                name: "き",
                body: [
                    Block(
                        kind: .ifBlock(
                            condition: Condition(
                                lhs: .variable("🌟"), comparison: .greater, rhs: .literal(6)),
                            body: [
                                Block(kind: .forward(.variable("🌟"))),
                                Block(kind: .multiplyVariable(name: "🌟", value: .literal(0.5))),
                                Block(kind: .turnRight(.literal(28))),
                                Block(kind: .callBlock(name: "き")),
                                Block(kind: .turnLeft(.literal(56))),
                                Block(kind: .callBlock(name: "き")),
                                Block(kind: .turnRight(.literal(28))),
                                Block(kind: .divideVariable(name: "🌟", value: .literal(0.5))),
                                Block(kind: .backward(.variable("🌟"))),
                            ],
                            elseBody: nil))
                ]))
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(70))),
            Block(kind: .callBlock(name: "き")),
            define,
        ]
        // 70 → 35 → 17.5 → 8.75 → 4.375 stops, so 1+2+4+8 = 15 branches are
        // drawn, each one forward + three turns + one backward.
        let expanded = try expand(blocks)
        #expect(expanded.count == 15 * 5)
        // A box wrapped in ×0.5 … ÷0.5 around the calls comes back to where it
        // started, which is what makes one global box enough for a fractal —
        // the last thing the outermost call does is retrace its own trunk.
        #expect(expanded.last?.command == .forward(-70))
    }

    @Test("runaway recursion throws instead of overflowing the stack")
    func recursionLimitThrows() {
        let blocks = [
            Block(kind: .callBlock(name: "き")),
            Block(
                kind: .defineBlock(
                    name: "き",
                    body: [
                        Block(kind: .forward(.literal(10))),
                        Block(kind: .callBlock(name: "き")),
                    ])),
        ]
        // Reaching this expectation at all is the assertion: the depth is
        // measured against a debug build's stack (see `defaultNestingLimit`),
        // and a limit set too high crashes the test process instead of
        // failing it.
        #expect(
            throws: BlockExpansionError.nestingLimitExceeded(
                limit: BlockExpander.defaultNestingLimit)
        ) {
            try expand(blocks)
        }
    }

    @Test("mutual recursion counts against the same depth")
    func mutualRecursionThrows() {
        let blocks = [
            Block(kind: .callBlock(name: "あ")),
            Block(kind: .defineBlock(name: "あ", body: [Block(kind: .callBlock(name: "い"))])),
            Block(kind: .defineBlock(name: "い", body: [Block(kind: .callBlock(name: "あ"))])),
        ]
        #expect(
            throws: BlockExpansionError.nestingLimitExceeded(
                limit: BlockExpander.defaultNestingLimit)
        ) {
            try expand(blocks)
        }
    }

    @Test("nesting counts bodies as well as calls")
    func nestedBodiesCountTowardTheLimit() throws {
        // Every kind of descent costs the same stack, so all of them are
        // bounded by the one limit — a definition wrapped in repeats spends
        // several levels per call, which is exactly the case a call-only
        // counter would have missed.
        func nested(_ depth: Int) -> [Block] {
            var body = [Block(kind: .home)]
            for _ in 0..<depth {
                body = [Block(kind: .repeatBlock(count: .literal(1), body: body))]
            }
            return body
        }
        #expect(try expand(nested(3), nestingLimit: 4).count == 1)
        #expect(throws: BlockExpansionError.nestingLimitExceeded(limit: 2)) {
            try expand(nested(3), nestingLimit: 2)
        }
    }

    @Test("a custom nesting limit applies, and calls still cost steps")
    func customNestingLimit() throws {
        let blocks = [
            Block(kind: .callBlock(name: "き")),
            Block(kind: .defineBlock(name: "き", body: [Block(kind: .callBlock(name: "き"))])),
        ]
        #expect(throws: BlockExpansionError.nestingLimitExceeded(limit: 3)) {
            try expand(blocks, nestingLimit: 3)
        }
        // A call-only loop is bounded by the step cap too, not only by depth:
        // this one is shallow and still can't run away.
        let loop = [
            Block(
                kind: .repeatBlock(
                    count: .literal(1000),
                    body: [Block(kind: .callBlock(name: "き"))])),
            Block(kind: .defineBlock(name: "き", body: [])),
        ]
        #expect(throws: BlockExpansionError.commandLimitExceeded(limit: 20)) {
            try expand(loop, limit: 20)
        }
    }
}
