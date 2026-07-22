import Foundation
import Testing

@testable import TortoiseBlocksKit

@Suite("BlockTree editing")
struct BlockTreeTests {
    // Fixture: [forward, repeat(2) { turnRight, repeat(3) { home } }]
    private let forward = Block(kind: .forward(.literal(100)))
    private let turn = Block(kind: .turnRight(.literal(90)))
    private let home = Block(kind: .home)
    private var innerRepeat: Block
    private var outerRepeat: Block
    private var tree: [Block]

    init() {
        innerRepeat = Block(kind: .repeatBlock(count: .literal(3), body: [home]))
        outerRepeat = Block(kind: .repeatBlock(count: .literal(2), body: [turn, innerRepeat]))
        tree = [forward, outerRepeat]
    }

    @Test("find locates deeply nested blocks")
    func findNested() {
        #expect(BlockTree.block(withID: home.id, in: tree)?.kind == .home)
        #expect(BlockTree.block(withID: UUID(), in: tree) == nil)
    }

    @Test("append to top level")
    func appendTopLevel() throws {
        let new = Block(kind: .penUp)
        let result = try #require(BlockTree.appending(new, toBodyOf: nil, in: tree))
        #expect(result.count == 3)
        #expect(result.last?.id == new.id)
    }

    @Test("append into a nested repeat body")
    func appendNested() throws {
        let new = Block(kind: .penDown)
        let result = try #require(BlockTree.appending(new, toBodyOf: innerRepeat.id, in: tree))
        guard
            case .repeatBlock(_, let outerBody) = result[1].kind,
            case .repeatBlock(_, let innerBody) = outerBody[1].kind
        else {
            Issue.record("tree shape changed unexpectedly")
            return
        }
        #expect(innerBody.map(\.id) == [home.id, new.id])
    }

    @Test("append into a missing or non-repeat container is a no-op (nil)")
    func appendInvalidContainer() {
        let new = Block(kind: .penUp)
        #expect(BlockTree.appending(new, toBodyOf: UUID(), in: tree) == nil)
        #expect(BlockTree.appending(new, toBodyOf: forward.id, in: tree) == nil)
    }

    @Test("remove a nested block")
    func removeNested() throws {
        let result = try #require(BlockTree.removing(blockWithID: home.id, from: tree))
        #expect(BlockTree.block(withID: home.id, in: result) == nil)
        // Everything else survives.
        #expect(BlockTree.block(withID: turn.id, in: result) != nil)
        #expect(BlockTree.removing(blockWithID: UUID(), from: tree) == nil)
    }

    @Test("removing a repeat removes its subtree")
    func removeSubtree() throws {
        let result = try #require(BlockTree.removing(blockWithID: outerRepeat.id, from: tree))
        #expect(result.map(\.id) == [forward.id])
        #expect(BlockTree.block(withID: home.id, in: result) == nil)
    }

    @Test("move swaps with a sibling; edges are no-ops (nil)")
    func moveWithinSiblings() throws {
        let moved = try #require(BlockTree.moving(blockWithID: forward.id, by: 1, in: tree))
        #expect(moved.map(\.id) == [outerRepeat.id, forward.id])
        // Top edge / bottom edge.
        #expect(BlockTree.moving(blockWithID: forward.id, by: -1, in: tree) == nil)
        #expect(BlockTree.moving(blockWithID: outerRepeat.id, by: 1, in: tree) == nil)
    }

    @Test("move works inside a nested body")
    func moveNested() throws {
        let result = try #require(BlockTree.moving(blockWithID: innerRepeat.id, by: -1, in: tree))
        guard case .repeatBlock(_, let outerBody) = result[1].kind else {
            Issue.record("outer repeat missing")
            return
        }
        #expect(outerBody.map(\.id) == [innerRepeat.id, turn.id])
    }

    @Test("insert at an index, top level and nested, with clamping")
    func insertAtIndex() throws {
        let new = Block(kind: .penUp)
        let top = try #require(BlockTree.inserting(new, at: 1, inBodyOf: nil, in: tree))
        #expect(top.map(\.id) == [forward.id, new.id, outerRepeat.id])

        let clamped = try #require(BlockTree.inserting(new, at: 99, inBodyOf: nil, in: tree))
        #expect(clamped.last?.id == new.id)

        let nested = try #require(
            BlockTree.inserting(new, at: 0, inBodyOf: outerRepeat.id, in: tree))
        guard case .repeatBlock(_, let body) = nested[1].kind else {
            Issue.record("outer repeat missing")
            return
        }
        #expect(body.map(\.id) == [new.id, turn.id, innerRepeat.id])

        #expect(BlockTree.inserting(new, at: 0, inBodyOf: forward.id, in: tree) == nil)
    }

    @Test("move to an index within the same list adjusts for the removal")
    func moveToIndexSameList() throws {
        // Gap index 2 (after outerRepeat) for the block at index 0.
        let result = try #require(
            BlockTree.moving(blockWithID: forward.id, toIndex: 2, inBodyOf: nil, in: tree))
        #expect(result.map(\.id) == [outerRepeat.id, forward.id])

        // Moving onto its own position is an identity operation.
        let identity = try #require(
            BlockTree.moving(blockWithID: forward.id, toIndex: 0, inBodyOf: nil, in: tree))
        #expect(identity == tree)
    }

    @Test("move across containers, in and out of a repeat body")
    func moveAcrossContainers() throws {
        // Top-level forward into the inner repeat's body.
        let inward = try #require(
            BlockTree.moving(
                blockWithID: forward.id, toIndex: 0, inBodyOf: innerRepeat.id, in: tree))
        #expect(inward.count == 1)
        guard
            case .repeatBlock(_, let outerBody) = inward[0].kind,
            case .repeatBlock(_, let innerBody) = outerBody[1].kind
        else {
            Issue.record("tree shape changed unexpectedly")
            return
        }
        #expect(innerBody.map(\.id) == [forward.id, home.id])

        // Nested home out to the top level.
        let outward = try #require(
            BlockTree.moving(blockWithID: home.id, toIndex: 0, inBodyOf: nil, in: tree))
        #expect(outward.first?.id == home.id)
        guard case .repeatBlock(_, let newOuter) = outward[2].kind,
            case .repeatBlock(_, let newInner) = newOuter[1].kind
        else {
            Issue.record("tree shape changed unexpectedly")
            return
        }
        #expect(newInner.isEmpty)
    }

    @Test("moving a repeat into its own subtree is rejected")
    func moveIntoOwnSubtree() {
        #expect(
            BlockTree.moving(
                blockWithID: outerRepeat.id, toIndex: 0, inBodyOf: innerRepeat.id, in: tree)
                == nil)
        #expect(
            BlockTree.moving(
                blockWithID: outerRepeat.id, toIndex: 0, inBodyOf: outerRepeat.id, in: tree)
                == nil)
    }

    @Test("usedVariableNames lists first appearances, slots and targets alike")
    func usedVariableNames() {
        #expect(BlockTree.usedVariableNames(in: tree).isEmpty)
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .literal(5))),
            Block(
                kind: .repeatBlock(
                    count: .variable("はやさ"),
                    body: [
                        Block(kind: .forward(.variable("🌟"))),
                        Block(kind: .addVariable(name: "💖", value: .variable("はやさ"))),
                    ]
                )),
        ]
        #expect(BlockTree.usedVariableNames(in: blocks) == ["🌟", "はやさ", "💖"])
    }

    @Test("renamingVariable rewrites every occurrence; unused names are no-ops")
    func renameVariable() throws {
        let blocks = [
            Block(kind: .setVariable(name: "🌟", value: .variable("🌟"))),
            Block(
                kind: .repeatBlock(
                    count: .variable("🌟"),
                    body: [Block(kind: .forward(.variable("🌟")))]
                )),
        ]
        let renamed = try #require(BlockTree.renamingVariable("🌟", to: "ほし", in: blocks))
        #expect(BlockTree.usedVariableNames(in: renamed) == ["ほし"])
        // Rename is an argument edit — block identity survives.
        #expect(renamed.map(\.id) == blocks.map(\.id))
        #expect(BlockTree.renamingVariable("💖", to: "ほし", in: blocks) == nil)
        #expect(BlockTree.renamingVariable("🌟", to: "🌟", in: blocks) == nil)
    }

    @Test("container edits work inside an if body")
    func ifContainerEdits() throws {
        let home = Block(kind: .home)
        let ifBlock = Block(
            kind: .ifBlock(
                condition: Condition(lhs: .literal(1), comparison: .less, rhs: .literal(2)),
                body: [home], elseBody: nil))

        let appended = try #require(
            BlockTree.appending(Block(kind: .penUp), toBodyOf: ifBlock.id, in: [ifBlock]))
        #expect(appended[0].kind.containerBody?.count == 2)

        let inserted = try #require(
            BlockTree.inserting(Block(kind: .penDown), at: 0, inBodyOf: ifBlock.id, in: [ifBlock]))
        #expect(inserted[0].kind.containerBody?.first?.kind == .penDown)

        let removed = try #require(BlockTree.removing(blockWithID: home.id, from: [ifBlock]))
        #expect(removed[0].kind.containerBody?.isEmpty == true)

        // Drag & drop from the top level into the if body.
        let outside = Block(kind: .forward(.literal(10)))
        let moved = try #require(
            BlockTree.moving(
                blockWithID: outside.id, toIndex: 0, inBodyOf: ifBlock.id,
                in: [outside, ifBlock]))
        #expect(moved.count == 1)
        #expect(moved[0].kind.containerBody?.map(\.id) == [outside.id, home.id])
    }

    @Test("usedVariableNames and rename reach into if conditions and both mouths")
    func variableNamesInConditions() throws {
        let blocks = [
            Block(
                kind: .ifBlock(
                    condition: Condition(
                        lhs: .variable("🌟"), comparison: .less, rhs: .variable("💖")),
                    body: [Block(kind: .forward(.variable("🍀")))],
                    elseBody: [Block(kind: .backward(.variable("うら")))]
                ))
        ]
        #expect(BlockTree.usedVariableNames(in: blocks) == ["🌟", "💖", "🍀", "うら"])
        let renamed = try #require(BlockTree.renamingVariable("うら", to: "おもて", in: blocks))
        #expect(BlockTree.usedVariableNames(in: renamed) == ["🌟", "💖", "🍀", "おもて"])
    }

    @Test("arithmetic blocks record and rename their box like set/add")
    func arithmeticVariableNames() throws {
        let blocks = [
            Block(kind: .subtractVariable(name: "🌟", value: .variable("💖"))),
            Block(kind: .multiplyVariable(name: "🍀", value: .literal(2))),
            Block(kind: .divideVariable(name: "🌟", value: .literal(2))),
        ]
        #expect(BlockTree.usedVariableNames(in: blocks) == ["🌟", "💖", "🍀"])
        let renamed = try #require(BlockTree.renamingVariable("🌟", to: "ほし", in: blocks))
        #expect(BlockTree.usedVariableNames(in: renamed) == ["ほし", "💖", "🍀"])
    }

    @Test("else-mouth edits: append, insert, cross-mouth move, rejections")
    func elseMouthEdits() throws {
        let thenHome = Block(kind: .home)
        let elsePenUp = Block(kind: .penUp)
        let ifBlock = Block(
            kind: .ifBlock(
                condition: Condition(lhs: .literal(1), comparison: .less, rhs: .literal(2)),
                body: [thenHome],
                elseBody: [elsePenUp]
            ))
        let elseAddress = BodyAddress(containerID: ifBlock.id, slot: .elseBody)

        let appended = try #require(
            BlockTree.appending(Block(kind: .penDown), toBodyAt: elseAddress, in: [ifBlock]))
        #expect(appended[0].kind.body(for: .elseBody)?.count == 2)
        // The then mouth is untouched.
        #expect(appended[0].kind.body(for: .body)?.map(\.id) == [thenHome.id])

        let inserted = try #require(
            BlockTree.inserting(Block(kind: .penDown), at: 0, inBodyAt: elseAddress, in: [ifBlock]))
        #expect(inserted[0].kind.body(for: .elseBody)?.first?.kind == .penDown)

        // Cross-mouth drag: then → else.
        let moved = try #require(
            BlockTree.moving(
                blockWithID: thenHome.id, toIndex: 0, inBodyAt: elseAddress, in: [ifBlock]))
        #expect(moved[0].kind.body(for: .body)?.isEmpty == true)
        #expect(moved[0].kind.body(for: .elseBody)?.map(\.id) == [thenHome.id, elsePenUp.id])

        // Same-list forward move inside the else mouth adjusts the index.
        let penDown = Block(kind: .penDown)
        let twoElse = Block(
            kind: .ifBlock(
                condition: Condition(lhs: .literal(1), comparison: .less, rhs: .literal(2)),
                body: [], elseBody: [elsePenUp, penDown]
            ))
        let sameList = try #require(
            BlockTree.moving(
                blockWithID: elsePenUp.id, toIndex: 2,
                inBodyAt: BodyAddress(containerID: twoElse.id, slot: .elseBody), in: [twoElse]))
        #expect(sameList[0].kind.body(for: .elseBody)?.map(\.id) == [penDown.id, elsePenUp.id])

        // Dropping the if into its own else mouth is rejected.
        #expect(
            BlockTree.moving(
                blockWithID: ifBlock.id, toIndex: 0, inBodyAt: elseAddress, in: [ifBlock])
                == nil)

        // The else mouth of an else-less if is not a valid target.
        let noElse = Block(
            kind: .ifBlock(
                condition: Condition(lhs: .literal(1), comparison: .less, rhs: .literal(2)),
                body: [], elseBody: nil
            ))
        #expect(
            BlockTree.appending(
                Block(kind: .home),
                toBodyAt: BodyAddress(containerID: noElse.id, slot: .elseBody), in: [noElse]) == nil
        )
    }

    @Test("update a nested block's kind in place")
    func updateNestedKind() throws {
        let result = try #require(
            BlockTree.updatingKind(of: turn.id, to: .turnLeft(.literal(45)), in: tree))
        guard case .repeatBlock(_, let outerBody) = result[1].kind else {
            Issue.record("outer repeat missing")
            return
        }
        #expect(outerBody[0].id == turn.id)
        #expect(outerBody[0].kind == .turnLeft(.literal(45)))
        #expect(BlockTree.updatingKind(of: UUID(), to: .home, in: tree) == nil)
    }
}
