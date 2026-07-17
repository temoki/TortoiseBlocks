import SwiftUI
import TortoiseBlocksKit
import TortoiseUI

/// Root: palette | workspace | canvas (regular width),
/// or a つくる / うごかす tab pair (compact width).
struct ContentView: View {
    @State private var workspace = WorkspaceModel()
    @State private var runner = RunnerModel()

    var body: some View {
        #if os(iOS)
            AdaptiveRootView(workspace: workspace, runner: runner)
        #else
            RegularRootView(workspace: workspace, runner: runner)
        #endif
    }
}

#if os(iOS)
    struct AdaptiveRootView: View {
        let workspace: WorkspaceModel
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
        let workspace: WorkspaceModel
        let runner: RunnerModel

        var body: some View {
            TabView {
                Tab("つくる", systemImage: "square.stack.3d.up") {
                    VStack(spacing: 0) {
                        WorkspaceView(workspace: workspace)
                        Divider()
                        PaletteStrip(workspace: workspace)
                            .padding(.vertical, 8)
                    }
                }
                Tab("うごかす", systemImage: "tortoise") {
                    CanvasPane(workspace: workspace, runner: runner)
                }
            }
        }
    }
#endif

struct RegularRootView: View {
    let workspace: WorkspaceModel
    let runner: RunnerModel

    var body: some View {
        HStack(spacing: 0) {
            PaletteView(workspace: workspace)
                .frame(width: 220)
            Divider()
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 440)
            Divider()
            CanvasPane(workspace: workspace, runner: runner)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The drawing side: canvas + playback controls, wired to the workspace.
struct CanvasPane: View {
    let workspace: WorkspaceModel
    @Bindable var runner: RunnerModel

    var body: some View {
        VStack(spacing: 0) {
            TortoiseCanvas(runner.tortoise, player: runner.player)
                .padding()
            Divider()
            PlaybackControls(workspace: workspace, runner: runner)
                .padding()
        }
        .alert("ブロックがおおすぎるよ", isPresented: $runner.showsExpansionError) {
            Button("わかった", role: .cancel) {}
        } message: {
            Text("くりかえしのかずをちいさくしてみてね")
        }
    }
}

/// Run / clear / pause / step / speed, driving the runner and player.
struct PlaybackControls: View {
    let workspace: WorkspaceModel
    @Bindable var runner: RunnerModel

    var body: some View {
        @Bindable var player = runner.player
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button("うごかす", systemImage: "play.fill") {
                    runner.run(workspace.blocks)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspace.blocks.isEmpty)
                Button("けす", systemImage: "trash") {
                    runner.clear()
                }
                Spacer()
                Text("コマンド: \(runner.player.currentCommandIndex + 1)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Toggle("いちじていし", systemImage: "pause.fill", isOn: $player.isPaused)
                    .toggleStyle(.button)
                Button("いっぽすすむ", systemImage: "forward.frame.fill") {
                    runner.player.step()
                }
                .disabled(!runner.player.isPaused)
                SpeedSlider(player: runner.player)
            }
        }
    }
}

/// Viewer-side speed control bound to `TortoisePlayer.speedOverride`.
struct SpeedSlider: View {
    @Bindable var player: TortoisePlayer

    var body: some View {
        HStack {
            Label("はやさ", systemImage: "tortoise")
                .labelStyle(.iconOnly)
            Slider(value: speed, in: 1...10, step: 1) {
                Text("はやさ")
            }
            .frame(maxWidth: 240)
            Label("はやさ", systemImage: "hare")
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
    ContentView()
}
