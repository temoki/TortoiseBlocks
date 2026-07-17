import SwiftUI
import TortoiseBlocksKit
import TortoiseUI

/// M0 walking skeleton: a hardcoded command stream drawn by
/// `TortoiseCanvas(_:player:)` with full playback controls.
/// The workspace/palette editor replaces the sample picker from M2 on.
struct ContentView: View {
    @State private var tortoise = Tortoise()
    @State private var player = TortoisePlayer()

    var body: some View {
        VStack(spacing: 0) {
            TortoiseCanvas(tortoise, player: player)
                .padding()
            Divider()
            PlaybackControls(tortoise: tortoise, player: player)
                .padding()
        }
    }
}

/// Run / pause / step / speed controls driving a `TortoisePlayer`.
struct PlaybackControls: View {
    let tortoise: Tortoise
    @Bindable var player: TortoisePlayer

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button("ほしをかく", systemImage: "play.fill") {
                    run(SampleProgram.star())
                }
                Button("しかくをかく", systemImage: "play.fill") {
                    run(SampleProgram.filledSquare())
                }
                Button("けす", systemImage: "trash") {
                    tortoise.reset()
                }
                Spacer()
                Text("コマンド: \(player.currentCommandIndex + 1)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Toggle("いちじていし", systemImage: "pause.fill", isOn: $player.isPaused)
                    .toggleStyle(.button)
                Button("いっぽすすむ", systemImage: "forward.frame.fill") {
                    player.step()
                }
                .disabled(!player.isPaused)
                SpeedSlider(player: player)
            }
        }
    }

    private func run(_ commands: [TortoiseCommand]) {
        tortoise.reset()
        tortoise.apply(commands)
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
