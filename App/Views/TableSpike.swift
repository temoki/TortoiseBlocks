#if os(visionOS)

    import RealityKit
    import SwiftUI
    import TortoiseBlocksKit
    import TortoiseUI

    // Phase 0 spike for #53 — **throwaway**. This exists to answer three
    // questions on a real Vision Pro and then be deleted:
    //
    //   1. Is a drawing laid on a real table legible as line work?
    //   2. How big should it be? (`Size.every` is the measuring stick.)
    //   3. Does a 10,000-command program still play at a usable frame rate?
    //
    // It deliberately bolts onto the existing DocumentGroup app rather than
    // building the viewer #53 actually describes: the point is to measure the
    // rendering, not to prototype the product. Every string here is
    // `Text(verbatim:)` so a spike never lands in `Localizable.xcstrings`.
    //
    // The one real finding is already baked into the shape of this file:
    // **no texture pipeline is needed.** `ViewAttachmentComponent` (visionOS
    // 26) puts a live SwiftUI view into the RealityKit scene, so the canvas on
    // the table is the *same* `TortoiseCanvas` the pane draws, driven by the
    // same `CommandPlayer`. Option (a) in #53 costs one entity, and the
    // highlight alignment that #53 calls load-bearing is untouched because
    // nothing about the command stream changed.

    /// Shared between the document window (which owns the runner) and the
    /// immersive space (which is a separate `Scene` and can't see it).
    @Observable
    @MainActor
    final class TableSpikeModel {
        static let spaceID = "table-spike"

        /// The runner whose canvas goes on the table. Set by `CanvasPane` when
        /// the space opens; nil means nothing to draw.
        var runner: RunnerModel?

        /// Length of the canvas's side on the table, in metres.
        var side: Size = .sixty

        /// Anchor to a detected horizontal surface, or hang at a fixed spot.
        /// The fixed spot is not only a fallback — it is the only mode the
        /// simulator can show, since ARKit finds no planes there, which is why
        /// the launch-argument route starts with it off.
        var anchorsToTable = !TableSpikeModel.autoOpens

        var isOpen = false

        /// `-TBSpike YES` puts the table up at launch on a built-in sample.
        ///
        /// Without it the spike is unreachable from the simulator: a visionOS
        /// `DocumentGroup` ignores `simctl openurl` (the trick that opens a
        /// document on iPadOS), simctl cannot send taps, and the custom
        /// `DocumentGroupLaunchScene` never appears — visionOS goes straight to
        /// the system browser, so there is no view of ours to hang a `.task`
        /// on either. Presenting the space itself at launch is what is left.
        static var autoOpens: Bool {
            UserDefaults.standard.bool(forKey: "TBSpike")
        }

        /// The runner to draw, falling back to a document-less one on a
        /// built-in sample — which is the only kind the launch-argument route
        /// can have. `SampleBlocks` is already public and already what the
        /// app's own 「みほん」 uses, so the spike needs no bundled file.
        func runnerOrSample() -> RunnerModel {
            if let runner { return runner }
            let made = RunnerModel()
            made.run(SampleBlocks.spiral())
            runner = made
            return made
        }

        /// Discrete sizes rather than a slider, because changing the size
        /// rebuilds the attachment at a new point size (that is the whole
        /// point — scaling the entity instead would resample one texture and
        /// measure the wrong thing). Rare, deliberate changes suit a rebuild;
        /// a slider dragging through them would not.
        enum Size: Double, CaseIterable, Identifiable {
            case forty = 0.4
            case sixty = 0.6
            case eighty = 0.8
            case hundred = 1.0

            var id: Double { rawValue }
            var label: String { "\(Int(rawValue * 100))cm" }
        }
    }

    /// The immersive space: one entity, lying flat.
    struct TableSpikeSpace: View {
        @Environment(TableSpikeModel.self) private var model

        /// visionOS lays SwiftUI out in points and the world in metres. This
        /// is the conversion, read from the scene rather than guessed at — it
        /// is what makes "60cm" mean 60cm instead of an arbitrary scale
        /// factor, and it is the number Phase 1 will need for real.
        @PhysicalMetric(from: .meters) private var pointsPerMeter: CGFloat = 1

        var body: some View {
            RealityView { content in
                let runner = model.runnerOrSample()
                let side = model.side.rawValue * pointsPerMeter

                let canvas = Entity()
                canvas.components.set(
                    ViewAttachmentComponent(
                        rootView: TableCanvasSheet(runner: runner, side: side)))
                // A SwiftUI attachment stands upright facing the viewer; a
                // drawing on a table has to lie down.
                canvas.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

                if model.anchorsToTable {
                    content.add(
                        AnchorEntity(
                            .plane(.horizontal, classification: .table, minimumBounds: [0.2, 0.2])
                        ).addingChild(canvas))
                }
                else {
                    // **An immersive space's origin is on the floor**, under
                    // where the wearer started — not at eye level. The first
                    // try put this at y = -0.4 for "desk height below the
                    // eyes" and buried both entities under the floor, which
                    // looks exactly like nothing rendering at all.
                    // Higher than a real table so the simulator's fixed
                    // horizontal gaze can see it — this mode is for checking
                    // that the drawing renders, not for judging its height.
                    canvas.position = [0, 1.0, -1.2]
                    content.add(canvas)
                }
            }
            // Both of these change what is built, not how it is positioned, so
            // they rebuild rather than update.
            .id("\(model.side.rawValue)-\(model.anchorsToTable)")
        }
    }

    /// What actually goes on the table: the app's own canvas, unchanged.
    private struct TableCanvasSheet: View {
        let runner: RunnerModel
        let side: CGFloat

        var body: some View {
            TortoiseCanvas(runner.tortoise, player: runner.player)
                .tortoiseSprite(CanvasPane.sprite)
                // Paper, for the same reason the pane paints it: the default
                // pen is black and a table is not white.
                .background(.white)
                .frame(width: side, height: side)
        }
    }

    /// The spike's controls, parked under the playback row in `CanvasPane`.
    struct TableSpikeBar: View {
        let runner: RunnerModel

        @Environment(TableSpikeModel.self) private var model
        @Environment(\.openImmersiveSpace) private var openSpace
        @Environment(\.dismissImmersiveSpace) private var dismissSpace

        var body: some View {
            @Bindable var model = model
            HStack {
                Button(model.isOpen ? "しまう" : "つくえに おく", systemImage: "table.furniture") {
                    Task { await toggle() }
                }
                .buttonStyle(.borderedProminent)

                Picker(selection: $model.side) {
                    ForEach(TableSpikeModel.Size.allCases) { size in
                        Text(verbatim: size.label).tag(size)
                    }
                } label: {
                    Text(verbatim: "おおきさ")
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Toggle(isOn: $model.anchorsToTable) {
                    Text(verbatim: "平面に置く")
                }
                .toggleStyle(.switch)
                .fixedSize()

                Spacer()
                Text(verbatim: "spike #53")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }

        private func toggle() async {
            if model.isOpen {
                await dismissSpace()
                model.isOpen = false
            }
            else {
                model.runner = runner
                if case .opened = await openSpace(id: TableSpikeModel.spaceID) {
                    model.isOpen = true
                }
            }
        }
    }

    /// The window `-TBSpike YES` launches into, whose only job is to open the
    /// space. `defaultLaunchBehavior(.presented)` on the `ImmersiveSpace`
    /// itself does nothing here — the log shows the scene declared with
    /// `immersiveStyle = Mixed` and then `requesting immersive or volume NO` —
    /// because the `DocumentGroup` takes the launch. A window can take it
    /// instead, and `openImmersiveSpace` from inside one does work.
    struct TableSpikeLauncher: View {
        @Environment(TableSpikeModel.self) private var model
        @Environment(\.openImmersiveSpace) private var openSpace

        var body: some View {
            VStack(spacing: 12) {
                Text(verbatim: "spike #53")
                    .font(.largeTitle)
                Text(verbatim: "つくえの うえに みほんを おいています…")
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .task {
                guard !model.isOpen else { return }
                if case .opened = await openSpace(id: TableSpikeModel.spaceID) {
                    model.isOpen = true
                }
            }
        }
    }

    extension Entity {
        /// `content.add(AnchorEntity(…).addingChild(canvas))` reads better than
        /// the three statements it replaces, and this file has no other use for
        /// a local variable holding the anchor.
        fileprivate func addingChild(_ child: Entity) -> Entity {
            addChild(child)
            return self
        }
    }

#endif
