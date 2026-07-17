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
