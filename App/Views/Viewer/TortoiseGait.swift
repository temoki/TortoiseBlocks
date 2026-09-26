#if os(visionOS)

    import RealityKit
    import simd

    /// Makes the tortoise on the table walk instead of slide.
    ///
    /// The model's golden body is skinned to a skeleton — a torso joint and
    /// one joint per leg, hip to sole (`Tools/tortoise-model/build_tortoise.py`)
    /// — and this poses the legs every display frame from how far the tortoise
    /// actually moved since the last one. The step cycle advances by
    /// *distance*, so the legs go as fast as the animal does and stop when it
    /// stops; turning on the spot steps too, counted as the distance the feet
    /// would travel round the turn.
    ///
    /// Diagonal pairs move together — front-left with rear-right, then the
    /// other two — the way a real tortoise walks. A leg tucks up and swings out
    /// while it comes forward, and the whole animal waddles: it rocks toward
    /// the side that is standing and bobs on each change of feet.
    ///
    /// **Every amount here is large on purpose, and was judged by eye rather
    /// than derived.** The legs are a tenth of the body long from hip to sole,
    /// so the first pass — a 20° swing at the pace that keeps a foot planted —
    /// moved a foot about 3% of the body, and on the table nobody could see
    /// the legs move at all. The numbers below are what the maintainer settled
    /// on from simulator recordings: 50°, two to three times the pace, a 10°
    /// rock. A walk this size scurries more than it plods, which is also what
    /// the drawing's tempo makes the animal do anyway.
    @MainActor
    final class TortoiseGait {
        /// The loaded model inside the carrier: rocked and bobbed as a whole.
        private let model: Entity
        /// The skinned golden body, whose joints are the legs.
        private let body: ModelEntity
        private let rest: [Transform]
        private let legs: [Leg]
        /// The torso joint's rest rotation, which the legs' swing is expressed
        /// through. The identity as the model is built, but read rather than
        /// assumed.
        private let torso: simd_quatf
        private let restLift: Float
        private let restOrientation: simd_quatf
        /// How long the tortoise is, in the units its position arrives in.
        private let length: Float

        private var phase: Float = 0
        private var amplitude: Float = 0
        private var last: (position: SIMD3<Float>, heading: Float)?

        private struct Leg {
            let joint: Int
            /// Where in the cycle this leg is: diagonal pairs share one.
            let offset: Float
            /// +1 on the left, −1 on the right, so a lifted foot swings outward
            /// on both sides.
            let side: Float
        }

        /// Nil when the model has no skeleton — an older asset, or one that
        /// failed to bind — and the tortoise then glides, as it always did.
        ///
        /// The skinned body arrives as the `ModelEntity` RealityKit makes of
        /// the model's `SkelRoot` (named "Skeleton"), not as the "Body" mesh
        /// beneath it, so it is found by having joints rather than by name.
        init?(model: Entity, length: Float) {
            guard let body = Self.skinned(in: model) else { return nil }
            let names = body.jointNames
            func joint(_ name: String) -> Int? {
                names.firstIndex { $0.split(separator: "/").last.map(String.init) == name }
            }
            guard let torsoJoint = joint("Torso"),
                let frontLeft = joint("LegFrontLeft"),
                let frontRight = joint("LegFrontRight"),
                let rearLeft = joint("LegRearLeft"),
                let rearRight = joint("LegRearRight")
            else { return nil }

            let rest = body.jointTransforms
            self.model = model
            self.body = body
            self.rest = rest
            self.torso = rest[torsoJoint].rotation
            self.legs = [
                Leg(joint: frontLeft, offset: 0, side: 1),
                Leg(joint: rearRight, offset: 0, side: -1),
                Leg(joint: frontRight, offset: .pi, side: -1),
                Leg(joint: rearLeft, offset: .pi, side: 1),
            ]
            self.restLift = model.position.z
            self.restOrientation = model.orientation
            self.length = length
        }

        /// Advances the walk to where the tortoise now stands.
        ///
        /// `position` is in the sheet's space and `heading` in radians; neither
        /// needs to be anything but consistent from one frame to the next.
        func step(position: SIMD3<Float>, heading: Float, deltaTime: Float) {
            let dt = max(deltaTime, 1e-4)
            var travelled: Float = 0
            if let last {
                let moved = simd_distance(position, last.position) / length
                var turned = abs(heading - last.heading).truncatingRemainder(dividingBy: 2 * .pi)
                turned = min(turned, 2 * .pi - turned)
                let distance = moved + turned * Self.turnRadius
                // A seek moves the tortoise in one frame by however far it
                // likes; stepping through that would spin the legs.
                if distance < Self.teleport { travelled = distance }
            }
            last = (position, heading)

            let advance = min(
                travelled / Self.stride * 2 * .pi, Self.maximumCyclesPerSecond * 2 * .pi * dt)
            phase = (phase + advance).truncatingRemainder(dividingBy: 2 * .pi)
            let moving = travelled / dt > Self.stillSpeed
            amplitude += ((moving ? 1 : 0) - amplitude) * min(1, dt / Self.settle)
            pose()
        }

        private func pose() {
            var transforms = rest
            for leg in legs {
                let p = phase + leg.offset
                let swing = Self.swing * amplitude * sin(p)
                // Only while the leg comes forward, which is the half of the
                // cycle where the swing is rising.
                let airborne = amplitude * max(0, cos(p))
                // About the model's own sideways axis (+X) for the swing and
                // its forward axis (+Y) for the lift, both about the hip, which
                // is where each leg joint sits. Written through the torso's
                // rotation so the axes stay the model's whatever the parent is.
                let turn =
                    simd_quatf(angle: swing, axis: [1, 0, 0])
                    * simd_quatf(angle: Self.lift * airborne * leg.side, axis: [0, 1, 0])
                transforms[leg.joint].rotation =
                    torso.inverse * turn * torso * rest[leg.joint].rotation
                // Tucked up while it comes forward, so the foot visibly leaves
                // the paper: shorter along the bone (the joint's own Y), a
                // little fatter across it, the way a cartoon leg squashes.
                let tuck = 1 - Self.tuck * airborne
                let across = 1 / tuck.squareRoot()
                transforms[leg.joint].scale = [across, tuck, across]
            }
            body.jointTransforms = transforms

            let bob = Self.bob * amplitude * (1 - cos(2 * phase)) / 2
            let roll = Self.rock * amplitude * sin(phase)
            // Rocking about the ground point under the shell tips one side's
            // feet into the paper, so the body rises by as much as that side
            // would sink: the low feet stay on the page and the high ones leave
            // it, which is what a waddle is.
            let clearance = Self.footReach * abs(sin(roll))
            model.position.z = restLift + (bob + clearance) * length
            model.orientation = simd_quatf(angle: roll, axis: [0, 1, 0]) * restOrientation
        }

        private static func skinned(in entity: Entity) -> ModelEntity? {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
            for child in entity.children {
                if let found = skinned(in: child) { return found }
            }
            return nil
        }

        // MARK: - The walk, in body lengths and radians

        /// How far each leg swings either side of upright.
        private static let swing: Float = 50 * .pi / 180
        /// How far a leg tips outward while it comes forward.
        private static let lift: Float = 0.3
        /// How much shorter a leg gets while it comes forward.
        private static let tuck: Float = 0.35
        /// Body lengths per step cycle — well short of the stride that keeps a
        /// foot planted (`2π × hip height × swing`, about 0.55), because at that
        /// pace the legs moved too slowly against the body to read.
        private static let stride: Float = 0.22
        /// How far the feet travel, in body lengths, per radian of turning.
        private static let turnRadius: Float = 0.3
        /// A move bigger than this in one frame is a jump, not a step.
        private static let teleport: Float = 0.6
        /// Slower than this, in body lengths a second, counts as standing.
        private static let stillSpeed: Float = 0.05
        /// The fastest the legs cycle. The drawing's tempo gives every command
        /// the same time however long its line, so on a long line the animal
        /// outruns any stride — past this the feet patter and slide rather
        /// than blur.
        private static let maximumCyclesPerSecond: Float = 5.0
        /// Seconds to come to a stop, or get going.
        private static let settle: Float = 0.15
        /// How far the body rises on each change of feet.
        private static let bob: Float = 0.025
        /// How far the body rocks toward the standing side.
        private static let rock: Float = 10 * .pi / 180
        /// How far out from the centre line the outer edge of a sole is.
        private static let footReach: Float = 0.3
    }

#endif
