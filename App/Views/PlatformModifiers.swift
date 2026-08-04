import SwiftUI

// Small cross-cutting modifiers that hide their `#if os(...)` inside a
// modifier (the SwiftUI-way rule), so call sites stay platform-agnostic.
extension View {
    /// The number pad for numeric entry on iOS (#24); a no-op elsewhere.
    /// `.decimalPad` gives the digits and decimal point kids need; the
    /// number blocks don't take negative literals, so its lack of a minus
    /// key is intentional.
    func numericKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.decimalPad)
        #else
            self
        #endif
    }

    /// The iPad (pointer) hover highlight (#24); a no-op on macOS, which has
    /// its own cursor affordances.
    func pointerHover() -> some View {
        #if os(iOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }

    /// Holds an icon-only control to the 44pt finger minimum on iPadOS.
    /// A borderless SF Symbol button is only as tappable as the glyph is big —
    /// around 24pt at body size — so the ✕ on a block row is a small target on
    /// a touch screen even though the row around it is not.
    ///
    /// Only the *hit* area grows, and only where fingers are: the glyph is
    /// unchanged, and macOS keeps its own (smaller, pointer-sized) metrics
    /// rather than growing controls a mouse never needed. Rows are already
    /// taller than 44pt with their height floor and padding, and every place
    /// this is used sits after a `Spacer`, so the extra width takes slack
    /// instead of pushing the label.
    func touchTarget() -> some View {
        #if os(iOS)
            frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        #else
            self
        #endif
    }
}
