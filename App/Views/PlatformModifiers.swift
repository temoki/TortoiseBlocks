import SwiftUI

// Small cross-cutting modifiers that hide their `#if os(...)` inside a
// modifier (the SwiftUI-way rule), so call sites stay platform-agnostic.
//
// They are written `#if !os(macOS)` rather than naming iOS wherever the
// behaviour is simply "the touch platforms": these are UIKit-backed and exist
// on visionOS as well as iPadOS (#11), and spelling the condition as "not the
// Mac" is what keeps a new platform from silently taking the no-op branch the
// way visionOS did — an `#if os(iOS)` compiles clean everywhere and just stops
// applying. `pointerHover` is the exception, and says why.
extension View {
    /// The number pad for numeric entry (#24); a no-op on macOS, which has a
    /// hardware keyboard. `.decimalPad` gives the digits and decimal point kids
    /// need; the number blocks don't take negative literals, so its lack of a
    /// minus key is intentional.
    func numericKeyboard() -> some View {
        #if !os(macOS)
            keyboardType(.decimalPad)
        #else
            self
        #endif
    }

    /// The iPad (pointer) hover highlight (#24); a no-op on macOS, which has
    /// its own cursor affordances.
    ///
    /// Deliberately *not* extended to visionOS, where gaze feedback would seem
    /// to be exactly what this is for: `hoverEffect` on a palette entry crashes
    /// the app there. Launching straight into the workspace segfaults in
    /// `PaletteEntryButton.body` — a `swift_release` inside SwiftUI's own
    /// update, not our code — before a window is ever shown, and it does so
    /// with `.automatic` as well as `.highlight`, so it is the modifier and not
    /// the effect. (visionOS 26.5 / 27.0 simulators, Xcode 26.6.) Buttons get
    /// the system's own hover treatment there in any case; this is only the
    /// extra highlight iPadOS needs, so the platform loses nothing visible.
    func pointerHover() -> some View {
        #if os(iOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }

    /// Holds an icon-only control to the 44pt finger minimum on iPadOS (and to
    /// the same floor on visionOS, where the target is a gaze rather than a
    /// finger — 44 is the iPad number, not a measured visionOS one).
    /// A borderless SF Symbol button is only as tappable as the glyph is big —
    /// around 24pt at body size — so the ⋯ on a block row is a small target on
    /// a touch screen even though the row around it is not.
    ///
    /// On a `Menu`, apply this to the *label* rather than to the menu: a menu
    /// hit-tests what it was handed to draw, so wrapped around the outside this
    /// grows the layout and leaves the tappable area the size of the glyph. The
    /// symptom is a control that looks right and misses half the taps, and it
    /// only showed up when the row's ✕ became a ⋯ — a filled circle is a large
    /// shape by itself, three dots on a thin band are not.
    ///
    /// Only the *hit* area grows, and only where fingers are: the glyph is
    /// unchanged, and macOS keeps its own (smaller, pointer-sized) metrics
    /// rather than growing controls a mouse never needed. Rows are already
    /// taller than 44pt with their height floor and padding, and every place
    /// this is used sits after a `Spacer`, so the extra width takes slack
    /// instead of pushing the label.
    func touchTarget() -> some View {
        #if !os(macOS)
            frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        #else
            self
        #endif
    }
}

extension Scene {
    /// The size a Mac window opens at. Nothing on iPadOS, where the system
    /// decides.
    ///
    /// 1280×800pt is a working default for three panes, and doubles as the
    /// App Store's macOS screenshot size: at a Retina backing scale of 2 a
    /// window this size captures as exactly 2560×1600px, so a screenshot of
    /// an untouched window needs no crop and no resampling.
    ///
    /// `defaultSize` is a default in the strict sense — macOS restores a
    /// window's saved frame ahead of it, so a repeatable capture has to clear
    /// that saved state first.
    func defaultWindowSize() -> some Scene {
        #if os(macOS)
            defaultSize(width: 1280, height: 800)
        #else
            self
        #endif
    }
}
