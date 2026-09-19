import SwiftUI
import TortoiseBlocksKit

/// One tappable palette entry: a display name, an icon, and the block kind
/// it stamps out (each tap or drag creates a fresh `Block` with a new ID).
struct PaletteEntry: Identifiable {
    let title: LocalizedStringResource
    let systemImage: String
    let kind: BlockKind

    var id: String { title.key }
}

struct PaletteSection: Identifiable {
    let title: LocalizedStringResource
    let category: BlockCategory
    let entries: [PaletteEntry]

    var id: String { title.key }
}

enum Palette {
    static let sections: [PaletteSection] = [
        PaletteSection(
            title: "Motion", category: .movement,
            entries: [
                PaletteEntry(
                    title: "Forward", systemImage: "arrow.up",
                    kind: .forward(.literal(100))),
                PaletteEntry(
                    title: "Backward", systemImage: "arrow.down",
                    kind: .backward(.literal(100))),
                PaletteEntry(
                    title: "Turn Right", systemImage: "arrow.clockwise",
                    kind: .turnRight(.literal(90))),
                PaletteEntry(
                    title: "Turn Left", systemImage: "arrow.counterclockwise",
                    kind: .turnLeft(.literal(90))),
                PaletteEntry(
                    title: "Go Home", systemImage: "house",
                    kind: .home),
            ]),
        PaletteSection(
            title: "Pen", category: .pen,
            entries: [
                PaletteEntry(
                    title: "Pen Down", systemImage: "pencil",
                    kind: .penDown),
                PaletteEntry(
                    title: "Pen Up", systemImage: "pencil.slash",
                    kind: .penUp),
                PaletteEntry(
                    title: "Pen Color", systemImage: "paintpalette",
                    kind: .penColor(.literal(.blue))),
                PaletteEntry(
                    title: "Pen Width", systemImage: "lineweight",
                    kind: .penWidth(.literal(2))),
            ]),
        PaletteSection(
            title: "Fill", category: .fill,
            entries: [
                PaletteEntry(
                    title: "Fill Color", systemImage: "drop.fill",
                    kind: .fillColor(.literal(.yellow))),
                PaletteEntry(
                    title: "Start Fill", systemImage: "paintbrush.fill",
                    kind: .beginFill),
                PaletteEntry(
                    title: "End Fill", systemImage: "paintbrush",
                    kind: .endFill),
            ]),
        PaletteSection(
            title: "Control", category: .control,
            entries: [
                PaletteEntry(
                    title: "Repeat", systemImage: "repeat",
                    kind: .repeatBlock(count: .literal(4), body: [])),
                PaletteEntry(
                    title: "If", systemImage: "questionmark.diamond",
                    // "The dice shows 4 or more" — playable without setting
                    // up a variable first.
                    kind: .ifBlock(
                        condition: Condition(
                            lhs: .random(min: 1, max: 6), comparison: .greaterOrEqual,
                            rhs: .literal(4)),
                        body: [], elseBody: nil)),
            ]),
        PaletteSection(
            title: "Variables", category: .variables,
            entries: [
                PaletteEntry(
                    title: "Put in Box", systemImage: "tray.and.arrow.down",
                    kind: .setVariable(name: variableNamePresets[0], value: .literal(10))),
                PaletteEntry(
                    title: "Add to Box", systemImage: "plus.square",
                    kind: .addVariable(name: variableNamePresets[0], value: .literal(10))),
                PaletteEntry(
                    title: "Subtract from Box", systemImage: "minus.square",
                    kind: .subtractVariable(name: variableNamePresets[0], value: .literal(10))),
                PaletteEntry(
                    title: "Multiply Box", systemImage: "multiply.square",
                    kind: .multiplyVariable(name: variableNamePresets[0], value: .literal(2))),
                PaletteEntry(
                    title: "Divide Box", systemImage: "divide.square",
                    kind: .divideVariable(name: variableNamePresets[0], value: .literal(2))),
            ]),
        // Two entries, not one per defined name (#14). A palette section that
        // grew an entry per definition is the other way to do this, and it is
        // what Scratch does — but the name here is a chip on the block, the
        // way a box's is, so the generic "call" block already covers every
        // name and the palette stays a fixed list. Both blocks start on the
        // same preset name, so つくる → よぶ works with no editing at all.
        PaletteSection(
            title: "My Blocks", category: .functions,
            entries: [
                PaletteEntry(
                    title: "Make Block", systemImage: "puzzlepiece.extension",
                    kind: .defineBlock(name: functionNamePresets[0], body: [])),
                PaletteEntry(
                    title: "Call Block", systemImage: "puzzlepiece.extension.fill",
                    kind: .callBlock(name: functionNamePresets[0])),
            ]),
    ]
}

extension BlockCategory {
    /// Category tint: movement=sky, pen=wisteria, fill=mint, control=apricot,
    /// variables=blush, functions=coral — six hues a child can still name
    /// apart, drawn from the app's own artwork rather than from the system
    /// palette (#41). The app icon's gradient is sky to mint and the tortoise
    /// sprite is lavender, apricot and blush; against that, saturated system
    /// colors were the one thing on screen that didn't belong.
    ///
    /// Pastels are also what makes the text legible. The blocks used to be
    /// saturated fills under white text, which measured 1.9–3.3:1 — under AA
    /// for every category, in both appearances. Keeping white would have meant
    /// darkening the fills until orange came out brown (`#A76821`); this way
    /// nothing has to be muddied and ``ink`` clears 9.8:1 everywhere.
    ///
    /// The same color in light and dark. A block's fill is its identity, not a
    /// response to its surroundings — and since these are light in both, the
    /// text must not follow the appearance either (see ``ink``).
    var color: Color {
        switch self {
        case .movement: Color(.sRGB, red: 0.557, green: 0.824, blue: 0.961)  // #8ED2F5
        case .pen: Color(.sRGB, red: 0.839, green: 0.737, blue: 0.937)  // #D6BCEF
        case .fill: Color(.sRGB, red: 0.647, green: 0.906, blue: 0.741)  // #A5E7BD
        case .control: Color(.sRGB, red: 0.973, green: 0.808, blue: 0.584)  // #F8CE95
        case .variables: Color(.sRGB, red: 0.969, green: 0.698, blue: 0.788)  // #F7B2C9
        // The sixth hue had two places to go: the gap at yellow (~55°) and the
        // one at teal (~180°), with red squeezed between apricot's 33° and
        // blush's 340°. Judged in a prototype against the other five, yellow
        // sat too close to apricot — and a definition wrapping an if puts those
        // two side by side by construction — while teal read as a shade of the
        // sky blocks. Coral is the narrow gap, and it holds because the
        // *saturation* differs from blush as well as the hue.
        //
        // Lifted a touch above the coral that was prototyped (#F5A79B, 8.8:1)
        // so ink clears the same ~9.8:1 as the other five: a fill's lightness
        // is what carries the label, and one darker block would read as the
        // odd one out long before anyone measured it.
        case .functions: Color(.sRGB, red: 0.973, green: 0.706, blue: 0.659)  // #F8B4A8
        }
    }

    /// What a container's arms turn while a drag is over its header (#78):
    /// the same hue, turned up.
    ///
    /// The block answers with its own colour rather than wearing a ring. A
    /// ring reads as something arriving from outside; the header, spine and
    /// foot changing together reads as the container itself opening up, and it
    /// keeps the C one unbroken run of colour the way the resting state is.
    ///
    /// **Saturation only — the brightness does not move.** Mixing a pastel
    /// toward a dark saturated version of itself was tried first and came out
    /// muddy, which is what interpolating between a light, washed colour and a
    /// dark, vivid one always gives you: the middle is dull by construction.
    /// Holding the brightness and pushing saturation to 2.4× keeps the colour
    /// clean and makes it *more* itself rather than a step toward something
    /// else.
    ///
    /// The ink still has to be readable, since the header carries it: measured
    /// 6.06:1 sky, 5.41 wisteria, 10.56 mint, 7.44 apricot, 5.26 blush, 5.14
    /// coral — all well over AA. Mint's luminance barely moves (1.13:1 against
    /// its resting fill) because green carries most of the luminance in the
    /// first place; the *hue* change is plain to see, and a contrast ratio is
    /// the wrong instrument for that one.
    ///
    /// Not transparent, tempting as that was: the C is drawn additively so
    /// nothing has to know the pane's background (#21), and letting the pane
    /// through would hand that back.
    var dropFill: Color {
        switch self {
        case .movement: Color(.sRGB, red: 0.000, green: 0.635, blue: 0.961)  // #00A2F5
        case .pen: Color(.sRGB, red: 0.702, green: 0.457, blue: 0.937)  // #B375EF
        case .fill: Color(.sRGB, red: 0.284, green: 0.906, blue: 0.510)  // #49E782
        case .control: Color(.sRGB, red: 0.973, green: 0.577, blue: 0.039)  // #F8930A
        case .variables: Color(.sRGB, red: 0.969, green: 0.319, blue: 0.535)  // #F75188
        case .functions: Color(.sRGB, red: 0.973, green: 0.332, blue: 0.219)  // #F85538
        }
    }

    /// What is written on a block: a fixed near-black, on purpose.
    ///
    /// `Color.primary` would invert in dark mode and land white text back on a
    /// pastel — 1.4:1, the very failure this replaced. The fill doesn't follow
    /// the appearance, so neither can its label.
    static let ink = Color(.sRGB, red: 0.110, green: 0.110, blue: 0.118)  // #1C1C1E
}

/// The tap-to-add palette — only ever the `NavigationSplitView` sidebar
/// (#23), and untitled like the other two columns: the section headers name
/// its contents, and the bar above it belongs to the document (see
/// `RootView`).
struct PaletteView: View {
    let workspace: WorkspaceEditor
    /// Called after a tap puts a block in the program. nil in the iPad's
    /// column, where the palette is never in the way of what it just did;
    /// `CompactPaletteSheet` uses it to get out of the way (#113).
    var onInsert: (() -> Void)?

    @ScaledMetric private var sectionGap: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                ForEach(Palette.sections) { section in
                    PaletteSectionView(
                        section: section, workspace: workspace, onInsert: onInsert)
                }
            }
            .padding()
        }
    }
}

struct PaletteSectionView: View {
    let section: PaletteSection
    let workspace: WorkspaceEditor
    var onInsert: (() -> Void)?

    @ScaledMetric private var entryGap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: entryGap) {
            Text(section.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Lets VoiceOver's heading rotor jump section to section
                // instead of swiping through every block to reach the next
                // one — the palette is the longest list in the app.
                .accessibilityAddTraits(.isHeader)
            ForEach(section.entries) { entry in
                PaletteEntryButton(
                    entry: entry, category: section.category, workspace: workspace,
                    onInsert: onInsert)
            }
        }
    }
}

/// The measurements a palette entry's block look is made of, named because
/// two things wear it: the button style below, and the drag preview (#75),
/// which has to be the same block or picking one up changes what you were
/// looking at. They differ in exactly one way — an entry fills the column, a
/// preview is the size of the block — and that difference is a frame, which
/// is why this is a handful of constants rather than one modifier.
private enum PaletteBlock {
    static let verticalPadding: CGFloat = 9
    static let horizontalPadding: CGFloat = 11
    static let shape = RoundedRectangle(cornerRadius: 8)
}

/// A palette entry's block look: the category fill, the shared ink, and a
/// press state of its own since the plain style has none.
private struct PaletteBlockButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(BlockCategory.ink)
            .padding(.vertical, PaletteBlock.verticalPadding)
            .padding(.horizontal, PaletteBlock.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: PaletteBlock.shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            // Here rather than on the `Button`, because the button is a drag
            // source and the pair crashes visionOS — see `pointerHover`. It
            // also reads better: the highlight follows the shape the style
            // draws instead of the label's own bounds.
            .pointerHover()
    }
}

struct PaletteEntryButton: View {
    let entry: PaletteEntry
    let category: BlockCategory
    let workspace: WorkspaceEditor
    var onInsert: (() -> Void)?

    /// The entry's width, for the drag preview on iPadOS — see `BlockRowView`
    /// (#95).
    @State private var entryWidth: CGFloat = 0

    var body: some View {
        Button {
            workspace.add(entry.kind)
            onInsert?()
        } label: {
            Label {
                Text(entry.title)
            } icon: {
                Image(systemName: entry.systemImage)
            }
            .labelStyle(BlockLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The same chrome a placed block wears, rather than
        // `.borderedProminent` + `.tint` (#41): that style picks its own label
        // color — white — which is the one thing a pastel fill can't carry. A
        // palette entry and the row it becomes should look alike anyway.
        .buttonStyle(PaletteBlockButtonStyle(color: category.color))
        // The hover is inside that style, not here. On visionOS a hover effect
        // and `draggable` on the same view segfault — see `pointerHover`.
        //
        // Evaluated per drag, so every drag stamps a fresh Block (new ID).
        //
        // With a preview of its own (#75). The default is a snapshot of the
        // view, which squares off the corners the block was drawn with and
        // lifts a picture of a control rather than a block. This one is the
        // same label in the same fill, at the size of the block instead of the
        // width of the column — what you are carrying, not where it came from.
        //
        // Deliberately built from plain views rather than by reusing
        // `PaletteBlockButtonStyle`: that style carries `pointerHover()`, and
        // a hover effect anywhere under a `draggable` is the pairing that
        // segfaults visionOS.
        .draggable(workspace.dragging(Block(kind: entry.kind))) {
            Label {
                Text(entry.title)
            } icon: {
                Image(systemName: entry.systemImage)
            }
            .labelStyle(BlockLabelStyle())
            .foregroundStyle(BlockCategory.ink)
            .padding(.vertical, PaletteBlock.verticalPadding)
            .padding(.horizontal, PaletteBlock.horizontalPadding)
            .frame(
                minWidth: entryWidth > 0 ? entryWidth : nil,
                maxWidth: .infinity, alignment: .leading
            )
            .background(category.color, in: PaletteBlock.shape)
            // The corners are the block's, not a hole to fill in — see
            // `BlockChrome` (#90).
            .contentShape(.dragPreview, PaletteBlock.shape)
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            entryWidth = $0
        }
        .accessibilityHint("Tap to add to the end of the program. Drag to place anywhere.")
    }
}
