import SwiftUI

/// Block rows are read as a column — down the palette, and down each run of
/// siblings in the workspace — so the icons want a shared centre line and the
/// titles a shared left edge. `Label`'s own layout gives neither: SF Symbols
/// vary in width (15pt for `drop.fill` against 24pt for `house` at iOS body
/// size), and each title simply starts where its own icon ended, leaving the
/// text ragged by up to 9pt.
///
/// Applied to the palette entries (`PaletteEntryButton`) and to every
/// workspace block row (`SimpleBlockLabel`, the container headers, the else
/// divider). Not to `PaletteEntryChip`, which stacks its icon *above* a
/// centered title and so has nothing to align.
struct BlockLabelStyle: LabelStyle {
    /// The widest glyph used by any block row or palette entry. A hidden copy
    /// sits behind every icon to size the icon slot, which is what keeps the
    /// slot correct at the macOS body size (13pt), the iOS one (17pt), and
    /// every Dynamic Type step above them without a hard-coded width tracking
    /// all three. `house` measures widest or joint-widest at all of them.
    ///
    /// Re-check this when adding a block kind: an icon wider than the slot
    /// isn't clipped, it pushes its own title right — the exact ragged edge
    /// this style exists to remove.
    static let widestSystemImage = "house"

    func makeBody(configuration: Configuration) -> some View {
        BlockLabel(configuration: configuration)
    }
}

/// The style's body lives in a `View` so it can hold `@ScaledMetric`: a
/// `LabelStyle` is not a dynamic-property context, so a metric declared there
/// would never track Dynamic Type.
private struct BlockLabel: View {
    let configuration: LabelStyleConfiguration

    @ScaledMetric private var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ZStack {
                Image(systemName: BlockLabelStyle.widestSystemImage)
                    .hidden()
                configuration.icon
            }
            configuration.title
        }
    }
}
