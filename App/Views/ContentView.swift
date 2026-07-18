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
        #if os(iOS)
            AdaptiveRootView(workspace: workspace, runner: runner)
        #else
            RegularRootView(workspace: workspace, runner: runner)
        #endif
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
        HStack(spacing: 0) {
            PaletteView(workspace: workspace)
                .frame(width: 220)
            Divider()
            WorkspaceView(workspace: workspace, runner: runner)
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 440)
            Divider()
            CanvasPane(workspace: workspace, runner: runner)
                .frame(maxWidth: .infinity)
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
            HStack {
                Picker("View", selection: $showsCode) {
                    Text("Canvas").tag(false)
                    Text("Code").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("SVG") {
                        export(runner.svgData(), as: .svg)
                    }
                    Menu("PNG") {
                        Button("1x (512px)") {
                            export(runner.pngData(scale: 1), as: .png)
                        }
                        Button("2x (1024px)") {
                            export(runner.pngData(scale: 2), as: .png)
                        }
                        Button("3x (1536px)") {
                            export(runner.pngData(scale: 3), as: .png)
                        }
                    }
                    Divider()
                    // svgData()/pngData() are cached per run, so evaluating
                    // them here (ShareLink's items are eager) doesn't
                    // re-render on every menu open.
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
            .padding([.horizontal, .top])
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
        .alert("Too Many Blocks!", isPresented: $runner.showsExpansionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a smaller repeat count.")
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

/// Run / clear / pause / step / speed, driving the runner and player.
struct PlaybackControls: View {
    let workspace: WorkspaceEditor
    @Bindable var runner: RunnerModel

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
                Spacer()
                Text("Command: \(runner.player.currentCommandIndex + 1)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Toggle("Pause", systemImage: "pause.fill", isOn: $player.isPaused)
                    .toggleStyle(.button)
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

/// Timeline scrubber: shows the playback position and seeks on drag —
/// forward and backward, even mid-run.
struct PlaybackScrubber: View {
    let runner: RunnerModel

    var body: some View {
        HStack {
            Slider(value: position, in: -1...Double(max(runner.commandCount - 1, 0)), step: 1) {
                Text("Position")
            }
            .labelsHidden()
            .disabled(runner.commandCount == 0)
            Text(verbatim: "\(runner.player.currentCommandIndex + 1) / \(runner.commandCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
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
