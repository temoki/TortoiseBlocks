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
}
