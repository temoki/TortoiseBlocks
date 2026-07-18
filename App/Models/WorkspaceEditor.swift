import Foundation
import Observation
import SwiftUI
import TortoiseBlocksKit

/// Editor UI state that is not part of the document (never persisted).
@Observable
@MainActor
final class WorkspaceUIState {
    /// The container block (repeat/if) new palette blocks are appended into
    /// (nil = top level). Toggled from the container row's target button.
    var insertionTargetID: UUID?
}

/// Value-type editing facade over the document.
///
/// Every mutation goes through `BlockTree`'s pure functions, writes through
/// the document binding, and registers its inverse with the *document's*
/// UndoManager — so dirty state, autosave, and the standard Undo/Redo
/// commands all behave like any document app.
@MainActor
struct WorkspaceEditor {
    let document: Binding<BlocksDocument>
    let undoManager: UndoManager?
    let uiState: WorkspaceUIState

    var blocks: [Block] { document.wrappedValue.project.blocks }

    var insertionTargetID: UUID? {
        get { uiState.insertionTargetID }
        nonmutating set { uiState.insertionTargetID = newValue }
    }

    // Reading these in body stays fresh without observation: every edit,
    // undo, and redo mutates the document, which re-renders the view tree.
    var canUndo: Bool { undoManager?.canUndo ?? false }
    var canRedo: Bool { undoManager?.canRedo ?? false }

    // MARK: - Editing

    func add(_ kind: BlockKind) {
        let block = Block(kind: kind)
        // Fall back to top level if the target has been deleted meanwhile.
        let target = validatedInsertionTarget()
        guard let new = BlockTree.appending(block, toBodyOf: target, in: blocks) else { return }
        setBlocks(new)
        // Adding a container makes it the natural next target.
        if kind.containerBody != nil {
            insertionTargetID = block.id
        }
    }

    /// Replaces the (empty) tree with a sample program — goes through
    /// `setBlocks`, so it's undoable and dirties the document like any edit.
    func insertSample(_ blocks: [Block]) {
        setBlocks(blocks)
    }

    func delete(_ id: UUID) {
        guard let new = BlockTree.removing(blockWithID: id, from: blocks) else { return }
        setBlocks(new)
        if validatedInsertionTarget() == nil {
            insertionTargetID = nil
        }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let new = BlockTree.moving(blockWithID: id, by: offset, in: blocks) else { return }
        setBlocks(new)
    }

    func updateKind(of id: UUID, to kind: BlockKind) {
        guard let new = BlockTree.updatingKind(of: id, to: kind, in: blocks) else { return }
        setBlocks(new)
    }

    /// Handles a block drop at (containerID, index). A payload whose ID
    /// already exists in the tree is *moved* (workspace drag); an unknown ID
    /// is *inserted* (palette drag). Identity moves and invalid targets are
    /// rejected without touching the undo stack.
    @discardableResult
    func handleDrop(_ dropped: Block, at index: Int, inBodyOf containerID: UUID?) -> Bool {
        let new: [Block]?
        if BlockTree.block(withID: dropped.id, in: blocks) != nil {
            new = BlockTree.moving(
                blockWithID: dropped.id, toIndex: index, inBodyOf: containerID, in: blocks)
        } else {
            new = BlockTree.inserting(dropped, at: index, inBodyOf: containerID, in: blocks)
        }
        guard let new else { return false }
        return setBlocks(new)
    }

    // MARK: - Undo / Redo

    func undo() {
        undoManager?.undo()
    }

    func redo() {
        undoManager?.redo()
    }

    // MARK: - Private

    private func validatedInsertionTarget() -> UUID? {
        guard let id = uiState.insertionTargetID,
            let block = BlockTree.block(withID: id, in: blocks),
            block.kind.containerBody != nil
        else { return nil }
        return id
    }

    @discardableResult
    private func setBlocks(_ new: [Block]) -> Bool {
        guard new != blocks else { return false }
        Self.apply(new, to: document, undoManager: undoManager)
        return true
    }

    /// Writes the tree through the binding and registers the inverse;
    /// undoing re-enters here, which registers the redo automatically.
    private static func apply(
        _ value: [Block], to document: Binding<BlocksDocument>, undoManager: UndoManager?
    ) {
        let old = document.wrappedValue.project.blocks
        document.wrappedValue.project.blocks = value
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoManager) { manager in
            MainActor.assumeIsolated {
                apply(old, to: document, undoManager: manager)
            }
        }
    }
}
