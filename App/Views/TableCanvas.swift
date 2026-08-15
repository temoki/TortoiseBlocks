#if os(visionOS)

    import ARKit
    import QuartzCore
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
        static let programWindowID = "program"

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

        /// Committed translation, in world space — which is also the sheet's
        /// parent space, now that it hangs off the scene root rather than a
        /// plane anchor.
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

        // MARK: Finding somewhere to put it

        /// How the sheet came to be where it is.
        enum Placement {
            /// Looking for a table. **The sheet is not drawn yet**, and this
            /// can take ten seconds or more, so it is a state the window has
            /// to say out loud rather than a gap it leaves unexplained.
            case searching
            /// Standing on a surface ARKit found.
            case onTable
            /// In mid-air in front of the wearer, because no surface turned up
            /// (or none was asked for).
            case floating
        }

        var placement: Placement = .searching

        /// Where the sheet was put, in world space, before the wearer moved it.
        private(set) var home: SIMD3<Float> = [0, 1.0, -1.2]

        /// The turn that puts the sheet's top edge away from the wearer.
        private(set) var homeYaw: Float = 0

        /// How far ahead of the eyes the sheet lands. Desk reach: near enough
        /// to be *the thing you are looking at*, far enough not to sit in your
        /// lap. Everything past this is the wearer's to drag.
        static let reach: Float = 0.6

        /// Drop below eye level for the floating fallback — roughly where a
        /// desk would be if there were one.
        private static let floatingDrop: Float = 0.35

        func placeOnTable(atHeight y: Float, device: simd_float4x4) {
            aim(from: device, height: y)
            placement = .onTable
        }

        /// The fallback. `device` is nil only when world tracking has not
        /// produced a pose yet, and then there is nothing to aim by — the sheet
        /// takes a fixed spot ahead of the origin instead.
        func floatInFront(device: simd_float4x4?) {
            if let device {
                aim(from: device, height: device.columns.3.y - Self.floatingDrop)
            }
            else {
                home = [0, 1.0, -1.2]
                homeYaw = 0
            }
            placement = .floating
        }

        /// Puts the sheet in front of the wearer, facing the way they face.
        ///
        /// Lying down, the sheet's top edge points along **−Z** (that is what
        /// the −90° turn about X does to the page's up direction). So the yaw
        /// that carries −Z onto the gaze direction is exactly the one that puts
        /// the drawing's *north* away from the wearer — read from where you
        /// stand, the far edge is the top, which is the way a sheet of paper on
        /// a desk is oriented without anyone thinking about it.
        private func aim(from device: simd_float4x4, height y: Float) {
            let target = Self.gazeTarget(from: device)
            home = [target.x, y, target.z]
            homeYaw = Self.yaw(from: device)
        }

        /// The spot the sheet aims for: `reach` metres ahead of the eyes, at
        /// eye height. Shared with surface picking, so "the table I am looking
        /// at" and "where on it the drawing goes" are the same point.
        static func gazeTarget(from device: simd_float4x4) -> SIMD3<Float> {
            let eye = SIMD3(device.columns.3.x, device.columns.3.y, device.columns.3.z)
            let ahead = forward(of: device)
            return eye + ahead * reach
        }

        static func yaw(from device: simd_float4x4) -> Float {
            let ahead = forward(of: device)
            return atan2(-ahead.x, -ahead.z)
        }

        /// The gaze, flattened onto the horizontal plane. A head transform
        /// looks along its own −Z; dropping the Y component is what keeps the
        /// sheet level however far up or down the wearer happens to be looking
        /// when it lands.
        static func forward(of device: simd_float4x4) -> SIMD3<Float> {
            let flat = SIMD3(-device.columns.2.x, 0, -device.columns.2.z)
            let length = simd_length(flat)
            return length > 1e-4 ? flat / length : SIMD3(0, 0, -1)
        }

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

    /// Keeps every horizontal surface ARKit has told us about, so the choice of
    /// where to put the drawing is made over the whole set rather than over
    /// whichever one happened to arrive first.
    @MainActor
    final class SurfaceCollector {
        private var surfaces: [UUID: PlaneAnchor] = [:]

        var all: [PlaneAnchor] { Array(surfaces.values) }

        func consume(_ provider: PlaneDetectionProvider) async {
            for await update in provider.anchorUpdates {
                if update.event == .removed {
                    surfaces[update.anchor.id] = nil
                }
                else {
                    surfaces[update.anchor.id] = update.anchor
                }
            }
        }
    }

    /// Everything the entity's transform depends on, gathered in `body` so
    /// Observation actually sees it change.
    private struct SheetTransform {
        let isVisible: Bool
        let position: SIMD3<Float>
        let scale: Float
        let yaw: Float
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
            // Read here, in `body`, and captured by the closure below.
            //
            // Observation only registers what a *view update* touches, and a
            // `RealityView`'s `update:` closure runs outside that — properties
            // read only in there never mark this view as needing an update, so
            // the closure is called once and never again. The symptom is total:
            // the sheet stays disabled at wherever the first frame put it, and
            // ARKit deciding where the table is changes nothing on screen.
            let sheet = SheetTransform(
                isVisible: model.placement != .searching,
                position: model.home + model.visibleOffset,
                scale: model.entityScale,
                yaw: model.homeYaw + Float(model.visibleSpin))

            return RealityView { content in
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

                // A plain entity in world space, **not** an `AnchorEntity`.
                // Anchoring to a plane is one line and answers none of the
                // three questions that matter: the system picks which surface,
                // picks where on it, and never says when it succeeded. Running
                // the providers directly is what buys "in front of your eyes",
                // "turned to face you", and a wait the window can explain.
                content.add(sheet)
            } update: { content in
                guard let entity = Self.sheet(in: content) else { return }
                print()
                // Nothing to look at until there is somewhere to put it —
                // better a considered wait than a sheet parked wherever the
                // origin happens to be.
                entity.isEnabled = sheet.isVisible
                entity.position = sheet.position
                entity.scale = .init(repeating: sheet.scale)
                // Lie flat, then turn: the yaw the placement chose, plus
                // whatever the wearer has twisted since.
                entity.orientation =
                    simd_quatf(angle: sheet.yaw, axis: [0, 1, 0])
                    * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            }
            .task { await findSomewhereToPutIt() }
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
                            of: $0, keepingOnPlane: model.placement == .onTable)
                    }
                    .onEnded {
                        model.commitOffset(
                            Self.translation(of: $0, keepingOnPlane: model.placement == .onTable))
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

        /// Long enough for a table to turn up, short enough that nobody is left
        /// staring at nothing wondering whether it is broken. Measured against
        /// the ten-plus seconds plane detection actually took on device.
        private static let searchTimeout: Duration = .seconds(15)

        /// Finds a table, or gives up and floats — and either way ends with the
        /// sheet in front of the wearer, turned to face them.
        private func findSomewhereToPutIt() async {
            let session = ARKitSession()
            let world = WorldTrackingProvider()
            let planes = PlaneDetectionProvider(alignments: [.horizontal])
            model.placement = .searching

            do {
                try await session.run(model.sitsOnTable ? [world, planes] : [world])
            }
            catch {
                // A refused world-sensing prompt lands here, and it is not an
                // error worth showing a child: floating is a perfectly good way
                // to look at a drawing.
                model.floatInFront(device: nil)
                return
            }

            guard model.sitsOnTable else {
                model.floatInFront(device: await Self.pose(from: world))
                return
            }
            guard let device = await Self.pose(from: world) else {
                model.floatInFront(device: nil)
                return
            }

            // Collected rather than consumed. Taking the **first** surface that
            // passed was the whole of the "it keeps choosing the floor" bug:
            // updates arrive in no useful order, and a floor is large, flat and
            // found early, so it won nearly every race it was allowed to enter.
            let surfaces = SurfaceCollector()
            let collecting = Task { await surfaces.consume(planes) }
            defer { collecting.cancel() }

            let clock = ContinuousClock()
            let started = clock.now
            var firstSeen: ContinuousClock.Instant?

            while clock.now - started < Self.searchTimeout {
                if let best = Self.bestSurface(among: surfaces.all, device: device) {
                    firstSeen = firstSeen ?? clock.now
                    // A table by name is the answer outright. Anything else is
                    // a guess worth holding a moment, in case the real table is
                    // still being mapped.
                    if best.surfaceClassification == .table
                        || clock.now - firstSeen! >= Self.settleDelay
                    {
                        model.placeOnTable(
                            atHeight: best.originFromAnchorTransform.columns.3.y, device: device)
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            model.floatInFront(device: device)
        }

        /// The surface to put the drawing on: the one nearest to where the
        /// wearer is looking, out of those that could be a table at all.
        ///
        /// **Height is tested two ways, and each covers the other's blind
        /// spot.** An immersive space's origin sits on the floor, so an
        /// absolute height excludes the floor outright — but only while the
        /// origin really is down there. Eye-relative height does not depend on
        /// that, but on its own it lets the floor through for anyone *sitting*:
        /// a seated wearer's eyes are about 1.2m up, which puts the floor 1.2m
        /// below them, in exactly the band a standing wearer's desk occupies.
        /// That is what made this pick the floor. Together they leave a desk
        /// and take a floor whether you sit or stand.
        ///
        /// Classification is a *preference*, never a filter: it reports
        /// `.undetermined` often enough that filtering on it would find nothing
        /// in an ordinary room.
        private static func bestSurface(
            among surfaces: [PlaneAnchor], device: simd_float4x4
        ) -> PlaneAnchor? {
            let eye = SIMD3(device.columns.3.x, device.columns.3.y, device.columns.3.z)
            let ahead = ViewerModel.gazeTarget(from: device)
            return
                surfaces
                .filter { surface in
                    let y = surface.originFromAnchorTransform.columns.3.y
                    let belowEyes = eye.y - y
                    return y > minimumSurfaceHeight && belowEyes > 0.2
                        && belowEyes < maximumDropBelowEyes
                }
                .min { a, b in
                    // A named table beats an unnamed surface; after that, the
                    // one closest to what the wearer is looking at wins, which
                    // is what makes "the desk in front of me" beat "the counter
                    // behind me".
                    let named = (
                        a.surfaceClassification == .table, b.surfaceClassification == .table
                    )
                    if named.0 != named.1 { return named.0 }
                    return distance(from: ahead, to: a) < distance(from: ahead, to: b)
                }
        }

        private static func distance(from point: SIMD3<Float>, to surface: PlaneAnchor) -> Float {
            let centre = surface.originFromAnchorTransform.columns.3
            return simd_length(SIMD2(centre.x - point.x, centre.z - point.z))
        }

        /// The floor is at zero, so anything at knee height or below is not a
        /// table. Deliberately low: a child's desk is lower than an adult's.
        private static let minimumSurfaceHeight: Float = 0.35

        /// Far enough below the eyes to be a surface you look *down* at, near
        /// enough that a seated wearer's floor (about 1.2m down) is excluded.
        private static let maximumDropBelowEyes: Float = 1.1

        /// How long a non-table surface is held before being accepted, in case
        /// a real table is still being mapped. Cheap against the ten seconds
        /// detection takes anyway.
        private static let settleDelay: Duration = .seconds(2)

        /// The head pose — **once world tracking is actually tracking**.
        ///
        /// `queryDeviceAnchor` answers straight away after `run`, and what it
        /// answers with at first is an *untracked* anchor whose transform is the
        /// identity. Aiming from that puts the sheet 35cm below the origin,
        /// which is under the floor, which looks exactly like nothing rendering
        /// at all — the same symptom, from a different cause, as the very first
        /// placement bug in this file. `isTracked` is what separates a pose from
        /// a placeholder.
        private static func pose(from world: WorldTrackingProvider) async -> simd_float4x4? {
            for _ in 0..<poseAttempts {
                if let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
                    anchor.isTracked,
                    anchor.originFromAnchorTransform.columns.3.y > minimumEyeHeight
                {
                    return anchor.originFromAnchorTransform
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return nil
        }

        /// The height below which a "pose" is not one.
        ///
        /// An immersive space's origin is on the floor under the wearer, so a
        /// head is about a metre and a half up. **The simulator reports the
        /// identity transform and calls it tracked**, which reads as a head on
        /// the floor and aims the sheet into the ground — so `isTracked` alone
        /// is not enough to trust a pose by. 0.8m is under a seated child's
        /// eyes and over anything that is really a placeholder; below it the
        /// placement stops guessing and takes its fixed spot instead.

        /// Three seconds' worth of 100ms tries. Long enough for tracking to
        /// start, short enough that a headset which never tracks still gets a
        /// drawing rather than a blank room.
        private static let minimumEyeHeight: Float = 0.8

        private static let poseAttempts = 30

        /// A drag's translation in the entity's parent space, which is where
        /// `position` is read. Converting to `.scene` instead would be wrong
        /// the moment the sheet hangs off a plane anchor.
        ///
        /// `keepingOnPlane` is what stops a drag lifting the sheet off the
        /// table: the sheet is level, so dropping the Y component slides the
        /// drawing along the surface instead of into the air. It is off in the
        /// floating placement, where there is no surface to stay on and height
        /// is the only way to put the sheet somewhere sensible.
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

#endif
