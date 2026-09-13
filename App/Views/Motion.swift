import SwiftUI

/// What motion in this app looks like, and the one place Reduce Motion is
/// honoured for the declarative half of it (#70, #71, #72).
///
/// The app had five animations before this — all of them border fades — and
/// no reading of `accessibilityReduceMotion` at all. Everything added since
/// comes through here, so "does this respect Reduce Motion?" has one answer
/// instead of one per call site. The rule and its two shapes are written up in
/// `App/Views/CLAUDE.md`.
enum Motion {
    /// A tree edit: add, delete, reorder, drop, undo, redo (#70).
    ///
    /// Quick, with a little bounce — these are blocks being stacked, and the
    /// audience is children. 0.3s rather than `.snappy`'s own 0.5 because an
    /// edit is a direct manipulation: the row should be where you put it by
    /// the time you look at it. Judge a change to this in the running app on a
    /// *nested* program, where a single edit moves rows at three depths.
    static let blockEdit = Animation.snappy(duration: 0.3)

    /// One surface replacing another: the empty workspace giving way to a
    /// program, the canvas giving way to the code pane (#72).
    ///
    /// No bounce. A spring says something was moved by hand; these two are
    /// content being swapped underneath a control that stays put, and the
    /// swap should read as the *same pane* showing something else.
    static let paneSwap = Animation.easeInOut(duration: 0.25)

    /// A control changing what it means: the transport's centre button
    /// swapping ▶︎ for ⏸ and its fill between the accent and grey (#73).
    ///
    /// No bounce, and short. A spring would overshoot a colour interpolation,
    /// and the button has to be pressable again immediately.
    static let controlState = Animation.easeInOut(duration: 0.2)

    /// The running block, lifting and settling back (#78). Short, because the
    /// playhead moves ten times a second at ×1 and a longer one would still be
    /// arriving when the next block takes over.
    static let highlight = Animation.easeOut(duration: 0.15)

    /// A drop target opening under a dragged block (#77). Faster than an
    /// edit, because it has to keep up with a finger rather than confirm
    /// something that already happened — and it runs while the layout is
    /// moving, which is the one place a long animation reads as lag.
    static let dropGap = Animation.snappy(duration: 0.15)

    /// Bringing a row into view — the playback follow, and the block the
    /// palette just made (#71). Applied imperatively around `scrollTo`, so
    /// this is the one constant `motion(_:value:)` doesn't carry.
    static let scrollFollow = Animation.easeInOut(duration: 0.2)
}

/// A one-shot SF Symbol effect that Reduce Motion switches off (#76).
///
/// The trigger is an `Int` — a counter of the thing that happened — because
/// suppressing the effect means holding that number still, and only a type we
/// know can be pinned to a constant. Declarative motion, so the check lives in
/// a modifier like the one below rather than in a view body.
private struct ReducibleSymbolMotion<Effect: DiscreteSymbolEffect & SymbolEffect>: ViewModifier {
    let effect: Effect
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.symbolEffect(effect, value: reduceMotion ? 0 : trigger)
    }
}

extension View {
    func symbolMotion<Effect: DiscreteSymbolEffect & SymbolEffect>(
        _ effect: Effect, trigger: Int
    ) -> some View {
        modifier(ReducibleSymbolMotion(effect: effect, trigger: trigger))
    }
}

/// `.animation(_:value:)` that Reduce Motion switches off.
///
/// A modifier so the check has somewhere to live that isn't the view body —
/// the same reason `pointerHover()` exists for `#if os(...)`. Declarative
/// motion is decoration over a change that has already happened, so switching
/// it off is simply passing no animation and nothing downstream has to know.
///
/// Imperative motion (`withAnimation` around `scrollTo`) has no modifier to
/// hide inside and reads `accessibilityReduceMotion` in the view instead.
/// That is the only reason to read it in a body; there is no third shape.
private struct ReducibleMotion<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func motion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(ReducibleMotion(animation: animation, value: value))
    }
}
