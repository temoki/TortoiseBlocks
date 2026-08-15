#if os(visionOS)

    import SwiftUI
    import TortoiseBlocksKit

    /// The program, read-only, following the playback on the table (#53).
    ///
    /// This is the window that makes the visionOS build *this app* rather than
    /// a way to watch a drawing appear. Seeing which block is running while the
    /// tortoise moves is the whole pedagogy, and on a headset it gets the
    /// version the iPad cannot give it: the program on one surface and the
    /// drawing on your actual table, both full size, with nothing to switch
    /// between.
    ///
    /// **The rows are the editor's own rows.** Not a read-only lookalike — the
    /// same `BlockListView`, and so the same category colours, the same C-shaped
    /// containers, the same row heights and label alignment. A second renderer
    /// would have to be kept in step by hand, and the failure mode is silent:
    /// `SimpleBlockLabel` is on the "when adding a block kind" checklist
    /// precisely because a kind that is missed there renders as nothing.
    struct ProgramWindow: View {
        let model: ViewerModel

        var body: some View {
            ScrollView {
                // The list has to follow the playhead, or the feature only
                // works for programs short enough to fit: on device the
                // highlight was correct and *off screen* for everything past
                // the first few rows.
                //
                // `scrollTo` with **no anchor** is the whole trick. Centring
                // the running block would drag the list on nearly every
                // command — a loop body cycling three rows would never sit
                // still — while the default anchor scrolls the least amount
                // that brings the row into view, and does nothing at all while
                // it is already there. Unanimated for the same reason: at ten
                // commands a second an animation only ever restarts itself.
                ScrollViewReader { proxy in
                    programList
                        .onChange(of: model.runner.currentBlockID) { _, id in
                            guard let id else { return }
                            proxy.scrollTo(id)
                        }
                }
            }
            // The editing controls are not drawn at all. Inert-but-visible was
            // tried first and reads worse than either alternative: the ⋯ menu
            // and the mouths' "add here" toggle look pressable, do nothing, and
            // are the two things #53 says a read-only program must not offer.
            .environment(\.showsBlockEditing, false)
            .overlay {
                if !model.hasProgram {
                    ContentUnavailableView(
                        "No Drawing", systemImage: "square.stack.3d.up",
                        description: Text("Open a drawing, or start from a sample."))
                }
            }
        }

        private var programList: some View {
            BlockListView(
                blocks: model.blocks,
                address: .topLevel,
                workspace: Self.readOnly(model.blocks),
                // The highlight this window exists for. It costs nothing
                // extra: `RunnerModel.currentBlockID` is
                // `expandedBlockIDs[player.currentCommandIndex]`, and the
                // table draws through the very same `CommandPlayer`, so the
                // index alignment the whole app rests on is untouched by
                // the drawing having moved into an immersive space.
                highlightedID: model.runner.currentBlockID,
                usedVariableNames: BlockTree.usedVariableNames(in: model.blocks),
                usedFunctionNames: BlockTree.usedFunctionNames(in: model.blocks)
            )
            .padding()
            // Read-only twice over, and the belt matters more than the braces.
            //
            // The *binding* is what enforces it: `WorkspaceEditor` writes
            // through `document`, and a constant binding throws those writes
            // away — so even a path that tried to edit could not, and no list
            // of hidden affordances has to stay complete for that to hold.
            // Hit-testing off then removes the drag sources, the drop gaps and
            // the value chips from a window where none of them mean anything.
            //
            // On the **content**, not on the `ScrollView`. Around the scroll
            // view it takes the scrolling with it, and the window becomes one
            // that can only ever show the rows it happens to open on — which is
            // most of the program for anything but a short one.
            .allowsHitTesting(false)
        }

        /// An editor that cannot edit: no undo manager to register with, fresh
        /// UI state nothing reads, and a constant document binding that
        /// discards every write.
        private static func readOnly(_ blocks: [Block]) -> WorkspaceEditor {
            WorkspaceEditor(
                document: .constant(
                    BlocksDocument(project: BlocksProject(title: "", blocks: blocks))),
                undoManager: nil,
                uiState: WorkspaceUIState())
        }
    }

#endif
