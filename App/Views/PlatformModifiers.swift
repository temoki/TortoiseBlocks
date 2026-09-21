import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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

    /// The hover highlight (#24): the iPad's pointer, and on visionOS the gaze,
    /// which is the only thing there that says what you are about to press.
    /// A no-op on macOS, which has its own cursor affordances.
    ///
    /// **Never put this on a view that is also `draggable`.** That combination
    /// segfaults on visionOS — a `swift_release` inside SwiftUI's own update of
    /// the view's body, before a window is ever shown, with `.automatic` as
    /// well as `.highlight`. It cost a while to place, because the crash blames
    /// the body rather than the modifier and the effect looked like the
    /// culprit; the effect is fine and the *pairing* is not. So a palette
    /// entry, which is a drag source, wears its hover inside
    /// `PaletteBlockButtonStyle` — on the shaped body the style draws, one
    /// level below the `Button` that `draggable` is attached to — and that is
    /// why the palette applies this in its style while everything else applies
    /// it at the call site.
    ///
    /// visionOS needs it stated at all because it does *not* give a button with
    /// a custom `ButtonStyle` the system hover treatment; without this, a
    /// palette block is the one thing on screen that never lights up when
    /// looked at.
    func pointerHover() -> some View {
        #if !os(macOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }

    /// A sheet's own bar (#113): no back chevron, and a title that doesn't eat
    /// a detent.
    ///
    /// The chevron is the document scene's, not a stack's — a `DocumentGroup`
    /// hands its chrome to every navigation bar under it, sheets included, and
    /// in a sheet it points at nothing. (`toolbar(removing: .title)`, which is
    /// what `CanvasPane` uses against the *title* half of the same chrome,
    /// leaves the chevron behind.)
    ///
    /// Both modifiers are unavailable on macOS, which is never compact and so
    /// never presents these sheets.
    func sheetNavigationBar() -> some View {
        #if !os(macOS)
            navigationBarBackButtonHidden()
                .navigationBarTitleDisplayMode(.inline)
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

/// A way back to the document browser, in the sidebar's own bar (#118).
///
/// **The system's own way back is not reliably where a person looks.** Opened
/// from the app's document browser on an iPad in landscape, the document comes
/// up with no name and no back button at the top left — the only one is a bare
/// chevron in the *canvas* column, two thirds of the way across the screen.
/// It works (measured: it returns to the browser), and nothing will make a
/// child find it. This is a known SwiftUI bug, reproducible with Xcode's own
/// Document App template and filed as FB20062294; `.toolbarRole` in all three
/// of its values changes nothing, and nor does asking for the bar outright.
/// So the app carries its own.
///
/// **A `ViewModifier` and not a view inside a `toolbar` block**, because that
/// is what decides whether it works: `dismiss` read inside the toolbar item's
/// own view resolves against the toolbar's context and the button is inert —
/// it highlights on press and nothing happens. It has to come from the
/// environment of the content the toolbar is attached to.
private struct DocumentBrowserToolbar: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Drawings", systemImage: "folder") { dismiss() }
                    // A button in a `ToolbarItem` arrives with an empty
                    // accessibility identifier — SwiftUI passes an
                    // `Image(systemName:)` through everywhere else, but not
                    // here (#119 hit the same thing).
                    .accessibilityIdentifier("folder")
            }
        }
    }
}

extension View {
    /// See `DocumentBrowserToolbar`. A no-op on macOS, which has a window per
    /// document and File ▸ Open, and where `dismiss` would close the window.
    func documentBrowserToolbar() -> some View {
        #if os(macOS)
            self
        #else
            modifier(DocumentBrowserToolbar())
        #endif
    }
}

extension ToolbarContent {
    /// Turns off the glass capsule a `ToolbarItemGroup` paints behind its
    /// items (#119), for a group holding a control that draws its own shape.
    ///
    /// `sharedBackgroundVisibility` is `@available(visionOS, unavailable)`,
    /// like `ToolbarSpacer` before it — visionOS lays its toolbar out as an
    /// ornament and does the grouping itself, so there is no shared background
    /// to turn off. Naming the platform that lacks it keeps the `#if` out of
    /// `CanvasToolbar`, which exists for that reason in the first place.
    func withoutSharedBackground() -> some ToolbarContent {
        #if os(visionOS)
            self
        #else
            sharedBackgroundVisibility(.hidden)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The bar along the bottom of a compact screen (#113), where a thumb is.
    ///
    /// `.bottomBar` is `@available(macOS, unavailable)` — a Mac window has no
    /// such bar. macOS is also never compact, so `CompactRootView` never
    /// renders there and the fallback is only what keeps the file compiling;
    /// naming the platforms that *have* a bottom bar, rather than the one that
    /// does not, is what stops a new platform from silently taking it.
    static var compactActions: ToolbarItemPlacement {
        #if os(macOS)
            .automatic
        #else
            .bottomBar
        #endif
    }
}

/// How much of the screen the palette sheet takes (#113).
///
/// A type of ours rather than `PresentationDetent`s held in the view, because
/// that type does not exist on macOS *at all* — it is not merely a modifier
/// that no-ops there — so a `@State` of that type would not compile in a file
/// the Mac builds. See `paletteSheetSize(_:peek:)`.
enum PaletteSheetSize {
    /// The bar and a couple of blocks: the size you drag *from*, with the
    /// program behind it in plain view.
    case peek
    case half
    case full
}

extension View {
    /// The palette sheet's three sizes, and the thing that makes the small
    /// ones worth having: input reaching the workspace behind it.
    ///
    /// **`presentationBackgroundInteraction` is load-bearing.** Everything
    /// behind a sheet is inert by default, so without it a block dragged out
    /// of the palette has nothing to land on — the drop is refused by the
    /// presentation, not by drag and drop, and it looks identical either way.
    /// Enabled up through `.medium` only: at full height there is nothing
    /// showing to drop onto.
    ///
    /// A selection is passed rather than letting the sheet pick, because a
    /// detent set opens at its *smallest* — which here is the peek, two blocks
    /// of a palette of twenty.
    func paletteSheetSize(_ selection: Binding<PaletteSheetSize>, peek: CGFloat) -> some View {
        #if !os(macOS)
            presentationDetents(
                [.height(peek), .medium, .large],
                selection: Binding(
                    get: {
                        switch selection.wrappedValue {
                        case .peek: .height(peek)
                        case .half: .medium
                        case .full: .large
                        }
                    },
                    set: { detent in
                        selection.wrappedValue =
                            switch detent {
                            case .height(peek): .peek
                            case .large: .full
                            default: .half
                            }
                    })
            )
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            // **An opaque sheet, over a page of coloured blocks.** At less
            // than full height the sheet is glass, and what shows through a
            // palette is the program behind it — a second, ghostly one, in
            // the same colours as the blocks being read. `.background` is not
            // enough: `BackgroundStyle` resolves to whatever the context's
            // background is, which inside a sheet is that same glass.
            // `systemBackground` is a colour, and is opaque.
            .presentationBackground(Color(.systemBackground))
        #else
            self
        #endif
    }
}
