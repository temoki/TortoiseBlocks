import SwiftUI
import TortoiseBlocksKit
import TortoiseUI
import UniformTypeIdentifiers

/// Root: palette | workspace | canvas (regular width),
/// or a Build / Run tab pair (compact width).
struct ContentView: View {
    @Binding var document: BlocksDocument
    @State private var uiState = WorkspaceUIState()
    @State private var runner = RunnerModel()
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let workspace = WorkspaceEditor(
            document: $document, undoManager: undoManager, uiState: uiState)
        Group {
            #if os(iOS)
                AdaptiveRootView(workspace: workspace, runner: runner)
            #else
                RegularRootView(workspace: workspace, runner: runner)
            #endif
        }
        .focusedSceneValue(\.runner, runner)
        .focusedSceneValue(\.workspaceBlocks, workspace.blocks)
    }
}

#if os(iOS)
    struct AdaptiveRootView: View {
        let workspace: WorkspaceEditor
        let runner: RunnerModel
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            if horizontalSizeClass == .compact {
                CompactRootView(workspace: workspace, runner: runner)
            }
            else {
                RegularRootView(workspace: workspace, runner: runner)
            }
        }
    }

    struct CompactRootView: View {
        let workspace: WorkspaceEditor
        let runner: RunnerModel

        var body: some View {
            TabView {
                Tab("Build", systemImage: "square.stack.3d.up") {
                    VStack(spacing: 0) {
                        WorkspaceView(workspace: workspace, runner: runner)
                        Divider()
                        PaletteStrip(workspace: workspace)
                            .padding(.vertical, 8)
                    }
                }
                Tab("Run", systemImage: "tortoise") {
                    CanvasPane(workspace: workspace, runner: runner)
                }
            }
        }
    }
#endif

struct RegularRootView: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    // Grows the palette column with Dynamic Type so larger block labels
    // don't truncate (#24).
    @ScaledMetric private var paletteWidth: CGFloat = 220

    var body: some View {
        // Each column titles itself with a plain inline Text (§23) —
        // PaletteView, WorkspaceView, and CanvasPane — rather than a
        // `NavigationSplitView`/toolbar-level title. `.navigationTitle`,
        // `.principal`, and `.status` toolbar placements all turned out to
        // collide with this DocumentGroup scene's own document-title
        // chrome in one way or another (rename-on-tap, "Liquid Glass"
        // material, layout landing at the wrong edge) when three columns
        // each tried to claim one.
        NavigationSplitView {
            PaletteView(workspace: workspace)
                .navigationSplitViewColumnWidth(paletteWidth)
        } content: {
            WorkspaceView(workspace: workspace, runner: runner)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            // 280pt keeps the canvas usable (§23) — narrower and its own
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

    var body: some View {
        VStack(spacing: 0) {
            // The canvas stays in the hierarchy while the code pane covers
            // it (opacity, not if/else) so playback identity is preserved.
            ZStack {
                TortoiseCanvas(runner.tortoise, player: runner.player)
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
        .alert("Too Many Blocks!", isPresented: $runner.showsExpansionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a smaller repeat count.")
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

/// The canvas/code segmented toggle — shared between `CanvasPane`'s inline
/// header (compact) and its toolbar (regular, §23).
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

/// The export menu (SVG / PNG at three scales / ShareLink) — shared between
/// `CanvasPane`'s inline header (compact) and its toolbar (regular, §23).
/// `onExport` keeps this view free of `CanvasPane`'s own file-exporter state.
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
