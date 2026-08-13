#if os(visionOS)

    import RealityKit
    import SwiftUI
    import TortoiseBlocksKit
    import TortoiseUI

    // Phase 0 spike for #53 — **throwaway**. This exists to answer three
    // questions on a real Vision Pro and then be deleted:
    //
    //   1. Is a drawing laid on a real table legible as line work? — **yes**,
    //      answered on device.
    //   2. How big should it be? — **wrong question.** There is no right size;
    //      the wearer sets it, so the size and the spin are gestures now and
    //      what is left to learn is where people actually land.
    //   3. Does a 10,000-command program still play at a usable frame rate?
    //      — still open.
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

        /// The point size the attachment is built at, expressed in metres.
        ///
        /// The wearer's pinch scales the *entity*, not this — rebuilding the
        /// attachment mid-gesture would re-run the anchor search and make the
        /// drawing jump every time it is resized. So one render is made at
        /// this size and scaled from there, which never softens below it and
        /// may above it: **whether the upper end goes visibly soft is a Phase 0
        /// question to answer on device**, and the reason this is 1m rather
        /// than the 60cm the drawing usually sits at.
        static let builtSide: Double = 1.0

        /// Committed size of the sheet's side, in metres. Bounded because an
        /// unbounded pinch reaches a 50m canvas in about a second.
        var side: Double = 0.6
        static let sideRange: ClosedRange<Double> = 0.15...2.0

        /// Committed rotation about the vertical axis, in radians. A sheet
        /// lying flat has its normal straight up, so a plain 2-D twist *is*
        /// the vertical-axis spin — no 3-D rotation gesture needed.
        var spin: Double = 0

        /// In-flight gesture values: a multiplier and an offset that apply on
        /// top of the committed ones until the gesture ends. Kept apart from
        /// the committed values so a cancelled gesture leaves nothing behind.
        var liveScale: Double = 1
        var liveSpin: Double = 0

        /// What the wearer is actually looking at, gesture included.
        var visibleSide: Double {
            (side * liveScale).clamped(to: Self.sideRange)
        }

        var visibleSpin: Double { spin + liveSpin }

        /// The entity scale that turns the one built render into that size.
        var entityScale: Float { Float(visibleSide / Self.builtSide) }

        func commitScale(_ magnification: Double) {
            side = (side * magnification).clamped(to: Self.sideRange)
            liveScale = 1
        }

        func commitSpin(_ radians: Double) {
            spin += radians
            liveSpin = 0
        }

        func resetPlacement() {
            side = 0.6
            spin = 0
            liveScale = 1
            liveSpin = 0
        }

        /// The runner whose canvas goes on the table. Set by `CanvasPane` when
        /// the space opens from the app.
        var runner: RunnerModel?

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
    }

    extension Double {
        fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
            min(max(self, range.lowerBound), range.upperBound)
        }
    }

    /// The immersive space: one entity, lying flat, sized and spun by hand.
    struct TableSpikeSpace: View {
        @Environment(TableSpikeModel.self) private var model

        /// visionOS lays SwiftUI out in points and the world in metres. This
        /// is the conversion, read from the scene rather than guessed at — it
        /// is what makes "60cm" mean 60cm instead of an arbitrary scale
        /// factor, and it is the number Phase 1 will need for real.
        @PhysicalMetric(from: .meters) private var pointsPerMeter: CGFloat = 1

        private static let canvasName = "table-spike-canvas"

        var body: some View {
            RealityView { content in
                let runner = model.runnerOrSample()
                let built = TableSpikeModel.builtSide

                let canvas = Entity()
                canvas.name = Self.canvasName
                canvas.components.set(
                    ViewAttachmentComponent(
                        rootView: TableCanvasSheet(
                            runner: runner, side: built * pointsPerMeter)))
                // The gestures are targeted at the *entity*, so it needs a
                // shape to be hit and a component saying it accepts input.
                // The box is in the view's own plane (normal +Z) and scales
                // with the entity, so it keeps matching the sheet.
                canvas.components.set(InputTargetComponent())
                canvas.components.set(
                    CollisionComponent(shapes: [
                        .generateBox(size: [Float(built), Float(built), 0.005])
                    ]))

                if model.anchorsToTable {
                    content.add(
                        AnchorEntity(
                            .plane(.horizontal, classification: .table, minimumBounds: [0.2, 0.2])
                        ).addingChild(canvas))
                }
                else {
                    // **An immersive space's origin is on the floor**, under
                    // where the wearer started — not at eye level. The first
                    // try put this at y = -0.4 for "desk height, below the
                    // eyes" and buried it under the floor, which looks exactly
                    // like nothing rendering at all.
                    //
                    // Higher than a real table so the simulator's fixed
                    // horizontal gaze can see it — this mode is for checking
                    // that the drawing renders, not for judging its height.
                    canvas.position = [0, 1.0, -1.2]
                    content.add(canvas)
                }
            } update: { content in
                guard let canvas = Self.canvas(in: content) else { return }
                canvas.scale = .init(repeating: model.entityScale)
                // Lie flat first, then spin about the world's vertical axis.
                canvas.orientation =
                    simd_quatf(angle: Float(model.visibleSpin), axis: [0, 1, 0])
                    * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            }
            // Only the placement mode rebuilds; size and spin are transforms
            // on the entity that is already there.
            .id(model.anchorsToTable)
            .gesture(
                MagnifyGesture()
                    .targetedToAnyEntity()
                    .onChanged { model.liveScale = $0.gestureValue.magnification }
                    .onEnded { model.commitScale($0.gestureValue.magnification) }
            )
            .simultaneousGesture(
                RotateGesture()
                    .targetedToAnyEntity()
                    .onChanged { model.liveSpin = $0.gestureValue.rotation.radians }
                    .onEnded { model.commitSpin($0.gestureValue.rotation.radians) }
            )
        }

        private static func canvas(in content: RealityViewContent) -> Entity? {
            for root in content.entities {
                if let found = root.findEntity(named: canvasName) { return found }
            }
            return nil
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
                // The pinch and the twist belong to the entity. Left hit-
                // testable, this view would swallow them first and the sheet
                // could never be resized.
                .allowsHitTesting(false)
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

                Toggle(isOn: $model.anchorsToTable) {
                    Text(verbatim: "平面に置く")
                }
                .toggleStyle(.switch)
                .fixedSize()

                Spacer()

                // The readout is the measurement: there is no right size, but
                // where wearers actually settle is worth knowing before
                // Phase 1 picks a default.
                Text(verbatim: "\(Int((model.visibleSide * 100).rounded()))cm")
                    .monospacedDigit()
                Text(verbatim: "\(Int(Angle(radians: model.visibleSpin).degrees.rounded()))°")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("もとに もどす", systemImage: "arrow.counterclockwise") {
                    model.resetPlacement()
                }
                .labelStyle(.iconOnly)

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
                Text(verbatim: "\(Int((model.visibleSide * 100).rounded()))cm")
                    .monospacedDigit()
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
