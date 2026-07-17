import SwiftUI
import TortoiseBlocksKit

/// One tappable palette entry: a display name, an icon, and the block kind
/// it stamps out (each tap creates a fresh `Block` with a new ID).
struct PaletteEntry: Identifiable {
    let title: String
    let systemImage: String
    let kind: BlockKind

    var id: String { title }
}

struct PaletteSection: Identifiable {
    let title: String
    let category: BlockCategory
    let entries: [PaletteEntry]

    var id: String { title }
}

enum Palette {
    static let sections: [PaletteSection] = [
        PaletteSection(
            title: "うごき", category: .movement,
            entries: [
                PaletteEntry(
                    title: "まえへ", systemImage: "arrow.up",
                    kind: .forward(.literal(100))),
                PaletteEntry(
                    title: "うしろへ", systemImage: "arrow.down",
                    kind: .backward(.literal(100))),
                PaletteEntry(
                    title: "みぎへまわる", systemImage: "arrow.clockwise",
                    kind: .turnRight(.literal(90))),
                PaletteEntry(
                    title: "ひだりへまわる", systemImage: "arrow.counterclockwise",
                    kind: .turnLeft(.literal(90))),
                PaletteEntry(
                    title: "ホームへもどる", systemImage: "house",
                    kind: .home),
            ]),
        PaletteSection(
            title: "ペン", category: .pen,
            entries: [
                PaletteEntry(
                    title: "ペンをおろす", systemImage: "pencil",
                    kind: .penDown),
                PaletteEntry(
                    title: "ペンをあげる", systemImage: "pencil.slash",
                    kind: .penUp),
                PaletteEntry(
                    title: "ペンのいろ", systemImage: "paintpalette",
                    kind: .penColor(.blue)),
                PaletteEntry(
                    title: "ペンのふとさ", systemImage: "lineweight",
                    kind: .penWidth(.literal(2))),
            ]),
        PaletteSection(
            title: "ぬり", category: .fill,
            entries: [
                PaletteEntry(
                    title: "ぬりのいろ", systemImage: "drop.fill",
                    kind: .fillColor(.yellow)),
                PaletteEntry(
                    title: "ぬりはじめ", systemImage: "paintbrush.fill",
                    kind: .beginFill),
                PaletteEntry(
                    title: "ぬりおわり", systemImage: "paintbrush",
                    kind: .endFill),
            ]),
        PaletteSection(
            title: "せいぎょ", category: .control,
            entries: [
                PaletteEntry(
                    title: "くりかえす", systemImage: "repeat",
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
    let workspace: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Palette.sections) { section in
                    PaletteSectionView(section: section, workspace: workspace)
                }
            }
            .padding()
        }
    }
}

struct PaletteSectionView: View {
    let section: PaletteSection
    let workspace: WorkspaceModel

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
    let workspace: WorkspaceModel

    var body: some View {
        Button {
            workspace.add(entry.kind)
        } label: {
            Label(entry.title, systemImage: entry.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(category.color)
        .accessibilityHint("プログラムにブロックをついかします")
    }
}

/// Horizontal palette strip for compact (iPhone) layouts.
struct PaletteStrip: View {
    let workspace: WorkspaceModel

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
    }
}
