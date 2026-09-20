import SwiftUI
import TortoiseBlocksKit
import TortoiseUI
import UniformTypeIdentifiers

/// Root: palette | workspace | canvas.
struct ContentView: View {
    @Binding var document: BlocksDocument
    @State private var uiState = WorkspaceUIState()
    @State private var runner = RunnerModel()
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let workspace = WorkspaceEditor(
            document: $document, undoManager: undoManager, uiState: uiState)
        RootView(workspace: workspace, runner: runner)
            .focusedSceneValue(\.runner, runner)
            .focusedSceneValue(\.workspaceBlocks, workspace.blocks)
            .focusedSceneValue(\.workspaceUIState, uiState)
            // Every run path bumps the generation, so this is the single place
            // the document's QuickLook thumbnail is refreshed (#15). It is
            // stored, never read back onto the canvas — reopening a document
            // starts empty and one press of the run button fills it.
            .onChange(of: runner.runGeneration) {
                workspace.recordThumbnail(runner.thumbnailData())
            }
    }
}

/// Picks the layout by width (#113). Regular — iPad, Mac, and the visionOS
/// window, which is a regular-width scene and needs nothing of its own (#11) —
/// keeps the three-column split view. Compact — an iPhone, or an iPad window
/// squeezed into Slide Over — gets `CompactRootView`.
///
/// This branch is exactly what #29 deleted, and it is back because the fallback
/// #29 trusted does not exist. `NavigationSplitView` collapses to its
/// *sidebar* and pushes nothing, because these three columns are not a
/// selection-driven master-detail: measured on an iPhone 17, the entire
/// accessibility tree of an open document was the palette, a back button to the
/// document browser, and a scroll bar — no workspace, no canvas, and nothing to
/// press that reached either. The standard collapse is not a narrow version of
/// this app; it is a dead end, so compact needs a layout of its own.
struct RootView: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Two layouts rather than one that adapts: the panes are the same
        // three views, but what holds them (columns against a stack plus
        // sheets) has no middle ground worth expressing as modifiers.
        if horizontalSizeClass == .compact {
            CompactRootView(workspace: workspace, runner: runner)
        }
        else {
            RegularRootView(workspace: workspace, runner: runner)
        }
    }
}

/// The three-pane layout: palette | workspace | canvas.
struct RegularRootView: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    // Grows the palette column with Dynamic Type so larger block labels
    // don't truncate (#24).
    @ScaledMetric private var paletteWidth: CGFloat = 220

    var body: some View {
        // No column carries a title of its own (#23). Columns used to name
        // themselves with a plain inline Text; 0de22dd moved their controls
        // into native toolbars and dropped the headers, and nothing replaced
        // them, because a title per column is exactly what doesn't work here:
        // `.navigationTitle` and the `.principal` / `.status` toolbar
        // placements each collided with this DocumentGroup scene's own
        // document-title chrome (rename-on-tap, "Liquid Glass" material,
        // layout landing at the wrong edge). The one title on screen is the
        // document's, in the sidebar's bar — see `CanvasPane` for the copy
        // iPadOS puts in the detail column (#31).
        NavigationSplitView {
            PaletteView(workspace: workspace)
                .navigationSplitViewColumnWidth(paletteWidth)
        } content: {
            // 440pt is measured, not chosen, and `ideal` carries more weight
            // than it looks. macOS and iPadOS both let the divider be dragged,
            // so there the ideal is only where the column *opens*; on visionOS
            // it can't be, so the ideal is the width, permanently, while the
            // detail column absorbs every extra point — a 1280pt visionOS
            // window put 360 here and ~690 on the canvas (#11).
            // At 360 a three-deep program broke its labels onto two lines, and
            // not only at depth: 「くりかえす 10 かい」 wrapped か/い at the top
            // level, and 「はこにかける」 split in the middle. 440 fits every one
            // of them on one line at three levels of nesting (each level costs
            // 18pt), and still leaves the canvas ~600pt — well over its own 420
            // ideal. `max` has to stay above `ideal`, or the two platforms that
            // can drag could only ever drag narrower.
            WorkspaceView(workspace: workspace, runner: runner)
                .navigationSplitViewColumnWidth(min: 300, ideal: 440, max: 560)
                .toolbar { WorkspaceToolbar(workspace: workspace) }
        } detail: {
            // 280pt keeps the canvas usable (#23) — narrower and its own
            // playback row starts contesting space with the drawing.
            CanvasPane(workspace: workspace, runner: runner)
                .navigationSplitViewColumnWidth(min: 280, ideal: 420)
        }
    }
}

/// The iPhone layout (#113): the workspace *is* the screen, and the two panes
/// that cannot sit beside it are sheets raised from its toolbar.
///
/// The program is the root rather than the palette or the canvas because it is
/// the one pane a child returns to between every other action — the palette is
/// visited to fetch a block, the canvas to watch what the blocks did.
struct CompactRootView: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    /// **One piece of state for both sheets, deliberately.** Two `sheet`
    /// modifiers on the same view silently drop all but the last — the same
    /// trap the two `fileExporter`s in `CanvasPane` are written around.
    @State private var sheet: CompactSheet?
    /// Kept here rather than in the sheet so the size survives closing it: a
    /// child who shrank the palette to drag from it wants it that size next
    /// time too.
    @State private var paletteSize: PaletteSheetSize = .half

    var body: some View {
        // **A `NavigationStack` of our own, and its bar stays.** The stack is
        // forced: `.bottomBar` items placed into the `DocumentGroup`'s own
        // navigation controller do not appear, so ⊞ and ▶ vanish with it.
        //
        // Its bar is what carries the document's name here, which is why
        // hiding it — tried, in the first pass at #116 — is wrong. Measured on
        // an iPhone 17 Pro Max, the two ways a document opens do not present
        // the same way:
        //
        // *From the app's own browser*, a tap pushes onto that browser's
        // navigation controller and this stack's bar is the **only** one. Hide
        // it and the screen has no back button and no name at all — the child
        // is in a document with no way out.
        //
        // *From a URL* (Files, `simctl openurl`), the document is presented
        // with a bar of its own **as well**, and the scene hands its title
        // chrome to both: `< star ⌄` over `< star ⌄`. That duplication is
        // cosmetic, it is the rarer path, and no setting separates the two
        // cases — so it is the one that is lived with. The trade was the other
        // way round for one commit, and the wrong way round.
        NavigationStack {
            WorkspaceView(workspace: workspace, runner: runner)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            workspace.undo()
                        }
                        .disabled(!workspace.canUndo)
                        Button("Redo", systemImage: "arrow.uturn.forward") {
                            workspace.redo()
                        }
                        .disabled(!workspace.canRedo)
                    }
                    // The two ways off this screen, at the bottom, where a
                    // thumb is — and either side of the trash can, which keeps
                    // its own inset: ⊞, 🗑, ▶ in one row.
                    ToolbarItemGroup(placement: .compactActions) {
                        Button("Blocks", systemImage: "square.grid.2x2") {
                            sheet = .palette
                        }
                        // **Said outright, because a toolbar swallows it.**
                        // SwiftUI hands an `Image(systemName:)` through as the
                        // accessibility identifier — which is how the
                        // transport's `play.fill` and the trash can's `trash`
                        // are addressed without naming a localized label — but
                        // a button placed in a `ToolbarItem` arrives with an
                        // empty one. These two are the whole of what a phone's
                        // screenshots have to press, so they say their own
                        // names.
                        .accessibilityIdentifier("square.grid.2x2")
                        Spacer()
                        // Running and showing the drawing are one action here:
                        // there is nowhere for a drawing to already be, so a
                        // button that only opened the canvas would open an
                        // empty one. `play.fill` is the transport's own glyph,
                        // so ▶ means the same thing in both places a child
                        // meets it. (Not `tortoise`: paired with `hare` that is
                        // the *speed* symbol, and this app has a speed menu.)
                        Button("Run", systemImage: "play.fill") {
                            runner.run(workspace.blocks)
                            sheet = .canvas
                        }
                        .disabled(workspace.blocks.isEmpty)
                        // The transport's centre button carries this name too,
                        // and deliberately: pressed, both run the program. The
                        // two are never on screen at once — this one raises
                        // the sheet the other lives in.
                        .accessibilityIdentifier("play.fill")
                    }
                }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .palette: CompactPaletteSheet(workspace: workspace, size: $paletteSize)
            case .canvas: CompactCanvasSheet(workspace: workspace, runner: runner)
            }
        }
    }
}

/// Which pane `CompactRootView` is showing over the workspace.
enum CompactSheet: String, Identifiable {
    case palette
    case canvas

    var id: String { rawValue }
}

/// The palette, over the workspace (#113).
///
/// **Both ways in work, and they mean different things.** A tap places a block
/// and closes the sheet — one block, then look at it. A drag carries one out
/// onto the program showing behind, which *is* possible from a sheet (measured,
/// against the expectation that it would not be) as long as the sheet is short
/// enough to be dropping onto something and the background is left interactive
/// — see `paletteSheetSize(_:peek:)`, which owns both halves of that.
struct CompactPaletteSheet: View {
    let workspace: WorkspaceEditor
    @Binding var size: PaletteSheetSize

    /// The bar, the grab handle, and two blocks under them. Scaled, because
    /// what has to fit is rows of text.
    @ScaledMetric private var peekHeight: CGFloat = 180

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // **Closing on the tap is the point, not a convenience.** A
            // tapped block goes in at the insertion target, which on a program
            // of any length is below the fold — and #71 is the whole argument
            // that a block added where it cannot be seen reads as nothing
            // having happened. Shrinking the sheet does not fix *that* case
            // (measured: with the spiral sample loaded, the tapped block still
            // landed off-screen), so the sheet gets out of the way and lets
            // the workspace's own scroll-to-the-new-block do its job. A drag
            // needs none of this, because you are looking at where it lands.
            PaletteView(workspace: workspace) { dismiss() }
                .navigationTitle("Blocks")
                .sheetNavigationBar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .paletteSheetSize($size, peek: peekHeight)
    }
}

/// The canvas, over the workspace (#113) — the same `CanvasPane` the iPad shows
/// in its detail column, including the transport and the export menu.
///
/// The close button is ours. On iPad the pane's leading chevron belongs to the
/// split view; a sheet has no such thing, and dragging it down is the only way
/// out a child would otherwise have.
struct CompactCanvasSheet: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CanvasPane(workspace: workspace, runner: runner)
                .sheetNavigationBar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        }
    }
}

/// The drawing side: canvas (or the generated-code pane) + playback
/// controls, wired to the workspace.
struct CanvasPane: View {
    let workspace: WorkspaceEditor
    @Bindable var runner: RunnerModel

    @State private var showsCode = false
    // One presentation state for both formats: attaching two fileExporter
    // modifiers to the same view lets the later one swallow the earlier.
    @State private var exportFile: ExportFile?
    @State private var exportType: UTType = .png

    /// Our own tortoise instead of the library's green triangle. `size` is the
    /// artwork's natural size — the @1x rendition is 23×32px — so at viewport
    /// scale 1 it lands pixel-exact rather than resampled, and the library
    /// scales it with the viewport from there (0.5×–2×), exactly as it scales
    /// the triangle. The asset has to point *up*: `.image` rotates its top edge
    /// toward the heading. Deliberately not applied to the PNG export's canvas
    /// — see `RunnerModel.exportFrameSize`.
    private static let sprite = TortoiseSprite.image(
        Image(.tortoiseSprite), size: CGSize(width: 23, height: 32))

    /// The paper's outline: the same 8 a standalone block row rounds
    /// (`RowCorners`), so the two panes agree rather than each softening by its
    /// own amount. A wider radius was tried on the larger surface and judged
    /// too much in the running app. Not scaled with Dynamic Type — it follows
    /// the pane, not the text.
    private static let sheet = RoundedRectangle(cornerRadius: 8)

    var body: some View {
        VStack(spacing: 0) {
            // The canvas stays in the hierarchy while the code pane covers
            // it (opacity, not if/else) so playback identity is preserved.
            ZStack {
                TortoiseCanvas(runner.tortoise, player: runner.player)
                    .tortoiseSprite(Self.sprite)
                    // The canvas is paper, in both appearances — the default pen
                    // is black, and it has to be on something.
                    //
                    // Since 2.0.0-beta12 the library paints that white itself
                    // (TortoiseGraphics2#44 — before it, a stream that never
                    // named a background rendered as nothing, which light mode
                    // hid behind a nearly white system background and dark mode
                    // did not). This stays anyway: "our canvas is paper" is a
                    // decision about this app, and it should not quietly depend
                    // on a library default that has already changed once.
                    //
                    // Inside the padding, so the sheet is inset and the pane's
                    // own colour frames it. Taking it to the pane's edges was
                    // tried and judged worse in the running app.
                    .background(.white, in: Self.sheet)
                    // Clips the drawing to the same shape rather than only
                    // painting under it, which is now load-bearing: the library
                    // paints its own square white over this one, and without
                    // the clip the rounded corners it was given would be
                    // squared straight back off. (It was added a release early,
                    // against exactly this happening.)
                    .clipShape(Self.sheet)
                    .padding()
                    .opacity(showsCode ? 0 : 1)
                    .accessibilityHidden(showsCode)
                if showsCode {
                    CodePane(code: SwiftCodeGenerator.code(for: workspace.blocks))
                        .padding()
                }
            }
            // Pressing the toggle should change the content and nothing else,
            // which is an argument for a cross-fade as much as for the two
            // panes matching (#11) — a cut makes the pane look like it was
            // replaced rather than turned over (#72).
            //
            // The code pane stays inside an `if` rather than joining the
            // canvas on `opacity`: keeping it alive would re-run
            // `SwiftCodeGenerator` on every edit, for a pane nobody is
            // looking at. The canvas is the one that can't be rebuilt —
            // destroying `TortoiseCanvas` resets playback identity.
            .motion(Motion.paneSwap, value: showsCode)
            Divider()
            PlaybackControls(
                blocks: workspace.blocks, runner: runner,
                isStale: runner.isStale(comparedTo: workspace.blocks)
            )
            .padding()
        }
        // The document title belongs to the sidebar's bar, once (#31). On
        // iPadOS the DocumentGroup hands its title chrome to *both* ends of the
        // split view — sidebar and detail — so the document name and its
        // rename chevron can end up on screen twice; rotating is the reliable
        // way to get there, since the detail keeps the chrome it had before the
        // columns rearranged. This drops the copy here. The back chevron it
        // sits next to is not ours to remove — neither dropping this column's
        // toolbar nor `navigationBarBackButtonHidden` touches it.
        .toolbar(removing: .title)
        .toolbar {
            CanvasToolbar(
                workspace: workspace, runner: runner, showsCode: $showsCode, onExport: export)
        }
        // One alert, switching on why the run failed (`expansionAlert`):
        // attaching a second one for the recursion case would silently drop
        // whichever came first.
        .alert(Text(runner.expansionAlert.title), isPresented: $runner.showsExpansionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(runner.expansionAlert.message)
        }
        .onChange(of: runner.pendingExport) { _, type in
            guard let type else { return }
            switch type {
            case .svg: export(runner.svgData(), as: .svg)
            case .png: export(runner.pngData(), as: .png)
            default: break
            }
            runner.pendingExport = nil
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
            document: exportFile, contentType: exportType,
            defaultFilename: String(localized: "Drawing")
        ) { _ in
            exportFile = nil
        }
    }

    private func export(_ data: Data?, as type: UTType) {
        guard let data else { return }
        exportType = type
        exportFile = ExportFile(data: data)
    }
}

/// `CanvasPane`'s toolbar: the canvas/code toggle, then ⟳ and the export menu.
///
/// It is a `ToolbarContent` type of its own only so the `#if` below has
/// somewhere to live that isn't the call site — `ToolbarSpacer` is the Liquid
/// Glass grouping separator and is unavailable on visionOS, which lays its
/// toolbar out as an ornament and spaces the groups itself. The items and
/// their order are the same everywhere; only the separators come and go.
struct CanvasToolbar: ToolbarContent {
    let workspace: WorkspaceEditor
    let runner: RunnerModel
    @Binding var showsCode: Bool
    let onExport: (Data?, UTType) -> Void

    var body: some ToolbarContent {
        #if !os(visionOS)
            ToolbarSpacer(.flexible, placement: .primaryAction)
        #endif

        // **The group's own glass, turned off for this one control.** In 26 a
        // `ToolbarItemGroup` draws a capsule behind whatever it holds, and a
        // `Picker(.segmented)` draws a capsule of its own — so this item came
        // out as a capsule inside a capsule, the outer one a size larger and
        // slightly off (#119). The group below keeps its background because
        // ⟳ and the export menu are plain buttons with no shape of their own.
        //
        // Not only cosmetic: the outer capsule's padding was taking width the
        // segments needed, and in portrait the labels were being truncated to
        // 「キ… コ…」. They fit once it is gone.
        ToolbarItemGroup(placement: .primaryAction) {
            CanvasViewToggle(showsCode: $showsCode)
        }
        .withoutSharedBackground()

        #if !os(visionOS)
            ToolbarSpacer(.fixed, placement: .primaryAction)
        #endif

        ToolbarItemGroup(placement: .primaryAction) {
            CanvasRollAgainButton(workspace: workspace, runner: runner)
            CanvasExportMenu(runner: runner, onExport: onExport)
        }
    }
}

/// The canvas/code segmented toggle, in `CanvasPane`'s toolbar (#23).
struct CanvasViewToggle: View {
    @Binding var showsCode: Bool

    var body: some View {
        Picker("View", selection: $showsCode) {
            Text("Canvas").tag(false)
            Text("Code").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 220)
    }
}

/// The export menu (SVG / PNG at three scales / ShareLink), in `CanvasPane`'s
/// toolbar (#23). `onExport` keeps this view free of `CanvasPane`'s own
/// file-exporter state.
struct CanvasExportMenu: View {
    @Bindable var runner: RunnerModel
    let onExport: (Data?, UTType) -> Void

    var body: some View {
        Menu("Export", systemImage: "square.and.arrow.up") {
            Button("SVG") {
                onExport(runner.svgData(), .svg)
            }
            Menu("PNG") {
                Button("1x (512px)") {
                    onExport(runner.pngData(scale: 1), .png)
                }
                Button("2x (1024px)") {
                    onExport(runner.pngData(scale: 2), .png)
                }
                Button("3x (1536px)") {
                    onExport(runner.pngData(scale: 3), .png)
                }
            }
            Divider()
            // svgData()/pngData() are cached per run, so evaluating them
            // here (ShareLink's items are eager) doesn't re-render on every
            // menu open.
            if let svgData = runner.svgData() {
                ShareLink(items: [SVGDrawing(data: svgData)]) { _ in
                    SharePreview("Drawing")
                } label: {
                    Label("Share SVG", systemImage: "square.and.arrow.up")
                }
            }
            if let pngData = runner.pngData() {
                ShareLink(items: [PNGDrawing(data: pngData)]) { _ in
                    SharePreview("Drawing")
                } label: {
                    Label("Share PNG", systemImage: "square.and.arrow.up")
                }
            }
        }
        .disabled(!runner.canExport)
        .fixedSize()
    }
}

#Preview {
    ContentView(document: .constant(BlocksDocument()))
}
