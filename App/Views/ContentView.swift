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
            } else {
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

    var body: some View {
        NavigationSplitView {
            PaletteView(workspace: workspace)
                .columnLabel("Blocks")
                .navigationSplitViewColumnWidth(220)
        } content: {
            WorkspaceView(workspace: workspace, runner: runner, showsTitle: false)
                .columnLabel("Program")
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            // 280pt keeps the canvas usable (§23) — narrower and its own
            // playback row starts contesting space with the drawing.
            CanvasPane(workspace: workspace, runner: runner, usesToolbar: true)
                .columnLabel("Run")
                .navigationSplitViewColumnWidth(min: 280, ideal: 420)
        }
    }
}

extension View {
    /// A plain, non-editable label for a `NavigationSplitView` column
    /// (§23) — deliberately *not* `.navigationTitle`, which inside this
    /// app's `DocumentGroup` scene doubles as the document's own rename
    /// control. Setting it per column meant the document-rename popover
    /// (with the column's label swapped in for its title text) opened from
    /// every column, not just the one place a kid should be renaming the
    /// saved file from.
    func columnLabel(_ text: LocalizedStringKey) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Text(text)
                    .font(.headline)
            }
        }
    }
}

/// The drawing side: canvas (or the generated-code pane) + playback
/// controls, wired to the workspace.
struct CanvasPane: View {
    let workspace: WorkspaceEditor
    @Bindable var runner: RunnerModel
    /// Regular width hosts this pane inside `RegularRootView`'s
    /// `NavigationSplitView`, which gives the view toggle and export menu a
    /// toolbar to live in; compact width's plain `TabView` has no
    /// navigation bar, so it keeps the inline header instead (§23).
    var usesToolbar = false

    @State private var showsCode = false
    // One presentation state for both formats: attaching two fileExporter
    // modifiers to the same view lets the later one swallow the earlier.
    @State private var exportFile: ExportFile?
    @State private var exportType: UTType = .png

    var body: some View {
        VStack(spacing: 0) {
            if !usesToolbar {
                HStack {
                    CanvasViewToggle(showsCode: $showsCode)
                    Spacer()
                    CanvasExportMenu(runner: runner, onExport: export)
                }
                .padding([.horizontal, .top])
            }
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
            PlaybackControls(workspace: workspace, runner: runner)
                .padding()
        }
        .toolbar {
            if usesToolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    CanvasViewToggle(showsCode: $showsCode)
                    CanvasExportMenu(runner: runner, onExport: export)
                }
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

/// Run / clear / pause / position, always visible in one row (§23); step,
/// the scrubber, and speed reveal below on demand — `isExpanded` is UI-only
/// state, deliberately not persisted across launches.
struct PlaybackControls: View {
    let workspace: WorkspaceEditor
    @Bindable var runner: RunnerModel

    @State private var isExpanded = false

    var body: some View {
        @Bindable var player = runner.player
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button("Run", systemImage: "play.fill") {
                    runner.run(workspace.blocks)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspace.blocks.isEmpty)
                Button("Clear", systemImage: "trash") {
                    runner.clear()
                }
                .disabled(runner.commandCount == 0)
                Toggle("Pause", systemImage: "pause.fill", isOn: $player.isPaused)
                    .toggleStyle(.button)
                    // Icon-only: "Pause"/いちじていし was the one label in
                    // this row long enough to wrap to two lines once
                    // everything shared a single row (§23).
                    .labelStyle(.iconOnly)
                    .disabled(runner.commandCount == 0)
                Spacer()
                // The one place the run position shows — this used to be
                // duplicated between "Command: N" here and "N / M" on the
                // scrubber below.
                Text(verbatim: positionText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .trailing)
                Button("Playback Details", systemImage: "chevron.down") {
                    isExpanded.toggle()
                }
                .labelStyle(.iconOnly)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            }
            if isExpanded {
                HStack(spacing: 16) {
                    Button("Step", systemImage: "forward.frame.fill") {
                        runner.player.step()
                    }
                    .disabled(!runner.player.isPaused)
                    SpeedSlider(player: runner.player)
                }
                PlaybackScrubber(runner: runner)
            }
        }
    }

    /// "N / M" once there's a run to show a position in; an idling scrubber
    /// (nothing run yet, or cleared) reads as a plain dash rather than the
    /// otherwise-confusing "0 / 0" (currentCommandIndex starts at -1).
    private var positionText: String {
        guard runner.commandCount > 0 else { return "–" }
        return "\(runner.player.currentCommandIndex + 1) / \(runner.commandCount)"
    }
}

/// Timeline scrubber: shows the playback position and seeks on drag —
/// forward and backward, even mid-run.
struct PlaybackScrubber: View {
    let runner: RunnerModel

    var body: some View {
        Slider(value: position, in: -1...Double(max(runner.commandCount - 1, 0)), step: 1) {
            Text("Position")
        }
        .labelsHidden()
        .disabled(runner.commandCount == 0)
    }

    private var position: Binding<Double> {
        Binding(
            get: { Double(runner.player.currentCommandIndex) },
            set: { runner.player.seek(to: Int($0.rounded())) }
        )
    }
}

/// Viewer-side speed control bound to `TortoisePlayer.speedOverride`.
struct SpeedSlider: View {
    @Bindable var player: TortoisePlayer

    var body: some View {
        HStack {
            Label("Speed", systemImage: "tortoise")
                .labelStyle(.iconOnly)
            Slider(value: speed, in: 1...10, step: 1) {
                Text("Speed")
            }
            .frame(maxWidth: 240)
            Label("Speed", systemImage: "hare")
                .labelStyle(.iconOnly)
        }
        .foregroundStyle(.secondary)
    }

    /// `speedOverride` is optional (nil = follow the stream); the slider
    /// always overrides, defaulting to the library's default speed.
    private var speed: Binding<Double> {
        Binding(
            get: { player.speedOverride ?? 5 },
            set: { player.speedOverride = $0 }
        )
    }
}

#Preview {
    ContentView(document: .constant(BlocksDocument()))
}
