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
    ]
}

extension BlockCategory {
    /// Category tint (§7): movement=blue, pen=purple, fill=green,
    /// control=orange, variables=pink (the one hue kids won't confuse with
    /// any of the other four).
    var color: Color {
        switch self {
        case .movement: .blue
        case .pen: .purple
        case .fill: .green
        case .control: .orange
        case .variables: .pink
        }
    }
}

/// The tap-to-add palette (vertical, for regular width layouts) — only ever
/// the `NavigationSplitView` sidebar (§23), so its title is a plain inline
/// header rather than a parameter like `WorkspaceView`'s.
struct PaletteView: View {
    let workspace: WorkspaceEditor

    var body: some View {
        VStack(spacing: 0) {
            Text("Blocks")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Palette.sections) { section in
                        PaletteSectionView(section: section, workspace: workspace)
                    }
                }
                .padding()
            }
            .paletteDropDeletion(workspace: workspace)
        }
    }
}

struct PaletteSectionView: View {
    let section: PaletteSection
    let workspace: WorkspaceEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(section.entries) { entry in
                PaletteEntryButton(entry: entry, category: section.category, workspace: workspace)
            }
        }
    }
}

struct PaletteEntryButton: View {
    let entry: PaletteEntry
    let category: BlockCategory
    let workspace: WorkspaceEditor

    var body: some View {
        Button {
            workspace.add(entry.kind)
        } label: {
            Label {
                Text(entry.title)
            } icon: {
                Image(systemName: entry.systemImage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(category.color)
        .pointerHover()
        // Evaluated per drag, so every drag stamps a fresh Block (new ID).
        .draggable(Block(kind: entry.kind))
        .accessibilityHint("Tap to add to the end of the program. Drag to place anywhere.")
    }
}

/// Compact-width palette (iPhone / narrow split): a row of category tabs
/// over the selected category's entries (§22). Grouping by category cuts the
/// old flat 16-entry scroll to at most five entries per tab, so any block is
/// two actions away — pick a tab, tap the block.
struct PaletteStrip: View {
    let workspace: WorkspaceEditor

    // Non-persisted UI state; starts on Motion, the first category.
    @State private var selectedCategory: BlockCategory = .movement

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Palette.sections) { section in
                        CategoryTab(
                            title: section.title,
                            color: section.category.color,
                            isSelected: selectedCategory == section.category
                        ) {
                            selectedCategory = section.category
                        }
                    }
                }
                .padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(selectedSection.entries) { entry in
                        PaletteEntryChip(
                            entry: entry, category: selectedCategory, workspace: workspace)
                    }
                }
                .padding(.horizontal)
            }
        }
        // Applied to the whole strip, tab row included, so a workspace block
        // dropped anywhere here is deleted (§22).
        .paletteDropDeletion(workspace: workspace)
    }

    private var selectedSection: PaletteSection {
        Palette.sections.first { $0.category == selectedCategory } ?? Palette.sections[0]
    }
}

/// One category tab: a capsule tinted with the category color, filled when
/// selected. A real `Button` with the selected trait, so VoiceOver announces
/// the selection (§22).
struct CategoryTab: View {
    let title: LocalizedStringResource
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : color)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(
                    isSelected ? color : color.opacity(0.15),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .pointerHover()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A compact palette entry for the strip: icon over label on a solid
/// category-color block, matching the workspace's block look (§21). Fixed
/// size (Dynamic-Type-scaled) keeps the row tidy regardless of label length.
struct PaletteEntryChip: View {
    let entry: PaletteEntry
    let category: BlockCategory
    let workspace: WorkspaceEditor

    @ScaledMetric private var width: CGFloat = 78
    @ScaledMetric private var height: CGFloat = 66

    var body: some View {
        Button {
            workspace.add(entry.kind)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: entry.systemImage)
                    .font(.title3)
                    // Decorative — VoiceOver reads the block name below, not
                    // the SF Symbol's own description (matching the regular
                    // sidebar's Label behavior).
                    .accessibilityHidden(true)
                Text(entry.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(category.color, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .pointerHover()
        // Evaluated per drag, so every drag stamps a fresh Block (new ID).
        .draggable(Block(kind: entry.kind))
        .accessibilityHint("Tap to add to the end of the program. Drag to place anywhere.")
    }
}

/// Drop-to-delete for both palette layouts: a block dragged in from the
/// workspace (its ID already exists in the tree) is deleted; a fresh
/// palette-origin drag (no ID in the tree yet) is rejected, so
/// palette→palette dragging is a no-op.
private struct PaletteDropDeletion: ViewModifier {
    let workspace: WorkspaceEditor

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    Color.red
                    Label("Drop to Delete", systemImage: "trash.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .opacity(isTargeted ? 0.9 : 0)
                .allowsHitTesting(false)
            }
            .dropDestination(for: Block.self) { items, _ in
                guard let dropped = items.first,
                    BlockTree.block(withID: dropped.id, in: workspace.blocks) != nil
                else { return false }
                workspace.delete(dropped.id)
                return true
            } isTargeted: {
                isTargeted = $0
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
    }
}

extension View {
    func paletteDropDeletion(workspace: WorkspaceEditor) -> some View {
        modifier(PaletteDropDeletion(workspace: workspace))
    }
}
