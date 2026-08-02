import SwiftUI
import TortoiseBlocksKit
import TortoiseUI

/// The playback transport, laid out like a video player (#28): a scrubber
/// with the position at each end, then rewind / step back / centre / step
/// forward / speed.
///
/// There is no disclosure and no clear button. Everything that controls
/// playback is visible at once, and "roll the dice again" lives on the canvas
/// itself (`CanvasRollAgainButton`) because it re-runs the program rather
/// than moving the playhead.
struct PlaybackControls: View {
    let workspace: WorkspaceEditor
    @Bindable var runner: RunnerModel
    /// Whether the workspace has been edited since the run on screen.
    /// Hoisted to the pane rather than computed here: deciding it hashes the
    /// whole block tree, and this view re-renders on every committed command.
    let isStale: Bool

    // Media-transport glyphs are read at a glance, not inspected, so they run
    // well above body size — and scale with Dynamic Type from there.
    @ScaledMetric private var glyph: CGFloat = 28
    /// The centre button carries the same glyph as its neighbours; what makes
    /// it primary is the filled circle around it, sized outright rather than
    /// left to the button style's padding.
    @ScaledMetric private var centerDiameter: CGFloat = 56
    @ScaledMetric private var centerGap: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            PlaybackScrubber(runner: runner)
            // Frame-advance and play sit centred as one group; the two
            // secondary controls pin to the edges. Equal flexible side slots
            // keep the centre honest however wide the speed chip reads.
            HStack(spacing: 0) {
                Button("Back to Start", systemImage: "backward.end.fill") {
                    runner.seek(to: -1)
                }
                .disabled(!runner.canStep || runner.player.currentCommandIndex < 0)
                .font(.system(size: glyph))
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: centerGap) {
                    // `.frame` glyphs, not `.fill` chevrons: double arrows read
                    // as scrub-by-seconds, and these move exactly one command.
                    Button("Step Back", systemImage: "backward.frame.fill") {
                        runner.seek(to: runner.player.currentCommandIndex - 1)
                    }
                    .disabled(!runner.canStep || runner.player.currentCommandIndex < 0)
                    .font(.system(size: glyph))

                    TransportCenterButton(
                        action: action, glyph: glyph, diameter: centerDiameter,
                        perform: perform)

                    Button("Step Forward", systemImage: "forward.frame.fill") {
                        runner.player.step()
                    }
                    .disabled(
                        !runner.canStep
                            || runner.player.currentCommandIndex >= runner.commandCount - 1
                    )
                    .font(.system(size: glyph))
                }

                PlaybackSpeedMenu(player: runner.player)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// What the centre button means right now. One button, four jobs — the
    /// same position always answers "what happens if I press this".
    private var action: TransportAction {
        if isStale { return .run }
        if runner.player.isFinished { return .replay }
        guard runner.player.isPaused else { return .pause }
        // A stream that is loaded but hasn't moved yet — rolling again leaves
        // one waiting here — is started, not resumed.
        return runner.player.currentCommandIndex < 0 ? .play : .resume
    }

    private func perform() {
        switch action {
        case .run: runner.run(workspace.blocks)
        case .pause: runner.player.isPaused = true
        case .play, .resume: runner.player.isPaused = false
        case .replay: runner.replay()
        }
    }
}

/// The four meanings the centre button carries.
enum TransportAction {
    /// Nothing has run, or the blocks changed since the run on screen.
    case run
    case pause
    /// A stream is loaded and waiting at the start.
    case play
    case resume
    /// Play the same command stream again from the start — the identical
    /// picture. Rolling fresh dice is `run` instead.
    case replay

    var title: LocalizedStringKey {
        switch self {
        case .run: "Run"
        case .pause: "Pause"
        case .play: "Play"
        case .resume: "Resume"
        case .replay: "Play Again"
        }
    }

    var systemImage: String {
        switch self {
        case .pause: "pause.fill"
        case .run, .play, .resume, .replay: "play.fill"
        }
    }

    /// Whether pressing this expands the block tree and starts a program.
    /// Drives the accent, so the colour answers "will this redraw my
    /// picture?" before the press — every run-ish control shares it, and
    /// plain transport controls stay uncoloured.
    var runsProgram: Bool { self == .run }
}

private struct TransportCenterButton: View {
    let action: TransportAction
    let glyph: CGFloat
    let diameter: CGFloat
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            // Sizing the *label* is what grows the circle: a frame on the
            // finished button would only pad around a style-sized background.
            Label(action.title, systemImage: action.systemImage)
                .font(.system(size: glyph))
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        // `.gray`, not `.secondary`: the neutral state is a *fill*, and
        // `Color.secondary` is a label style. Handed to `tint` it resolves per
        // platform — iOS lands on a mid grey, macOS on something near black,
        // so the primary control turned into the darkest thing in the row the
        // moment a run finished. An explicit system grey reads the same on
        // both.
        .tint(action.runsProgram ? .accentColor : .gray)
        // The label changes with the action, so VoiceOver announces what
        // the press will do — which is also why this is a Button and not
        // a Toggle bound to `isPaused`.
        .accessibilityLabel(Text(action.title))
    }
}

/// Timeline scrubber with the position at each end, like a video player's
/// elapsed / total. Seeks forward and backward, even mid-run.
struct PlaybackScrubber: View {
    let runner: RunnerModel

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: positionText)
            // Continuous on purpose. A stepped Slider carries one tick mark
            // per step, and the cost of a redraw grows with how many there
            // are — worse than linearly. Measured at 420pt on macOS, one
            // update of this row: 2.5ms at 200 commands, 25ms at 1,000,
            // 86ms at 2,000, against a flat 0.35ms with no step at all. The
            // scrubber redraws on *every* committed command, so a repeat of
            // a few hundred spent the whole frame here and the drawing
            // stuttered. The position is quantized either way — the binding
            // below rounds before it seeks — so `step` bought nothing.
            Slider(value: position, in: -1...Double(max(runner.commandCount - 1, 0))) {
                Text("Position")
            }
            .labelsHidden()
            .disabled(runner.commandCount == 0)
            .accessibilityValue(Text(positionAccessibilityValue))
            // A stepless slider adjusts by a fraction of its range, which for
            // a long program is many commands at once. Say outright that one
            // adjustment is one command — the same unit the step buttons and
            // the Run menu move in.
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: runner.seek(to: runner.player.currentCommandIndex + 1)
                case .decrement: runner.seek(to: runner.player.currentCommandIndex - 1)
                @unknown default: break
                }
            }
            Text(verbatim: totalText)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var position: Binding<Double> {
        Binding(
            get: { Double(runner.player.currentCommandIndex) },
            set: { runner.seek(to: Int($0.rounded())) }
        )
    }

    /// An idling scrubber (nothing run yet, or cleared) reads as a dash
    /// rather than the otherwise-confusing "0" — `currentCommandIndex`
    /// starts at -1.
    private var positionText: String {
        runner.commandCount > 0 ? "\(runner.player.currentCommandIndex + 1)" : "–"
    }

    private var totalText: String {
        runner.commandCount > 0 ? "\(runner.commandCount)" : "–"
    }

    private var positionAccessibilityValue: String {
        guard runner.commandCount > 0 else { return String(localized: "Nothing to play") }
        return String(
            localized: "Step \(runner.player.currentCommandIndex + 1) of \(runner.commandCount)")
    }
}

/// Viewer-side playback speed, offered as multiples of the normal tempo the
/// way a video player does — a menu, not a slider that eats a row.
///
/// `TortoisePlayer.speedOverride` is a 1…10 *level*, not a rate, but a step
/// lasts `0.5 / speed` seconds — so anchoring ×1 to the library's default of
/// 5 makes these multipliers exact without leaving the documented range.
enum PlaybackSpeed: Double, CaseIterable, Identifiable {
    case slowest = 1  // ×0.2
    case slow = 2.5  // ×0.5
    case normal = 5  // ×1
    case fast = 10  // ×2
    case instant = 0

    var id: Double { rawValue }

    /// Multipliers are digits and a sign — the same in every language — so
    /// only the named case needs the catalog.
    var label: String {
        switch self {
        case .slowest: "×0.2"
        case .slow: "×0.5"
        case .normal: "×1"
        case .fast: "×2"
        case .instant: String(localized: "Instant")
        }
    }
}

private struct PlaybackSpeedMenu: View {
    @Bindable var player: TortoisePlayer

    var body: some View {
        Menu {
            Picker("Speed", selection: selection) {
                ForEach(PlaybackSpeed.allCases) { speed in
                    Text(verbatim: speed.label).tag(speed)
                }
            }
        } label: {
            Text(verbatim: selection.wrappedValue.label)
                .font(.caption.monospacedDigit())
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .accessibilityLabel(Text("Speed"))
    }

    /// `speedOverride` is optional (nil = follow the stream). No block emits
    /// a speed command, so nil and ×1 are the same tempo — the menu always
    /// writes an explicit value and reads nil back as normal.
    private var selection: Binding<PlaybackSpeed> {
        Binding(
            get: { PlaybackSpeed(rawValue: player.speedOverride ?? 5) ?? .normal },
            set: { player.speedOverride = $0.rawValue }
        )
    }
}

/// Re-runs the program with fresh randomness. It sits on the canvas rather
/// than in the transport because it redraws the picture instead of moving
/// the playhead — and it took the slot the old trash button held, which
/// turned out to be redundant once the transport gained "back to start".
struct CanvasRollAgainButton: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    var body: some View {
        Button("Roll Again", systemImage: "arrow.clockwise") {
            runner.run(workspace.blocks, startPaused: true)
        }
        .disabled(workspace.blocks.isEmpty)
        .accessibilityHint("Runs the program again, rolling any dice for new values")
    }
}
