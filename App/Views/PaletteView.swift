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
            ]),
    ]
}

extension BlockCategory {
    /// Category tint (§7): movement=blue, pen=purple, fill=green, control=orange.
    var color: Color {
        switch self {
        case .movement: .blue
        case .pen: .purple
        case .fill: .green
        case .control: .orange
        }
    }
}

/// The tap-to-add palette (vertical, for regular width layouts).
struct PaletteView: View {
    let workspace: WorkspaceEditor

    var body: some View {
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
        // Evaluated per drag, so every drag stamps a fresh Block (new ID).
        .draggable(Block(kind: entry.kind))
        .accessibilityHint("Tap to add to the end of the program. Drag to place anywhere.")
    }
}

/// Horizontal palette strip for compact (iPhone) layouts.
struct PaletteStrip: View {
    let workspace: WorkspaceEditor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Palette.sections) { section in
                    ForEach(section.entries) { entry in
                        PaletteEntryButton(
                            entry: entry, category: section.category, workspace: workspace)
                    }
                }
            }
            .padding(.horizontal)
        }
        .paletteDropDeletion(workspace: workspace)
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
