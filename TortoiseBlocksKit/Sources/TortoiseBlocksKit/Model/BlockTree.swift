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

    /// Inserts `block` at `index` in the top level (`containerID == nil`) or
    /// in the body of the repeat with `containerID`; the index is clamped to
    /// the valid range. Returns `nil` if the container does not exist or is
    /// not a repeat.
    public static func inserting(
        _ block: Block, at index: Int, inBodyOf containerID: UUID?, in blocks: [Block]
    ) -> [Block]? {
        guard let containerID else {
            var copy = blocks
            copy.insert(block, at: min(max(0, index), blocks.count))
            return copy
        }
        for (i, candidate) in blocks.enumerated() {
            if candidate.id == containerID {
                guard case .repeatBlock(let count, let body) = candidate.kind else { return nil }
                var newBody = body
                newBody.insert(block, at: min(max(0, index), body.count))
                var copy = blocks
                copy[i].kind = .repeatBlock(count: count, body: newBody)
                return copy
            }
            if case .repeatBlock(let count, let body) = candidate.kind,
                let newBody = inserting(block, at: index, inBodyOf: containerID, in: body)
            {
                var copy = blocks
                copy[i].kind = .repeatBlock(count: count, body: newBody)
                return copy
            }
        }
        return nil
    }

    /// Moves an existing block to `index` in the given container (drag &
    /// drop). The index refers to the tree *before* removal — same-list
    /// forward moves are adjusted automatically. Dropping a block inside its
    /// own subtree returns `nil` (the destination vanishes with the
    /// extraction), as does an unknown block or container.
    public static func moving(
        blockWithID id: UUID, toIndex: Int, inBodyOf containerID: UUID?, in blocks: [Block]
    ) -> [Block]? {
        guard
            let (block, sourceContainer, sourceIndex, removedTree) =
                extracting(blockWithID: id, from: blocks, container: nil)
        else { return nil }
        var index = toIndex
        if sourceContainer == containerID, sourceIndex < toIndex {
            index -= 1
        }
        return inserting(block, at: index, inBodyOf: containerID, in: removedTree)
    }

    /// Removes the block, reporting where it was: (block, its container's
    /// ID or nil for top level, its index there, the remaining tree).
    private static func extracting(
        blockWithID id: UUID, from blocks: [Block], container: UUID?
    ) -> (block: Block, containerID: UUID?, index: Int, tree: [Block])? {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            var copy = blocks
            let block = copy.remove(at: index)
            return (block, container, index, copy)
        }
        for (i, candidate) in blocks.enumerated() {
            if case .repeatBlock(let count, let body) = candidate.kind,
                let (block, containerID, index, newBody) =
                    extracting(blockWithID: id, from: body, container: candidate.id)
            {
                var copy = blocks
                copy[i].kind = .repeatBlock(count: count, body: newBody)
                return (block, containerID, index, copy)
            }
        }
        return nil
    }

    /// Variable names referenced anywhere in the tree — set/add targets and
    /// `NumberValue.variable` slots alike — in first-appearance order,
    /// without duplicates. This *is* the set of existing variables: there is
    /// no registry, a name exists exactly as long as something mentions it.
    public static func usedVariableNames(in blocks: [Block]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        func record(_ name: String) {
            if seen.insert(name).inserted { names.append(name) }
        }
        func visit(_ value: NumberValue) {
            if case .variable(let name) = value { record(name) }
        }
        func walk(_ blocks: [Block]) {
            for block in blocks {
                switch block.kind {
                case .forward(let value), .backward(let value), .turnRight(let value),
                    .turnLeft(let value), .penWidth(let value):
                    visit(value)
                case .home, .penUp, .penDown, .penColor, .fillColor, .beginFill, .endFill:
                    break
                case .setVariable(let name, let value), .addVariable(let name, let value):
                    record(name)
                    visit(value)
                case .repeatBlock(let count, let body):
                    visit(count)
                    walk(body)
                }
            }
        }
        walk(blocks)
        return names
    }

    /// Renames a variable across the whole tree (set/add targets and value
    /// slots). Returns `nil` when nothing referenced `oldName` or the names
    /// are equal — a no-op for the caller, like every other edit here.
    public static func renamingVariable(
        _ oldName: String, to newName: String, in blocks: [Block]
    ) -> [Block]? {
        guard oldName != newName else { return nil }
        var changed = false
        func renamed(_ value: NumberValue) -> NumberValue {
            guard case .variable(oldName) = value else { return value }
            changed = true
            return .variable(newName)
        }
        func renamed(_ name: String) -> String {
            guard name == oldName else { return name }
            changed = true
            return newName
        }
        func walk(_ blocks: [Block]) -> [Block] {
            blocks.map { block in
                var block = block
                switch block.kind {
                case .forward(let value): block.kind = .forward(renamed(value))
                case .backward(let value): block.kind = .backward(renamed(value))
                case .turnRight(let value): block.kind = .turnRight(renamed(value))
                case .turnLeft(let value): block.kind = .turnLeft(renamed(value))
                case .penWidth(let value): block.kind = .penWidth(renamed(value))
                case .home, .penUp, .penDown, .penColor, .fillColor, .beginFill, .endFill:
                    break
                case .setVariable(let name, let value):
                    block.kind = .setVariable(name: renamed(name), value: renamed(value))
                case .addVariable(let name, let value):
                    block.kind = .addVariable(name: renamed(name), value: renamed(value))
                case .repeatBlock(let count, let body):
                    block.kind = .repeatBlock(count: renamed(count), body: walk(body))
                }
                return block
            }
        }
        let new = walk(blocks)
        return changed ? new : nil
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
