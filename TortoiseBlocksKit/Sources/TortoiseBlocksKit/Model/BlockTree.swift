import Foundation

/// Pure editing operations over a block tree.
///
/// Every operation returns a *new* tree (value semantics) or `nil` when it
/// cannot apply — the caller treats `nil` as a no-op and, crucially, does not
/// register an undo step for it. Undo itself is just "swap back the previous
/// tree", which these pure functions make trivial.
public enum BlockTree {
    /// Finds a block anywhere in the tree.
    public static func block(withID id: UUID, in blocks: [Block]) -> Block? {
        for block in blocks {
            if block.id == id { return block }
            if case .repeatBlock(_, let body) = block.kind,
                let found = Self.block(withID: id, in: body)
            {
                return found
            }
        }
        return nil
    }

    /// Appends `block` to the top level (`containerID == nil`) or to the
    /// body of the repeat block with `containerID`.
    /// Returns `nil` if the container does not exist or is not a repeat.
    public static func appending(
        _ block: Block, toBodyOf containerID: UUID?, in blocks: [Block]
    ) -> [Block]? {
        guard let containerID else { return blocks + [block] }
        for (index, candidate) in blocks.enumerated() {
            if candidate.id == containerID {
                guard case .repeatBlock(let count, let body) = candidate.kind else { return nil }
                var copy = blocks
                copy[index].kind = .repeatBlock(count: count, body: body + [block])
                return copy
            }
            if case .repeatBlock(let count, let body) = candidate.kind,
                let newBody = appending(block, toBodyOf: containerID, in: body)
            {
                var copy = blocks
                copy[index].kind = .repeatBlock(count: count, body: newBody)
                return copy
            }
        }
        return nil
    }

    /// Removes the block (and its whole subtree). Returns `nil` if not found.
    public static func removing(blockWithID id: UUID, from blocks: [Block]) -> [Block]? {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            var copy = blocks
            copy.remove(at: index)
            return copy
        }
        for (index, block) in blocks.enumerated() {
            if case .repeatBlock(let count, let body) = block.kind,
                let newBody = removing(blockWithID: id, from: body)
            {
                var copy = blocks
                copy[index].kind = .repeatBlock(count: count, body: newBody)
                return copy
            }
        }
        return nil
    }

    /// Swaps the block with the sibling `offset` positions away (±1 for the
    /// list-reorder buttons). Returns `nil` when not found or at the edge of
    /// its sibling list — both are no-ops for the caller.
    public static func moving(
        blockWithID id: UUID, by offset: Int, in blocks: [Block]
    ) -> [Block]? {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            let target = index + offset
            guard blocks.indices.contains(target) else { return nil }
            var copy = blocks
            copy.swapAt(index, target)
            return copy
        }
        for (index, block) in blocks.enumerated() {
            if case .repeatBlock(let count, let body) = block.kind,
                let newBody = moving(blockWithID: id, by: offset, in: body)
            {
                var copy = blocks
                copy[index].kind = .repeatBlock(count: count, body: newBody)
                return copy
            }
        }
        return nil
    }

    /// Replaces the block's kind (argument edits build the new kind from the
    /// old one, preserving a repeat's body). Returns `nil` if not found.
    public static func updatingKind(
        of id: UUID, to kind: BlockKind, in blocks: [Block]
    ) -> [Block]? {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            var copy = blocks
            copy[index].kind = kind
            return copy
        }
        for (index, block) in blocks.enumerated() {
            if case .repeatBlock(let count, let body) = block.kind,
                let newBody = updatingKind(of: id, to: kind, in: body)
            {
                var copy = blocks
                copy[index].kind = .repeatBlock(count: count, body: newBody)
                return copy
            }
        }
        return nil
    }
}
