import Foundation
import Observation
import TortoiseBlocksKit

/// The editor's shared state: the block tree, the insertion target, and
/// undo/redo. All mutations go through `BlockTree`'s pure functions —
/// undo is just swapping back the previous tree snapshot.
@Observable
@MainActor
final class WorkspaceModel {
    private(set) var blocks: [Block] = []

    /// The repeat block new palette blocks are appended into
    /// (nil = top level). Toggled from the repeat row's target button.
    var insertionTargetID: UUID?

    private(set) var canUndo = false
    private(set) var canRedo = false

    // The model owns its manager for now; the DocumentGroup document (M5)
    // will supply the document-scoped one instead.
    @ObservationIgnored private let undoManager = UndoManager()

    // MARK: - Editing

    func add(_ kind: BlockKind) {
        let block = Block(kind: kind)
        // Fall back to top level if the target has been deleted meanwhile.
        let target = validatedInsertionTarget()
        guard let new = BlockTree.appending(block, toBodyOf: target, in: blocks) else { return }
        commit(new)
        // Adding a repeat makes it the natural next target.
        if case .repeatBlock = kind {
            insertionTargetID = block.id
        }
    }

    func delete(_ id: UUID) {
        guard let new = BlockTree.removing(blockWithID: id, from: blocks) else { return }
        commit(new)
        if validatedInsertionTarget() == nil {
            insertionTargetID = nil
        }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let new = BlockTree.moving(blockWithID: id, by: offset, in: blocks) else { return }
        commit(new)
    }

    func updateKind(of id: UUID, to kind: BlockKind) {
        guard let new = BlockTree.updatingKind(of: id, to: kind, in: blocks) else { return }
        commit(new)
    }

    /// Handles a block drop at (containerID, index). A payload whose ID
    /// already exists in the tree is *moved* (workspace drag); an unknown ID
    /// is *inserted* (palette drag). Returns whether the drop was applied —
    /// identity moves and invalid targets (own subtree, vanished container)
    /// are rejected without touching the undo stack.
    @discardableResult
    func handleDrop(_ dropped: Block, at index: Int, inBodyOf containerID: UUID?) -> Bool {
        let new: [Block]?
        if BlockTree.block(withID: dropped.id, in: blocks) != nil {
            new = BlockTree.moving(
                blockWithID: dropped.id, toIndex: index, inBodyOf: containerID, in: blocks)
        } else {
            new = BlockTree.inserting(dropped, at: index, inBodyOf: containerID, in: blocks)
        }
        guard let new, new != blocks else { return false }
        commit(new)
        return true
    }

    // MARK: - Undo / Redo

    func undo() {
        undoManager.undo()
        refreshUndoState()
    }

    func redo() {
        undoManager.redo()
        refreshUndoState()
    }

    // MARK: - Private

    private func validatedInsertionTarget() -> UUID? {
        guard let id = insertionTargetID,
            let block = BlockTree.block(withID: id, in: blocks),
            case .repeatBlock = block.kind
        else { return nil }
        return id
    }

    /// Replaces the tree, registering the inverse as undo. Re-entering from
    /// an undo registers the redo automatically (UndoManager semantics).
    private func commit(_ new: [Block]) {
        let old = blocks
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.commit(old)
            }
        }
        blocks = new
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}
