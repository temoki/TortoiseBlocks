#if os(visionOS)

    import RealityKit
    import Spatial
    import SwiftUI
    import TortoiseBlocksKit
    import TortoiseUI

    // The visionOS viewer's drawing surface (#53): a sheet of paper lying on a
    // real table, with the tortoise walking across it.
    //
    // **No texture pipeline, and no stroke geometry.** #53 framed the renderer
    // as a choice between the two; `ViewAttachmentComponent` (visionOS 26) is a
    // third answer that costs neither. It puts a live SwiftUI view into the
    // RealityKit scene, so what lies on the table is the *same*
    // `TortoiseCanvas` the iPad and Mac panes draw, driven by the same
    // `CommandPlayer`. Nothing about the command stream changes, which is what
    // keeps the executing-block alignment (`RunnerModel.currentBlockID`)
    // available for free when the read-only program window arrives.

    /// Everything the viewer holds: the program on screen, the runner playing
    /// it, and where the sheet sits in the room.
    ///
    /// One object across two scenes — the window owns the controls, the
    /// immersive space owns the drawing, and a `Scene` cannot see another
    /// scene's state.
    @Observable
    @MainActor
    final class ViewerModel {
        static let spaceID = "table"

        // MARK: What is loaded

        /// The name shown in the window. A document's file name, a sample's
        /// title, or empty when nothing has been opened yet.
        private(set) var title = ""
        private(set) var blocks: [Block] = []
        let runner = RunnerModel()

        /// Set when opening a file fails, and shown as an alert. Kept as the
        /// message rather than the error so the version gate's wording
        /// (`DocumentError.newerSchema`) survives to the alert unchanged.
        var openFailure: String?

        var hasProgram: Bool { !blocks.isEmpty }

        func load(_ blocks: [Block], title: String) {
            self.blocks = blocks
            self.title = title
            runner.run(blocks, startPaused: true)
        }

        /// Opens a `.tortoise` from the file importer. The URL comes from
        /// outside the sandbox, so it has to be asked for before it can be
        /// read — and given back whether or not the read worked.
        func open(_ url: URL) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let project = try BlocksDocument.project(from: Data(contentsOf: url))
                load(project.blocks, title: url.deletingPathExtension().lastPathComponent)
            }
            catch {
                openFailure = error.localizedDescription
            }
        }

        // MARK: Where the sheet sits

        /// Committed size of the sheet's side, in metres. Bounded because an
        /// unbounded pinch reaches a 50m canvas in about a second; 2m at the
        /// top because a drawing that fills a whole table is a thing people
        /// want, and it stays legible there.
        var side: Double = 0.6
        static let sideRange: ClosedRange<Double> = 0.2...2.0

        /// The size the one render is built at — **the resolution knob**.
        ///
        /// A pinch scales the *entity* rather than rebuilding the attachment,
        /// because rebuilding mid-drag re-runs the anchor search and makes the
        /// drawing jump. So the sheet carries one render of a fixed point size
        /// and stretches it, and this is that size.
        ///
        /// visionOS lays out at **1m = 1360pt**, so 1.0 here is a 1360pt²
        /// render. What that buys depends on how big the sheet is shown: about
        /// 2270pt per displayed metre at the 60cm default, 680 at the 2m top of
        /// the range — a 3.3× spread, which is where the slight softness at the
        /// large end comes from. Raising this is the fix and it costs the
        /// square: 2.0 would be 2720pt², four times the pixels, heading toward
        /// texture-size limits at 2× backing.
        ///
        /// Do **not** conclude from the one measurement so far that this has no
        /// effect. It was tried at 1.2 against 1.0 and looked identical on
        /// device — but that is a 20% change in linear resolution, which is
        /// about what "identical" should look like. A real test is a 2× swing,
        /// judged at *one* displayed size.
        static let builtSide: Double = 1.0

        /// Committed rotation about the vertical axis, in radians.
        ///
        /// A 2-D `RotateGesture` is the wrong tool even though the geometry
        /// invites it: on visionOS it wants **two hands**, so a one-handed
        /// wrist turn does nothing and two-handed attempts fight the magnify.
        /// `RotateGesture3D(constrainedToAxis: .y)` is the one that means "turn
        /// your wrist, and only the vertical axis counts".
        var spin: Double = 0

        /// Committed translation, in the entity's **parent** space — the plane
        /// anchor when there is one, so a drag stays right without the app ever
        /// reading that anchor's transform (which visionOS does not hand out).
        var offset: SIMD3<Float> = .zero

        /// In-flight gesture values, applying on top of the committed ones
        /// until the gesture ends. Kept apart so a cancelled gesture leaves
        /// nothing behind.
        var liveScale: Double = 1
        var liveSpin: Double = 0
        var liveOffset: SIMD3<Float> = .zero

        /// Sit on a detected horizontal surface, or hang in front of the
        /// wearer. The second is the fallback #53 asks for — a room with no
        /// table, a refused world-sensing prompt, and the simulator, where
        /// ARKit finds no planes at all.
        var sitsOnTable = true

        var isPlaced = false

        var visibleSide: Double { (side * liveScale).clamped(to: Self.sideRange) }
        var visibleSpin: Double { spin + liveSpin }
        var visibleOffset: SIMD3<Float> { offset + liveOffset }

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

        func commitOffset(_ translation: SIMD3<Float>) {
            offset += translation
            liveOffset = .zero
        }

        func resetPlacement() {
            side = 0.6
            spin = 0
            offset = .zero
            liveScale = 1
            liveSpin = 0
            liveOffset = .zero
        }

        /// The signed turn a constrained `RotateGesture3D` describes. Held to
        /// the vertical axis, the rotation's own axis comes back as ±Y and its
        /// sign is the direction — the angle alone is unsigned.
        static func verticalAngle(of rotation: Rotation3D) -> Double {
            rotation.angle.radians * (rotation.axis.y < 0 ? -1 : 1)
        }
    }

    extension Double {
        fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
            min(max(self, range.lowerBound), range.upperBound)
        }
    }

    /// The immersive space: one sheet, lying flat, placed by hand.
    struct TableCanvasSpace: View {
        let model: ViewerModel

        /// visionOS lays SwiftUI out in points and the world in metres. This is
        /// the conversion, read from the scene rather than guessed at — it is
        /// what makes "60cm" mean 60cm instead of an arbitrary scale factor.
        @PhysicalMetric(from: .meters) private var pointsPerMeter: CGFloat = 1

        private static let sheetName = "table-canvas"

        var body: some View {
            RealityView { content in
                let sheet = Entity()
                sheet.name = Self.sheetName
                sheet.components.set(
                    ViewAttachmentComponent(
                        rootView: TableCanvasSheet(
                            runner: model.runner,
                            side: ViewerModel.builtSide * pointsPerMeter)))
                // The gestures target the *entity*, so it needs a shape to be
                // hit and a component saying it accepts input. The box lies in
                // the view's own plane and scales with the entity, so it keeps
                // matching the sheet.
                sheet.components.set(InputTargetComponent())
                sheet.components.set(
                    CollisionComponent(shapes: [
                        .generateBox(
                            size: [
                                Float(ViewerModel.builtSide), Float(ViewerModel.builtSide), 0.005,
                            ]
                        )
                    ]))

                if model.sitsOnTable {
                    content.add(
                        AnchorEntity(
                            .plane(.horizontal, classification: .table, minimumBounds: [0.2, 0.2])
                        ).addingChild(sheet))
                }
                else {
                    content.add(sheet)
                }
            } update: { content in
                guard let sheet = Self.sheet(in: content) else { return }
                sheet.position = Self.home(onTable: model.sitsOnTable) + model.visibleOffset
                sheet.scale = .init(repeating: model.entityScale)
                // Lie flat first, then spin about the parent's vertical axis —
                // the plane's normal when anchored, and up either way.
                sheet.orientation =
                    simd_quatf(angle: Float(model.visibleSpin), axis: [0, 1, 0])
                    * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            }
            // Only the placement mode rebuilds; size, spin and position are
            // transforms on the entity that is already there.
            .id(model.sitsOnTable)
            // All three run together, the way a hand does them: a pinch that
            // drifts and turns should move and spin rather than pick one. The
            // rotation's 5° threshold keeps an ordinary drag from spinning the
            // sheet on the way past.
            .gesture(
                DragGesture()
                    .targetedToAnyEntity()
                    .onChanged {
                        model.liveOffset = Self.translation(
                            of: $0, keepingOnPlane: model.sitsOnTable)
                    }
                    .onEnded {
                        model.commitOffset(
                            Self.translation(of: $0, keepingOnPlane: model.sitsOnTable))
                    }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: .y, minimumAngleDelta: .degrees(5))
                    .targetedToAnyEntity()
                    .onChanged {
                        model.liveSpin = ViewerModel.verticalAngle(of: $0.gestureValue.rotation)
                    }
                    .onEnded {
                        model.commitSpin(ViewerModel.verticalAngle(of: $0.gestureValue.rotation))
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .targetedToAnyEntity()
                    .onChanged { model.liveScale = $0.gestureValue.magnification }
                    .onEnded { model.commitScale($0.gestureValue.magnification) }
            )
        }

        /// Where the sheet sits before the wearer moves it.
        ///
        /// **An immersive space's origin is on the floor**, under where the
        /// wearer started — not at eye level. Placing the fallback at a
        /// negative height for "desk height, below the eyes" buries it under
        /// the floor, which looks exactly like nothing rendering at all. The
        /// anchored placement is the plane's own origin and needs no height of
        /// its own.
        private static func home(onTable: Bool) -> SIMD3<Float> {
            onTable ? .zero : [0, 1.0, -1.2]
        }

        /// A drag's translation in the entity's parent space, which is where
        /// `position` is read. Converting to `.scene` instead would be wrong
        /// the moment the sheet hangs off a plane anchor.
        ///
        /// `keepingOnPlane` is what stops a drag lifting the sheet off the
        /// table: on a plane anchor the parent's Y **is** the plane's normal,
        /// so dropping that one component slides the drawing along the surface
        /// instead of into the air. It is off in the floating placement, where
        /// there is no surface to stay on and height is the only way to put the
        /// sheet somewhere sensible.
        private static func translation(
            of value: EntityTargetValue<DragGesture.Value>, keepingOnPlane: Bool
        ) -> SIMD3<Float> {
            guard let parent = value.entity.parent else { return .zero }
            var delta = value.convert(value.gestureValue.translation3D, from: .local, to: parent)
            if keepingOnPlane { delta.y = 0 }
            return delta
        }

        private static func sheet(in content: RealityViewContent) -> Entity? {
            for root in content.entities {
                if let found = root.findEntity(named: sheetName) { return found }
            }
            return nil
        }
    }

    /// What actually lies on the table: the app's own canvas, unchanged.
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
                // The pinch, twist and drag belong to the entity. Left
                // hit-testable, this view swallows them first and the sheet can
                // never be moved at all.
                .allowsHitTesting(false)
        }
    }

    extension Entity {
        /// `content.add(AnchorEntity(…).addingChild(sheet))` reads better than
        /// the three statements it replaces, and this file has no other use for
        /// a local variable holding the anchor.
        fileprivate func addingChild(_ child: Entity) -> Entity {
            addChild(child)
            return self
        }
    }

#endif
