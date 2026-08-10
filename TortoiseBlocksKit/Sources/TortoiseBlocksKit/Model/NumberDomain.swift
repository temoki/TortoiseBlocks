/// The legal range of a numeric block argument, by the slot it sits in.
///
/// The limits are part of the block language, not an implementation detail,
/// and three layers share this one definition:
///
/// - **Input (App)** refuses out-of-range values: the stepper stops at the
///   bound and a typed number outside it reverts to the last good value, so an
///   out-of-range literal never enters the tree in the first place.
/// - **Execution (`BlockExpander`)** *saturates*: a value that leaves the range
///   at run time is pinned to the nearest bound rather than raising an error —
///   the same "never an error for a kid" line as the divide-by-zero no-op.
///   Input validation alone can't cover this: a box drifts past the bound
///   through `+=` / `*=`, and dice bounds, older documents, and hand-edited
///   JSON never pass through the editor at all.
/// - **Storage (`Codable`)** passes everything through untouched. The wire
///   format is frozen, so a document is never rejected or silently rewritten
///   over a value — it loads as written and saturates when it runs.
///
/// Unbounded input was reachable as three crashes and a freeze (#27):
/// `Int(Double)` traps outside `Int`'s range and on infinity/NaN,
/// `Double.random(in:)` traps on a range too wide to represent, and an empty
/// repeat body charges no step against the expansion cap, so a huge count spun
/// forever. Clamping *bounds* (not just results) and converting counts through
/// ``iterationCount(_:)`` is what closes all four.
public enum NumberDomain: Sendable, Hashable, CaseIterable {
    /// まえへ / うしろへ — points.
    case distance
    /// みぎへ / ひだりへ — degrees.
    case angle
    /// ペンのふとさ.
    case penWidth
    /// くりかえし回数.
    case repeatCount
    /// Box values, condition operands, and dice bounds.
    case general

    public var range: ClosedRange<Double> {
        switch self {
        // 400×400 is the logical canvas, so ±1000 already draws well past its
        // edge; autoFit brings it back into view.
        case .distance: -1000...1000
        // One full turn either way. Any larger rotation lands on a heading
        // already reachable inside that turn.
        case .angle: -360...360
        // A quarter of the canvas — wider is indistinguishable from a fill.
        case .penWidth: 0...100
        // A body of ten commands already hits `BlockExpander.defaultLimit` at
        // this count, so the cap is the existing step limit in another unit —
        // and an *empty* body can no longer spin past it.
        case .repeatCount: 0...1000
        case .general: -1000...1000
        }
    }

    /// Pins `value` into ``range``, always returning a finite number:
    /// infinities land on the bounds, and NaN — which has no nearest bound —
    /// becomes 0, a value every domain contains.
    public func clamp(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }

    /// `value` as a repeat count. Safe where a bare `Int(_ :Double)` was not:
    /// ``clamp(_:)`` has already produced a finite value inside `0...1000`.
    public static func iterationCount(_ value: Double) -> Int {
        Int(repeatCount.clamp(value).rounded())
    }
}

extension BlockKind {
    /// The domain of this kind's number slot, or `nil` for kinds that have
    /// none. Condition operands aren't covered here — an `ifBlock` holds a
    /// ``Condition``, whose two slots are always ``NumberDomain/general``.
    ///
    /// Exhaustive on purpose: adding a block kind won't compile until its
    /// slot has a domain.
    public var numberDomain: NumberDomain? {
        switch self {
        case .forward, .backward: .distance
        case .turnRight, .turnLeft: .angle
        case .penWidth: .penWidth
        case .repeatBlock: .repeatCount
        case .setVariable, .addVariable, .subtractVariable, .multiplyVariable,
            .divideVariable:
            .general
        case .home, .penUp, .penDown, .penColor, .fillColor, .beginFill, .endFill,
            .ifBlock, .defineBlock, .callBlock:
            nil
        }
    }
}
