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
            // Every run path bumps the generation, so this is the single place
            // the document's QuickLook thumbnail is refreshed (#15). It is
            // stored, never read back onto the canvas — reopening a document
            // starts empty and one press of the run button fills it.
            .onChange(of: runner.runGeneration) {
                workspace.recordThumbnail(runner.thumbnailData())
            }
    }
}

/// The one layout, on both platforms (#29). The app is iPad and Mac only, and
/// compact width — an iPhone, or an iPad window squeezed into Slide Over — is
/// no longer a design target: three panes' worth of information (palette,
/// program, canvas) folded into one 390pt column never came out usable. A
/// window narrow enough to go compact gets `NavigationSplitView`'s own
/// collapse, not a layout of ours.
struct RootView: View {
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
            WorkspaceView(workspace: workspace, runner: runner)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            // 280pt keeps the canvas usable (#23) — narrower and its own
            // playback row starts contesting space with the drawing.
            CanvasPane(workspace: workspace, runner: runner)
                .navigationSplitViewColumnWidth(min: 280, ideal: 420)
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
            Divider()
            PlaybackControls(
                workspace: workspace, runner: runner,
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
            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                CanvasViewToggle(showsCode: $showsCode)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                CanvasRollAgainButton(workspace: workspace, runner: runner)
                CanvasExportMenu(runner: runner, onExport: export)
            }
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
