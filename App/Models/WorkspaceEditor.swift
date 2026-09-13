import Foundation
import Observation
import SwiftUI
import TortoiseBlocksKit

/// Editor UI state that is not part of the document (never persisted).
@Observable
@MainActor
final class WorkspaceUIState {
    /// The mouth (container + slot) new palette blocks are appended into
    /// (nil = top level). Toggled from the container/else rows' target
    /// buttons.
    var insertionTarget: BodyAddress?

    /// Whether the "delete everything?" confirmation is on screen (#48).
    ///
    /// It lives here rather than in the trash can's own `@State` because two
    /// places ask for it — the can and the Mac's menu — and there must be
    /// exactly one dialog: a second presentation modifier of the same kind
    /// silently swallows the first.
    var confirmsDeleteAll = false

    /// How many times the block tree has been edited — undo and redo
    /// included, since both are edits (#70).
    ///
    /// The workspace animates on this rather than on the tree itself. The
    /// block list re-renders on every committed command during playback, so
    /// `.animation(_:value:)` keyed on `[Block]` would compare two whole trees
    /// ten times a second to answer a question — "did an edit happen?" — that
    /// a counter answers in one comparison. It is bumped in the same write as
    /// the tree, so SwiftUI sees both in one update and the changes animate
    /// together.
    private(set) var editGeneration = 0

    /// Called from `WorkspaceEditor.apply`, which is the only place the tree
    /// is written.
    func recordEdit() {
        editGeneration += 1
    }

    /// The block the palette just stamped out, so the workspace can bring it
    /// into view (#71).
    ///
    /// Only the *tap* path sets this. A block that was dragged into place was
    /// put where the child was already looking, and scrolling after a drop
    /// would move the program out from under them.
    private(set) var lastAddedBlockID: UUID?

    func recordAdd(_ id: UUID) {
        lastAddedBlockID = id
    }

    /// The block a drag is carrying right now (#98).
    ///
    /// There is no "a drag started" signal on iOS — `onDragSessionUpdated` is
    /// macOS-only, the same hole that made the trash can permanent (#30) — so
    /// this is written from `draggable`'s payload, which is an `@autoclosure`
    /// evaluated once per drag. The palette already leans on that: it is what
    /// stamps a fresh `Block` for every drag.
    ///
    /// There is no "a drag ended" signal either, and here that costs nothing.
    /// The value means something only while a drag is in flight, and a gap
    /// only asks about it when something is hovering over it. A cancelled drag
    /// leaves the last id behind, and the next drag overwrites it before any
    /// gap can read it.
    private(set) var draggedBlockID: UUID?

    func beginDrag(_ id: UUID) {
        draggedBlockID = id
    }
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

    var insertionTarget: BodyAddress? {
        get { uiState.insertionTarget }
        nonmutating set { uiState.insertionTarget = newValue }
    }

    /// What the workspace animates on (#70) — see `WorkspaceUIState`.
    var editGeneration: Int { uiState.editGeneration }

    /// What the workspace scrolls to (#71) — likewise.
    var lastAddedBlockID: UUID? { uiState.lastAddedBlockID }

    /// Records what a drag is carrying and hands the payload straight back, so
    /// a call site reads `draggable(workspace.dragging(block))` and the
    /// recording happens exactly when the drag does (#98).
    func dragging(_ block: Block) -> Block {
        uiState.beginDrag(block.id)
        return block
    }

    /// Whether a drop there would change anything at all — false in the two
    /// places a parted gap would be lying (#98): either side of the block
    /// being dragged, and anywhere inside its own subtree.
    func dropChangesTree(at index: Int, inBodyAt address: BodyAddress) -> Bool {
        guard let dragged = uiState.draggedBlockID else { return true }
        return BlockTree.dropChangesTree(
            blockWithID: dragged, toIndex: index, inBodyAt: address, in: blocks)
    }

    // Reading these in body stays fresh without observation: every edit,
    // undo, and redo mutates the document, which re-renders the view tree.
    var canUndo: Bool { undoManager?.canUndo ?? false }
    var canRedo: Bool { undoManager?.canRedo ?? false }

    // MARK: - Editing

    func add(_ kind: BlockKind) {
        let block = Block(kind: kind)
        // Fall back to top level if the target has been deleted meanwhile.
        let target = validatedInsertionTarget() ?? .topLevel
        guard let new = BlockTree.appending(block, toBodyAt: target, in: blocks) else { return }
        setBlocks(new)
        // Where it went, so the workspace can show it (#71). After the write,
        // and only when the write happened: pointing at a block that was never
        // added would scroll to nothing.
        uiState.recordAdd(block.id)
        // Adding a container makes it the natural next target.
        if kind.containerBody != nil {
            insertionTarget = BodyAddress(containerID: block.id)
        }
    }

    /// Replaces the (empty) tree with a sample program — goes through
    /// `setBlocks`, so it's undoable and dirties the document like any edit.
    func insertSample(_ blocks: [Block]) {
        setBlocks(blocks)
    }

    var confirmsDeleteAll: Bool {
        get { uiState.confirmsDeleteAll }
        nonmutating set { uiState.confirmsDeleteAll = newValue }
    }

    /// Empties the workspace (#48) — one edit, so one ⌘Z brings the whole
    /// program back. Nothing to delete is a no-op, and `setBlocks` refuses an
    /// unchanged tree anyway, so it never registers an empty undo step.
    ///
    /// The insertion target goes with it: the container it pointed into no
    /// longer exists.
    func deleteAll() {
        guard setBlocks([]) else { return }
        insertionTarget = nil
    }

    func delete(_ id: UUID) {
        guard let new = BlockTree.removing(blockWithID: id, from: blocks) else { return }
        setBlocks(new)
        if validatedInsertionTarget() == nil {
            insertionTarget = nil
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

    /// Renames a defined block, and with it every call to that name (#14) —
    /// one undoable edit, because leaving the calls behind would silently turn
    /// each of them into the no-op an undefined call is.
    ///
    /// Retargeting a *single* call is the other operation, and it belongs to
    /// that call's own name chip: `updateKind(of:to:)`.
    func renameFunction(_ oldName: String, to newName: String) {
        guard let new = BlockTree.renamingFunction(oldName, to: newName, in: blocks) else { return }
        setBlocks(new)
    }

    /// Handles a block drop at (address, index). A payload whose ID
    /// already exists in the tree is *moved* (workspace drag); an unknown ID
    /// is *inserted* (palette drag). Identity moves and invalid targets are
    /// rejected without touching the undo stack.
    @discardableResult
    func handleDrop(_ dropped: Block, at index: Int, inBodyAt address: BodyAddress) -> Bool {
        let new: [Block]?
        if BlockTree.block(withID: dropped.id, in: blocks) != nil {
            new = BlockTree.moving(
                blockWithID: dropped.id, toIndex: index, inBodyAt: address, in: blocks)
        }
        else {
            new = BlockTree.inserting(dropped, at: index, inBodyAt: address, in: blocks)
        }
        guard let new else { return false }
        return setBlocks(new)
    }

    /// Stores the picture the file browser shows for this document (#15).
    ///
    /// The one mutation here that does *not* register an undo, on purpose:
    /// running is not an edit, and ⌘Z has to keep stepping back through block
    /// changes rather than through a program's runs. It still writes through
    /// the binding, so the document goes dirty and autosave picks it up.
    ///
    /// A failed render (nil) leaves the previous thumbnail alone rather than
    /// clearing it — a stale picture beats no picture in a folder.
    func recordThumbnail(_ png: Data?) {
        guard let png else { return }
        document.wrappedValue.project.thumbnail = png
    }

    // MARK: - Undo / Redo

    func undo() {
        undoManager?.undo()
    }

    func redo() {
        undoManager?.redo()
    }

    // MARK: - Private

    private func validatedInsertionTarget() -> BodyAddress? {
        guard let target = uiState.insertionTarget,
            let id = target.containerID,
            let block = BlockTree.block(withID: id, in: blocks),
            block.kind.body(for: target.slot) != nil
        else { return nil }
        return target
    }

    @discardableResult
    private func setBlocks(_ new: [Block]) -> Bool {
        guard new != blocks else { return false }
        Self.apply(new, to: document, undoManager: undoManager, uiState: uiState)
        return true
    }

    /// Writes the tree through the binding and registers the inverse;
    /// undoing re-enters here, which registers the redo automatically.
    ///
    /// Every edit in the app comes through this one function, which is what
    /// makes the workspace's animation (#70) a single change rather than one
    /// per call site — and why undo and redo animate for free: they re-enter
    /// here, so a block that slid in when it was added slides back in when it
    /// is brought back.
    private static func apply(
        _ value: [Block], to document: Binding<BlocksDocument>, undoManager: UndoManager?,
        uiState: WorkspaceUIState
    ) {
        let old = document.wrappedValue.project.blocks
        document.wrappedValue.project.blocks = value
        uiState.recordEdit()
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoManager) { manager in
            MainActor.assumeIsolated {
                apply(old, to: document, undoManager: manager, uiState: uiState)
            }
        }
    }
}
