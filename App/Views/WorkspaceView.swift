import SwiftUI
import TortoiseBlocksKit

/// The program pane: title bar with undo/redo, then the block tree.
struct WorkspaceView: View {
    let workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("プログラム")
                    .font(.headline)
                Spacer()
                Button("もどす", systemImage: "arrow.uturn.backward") {
                    workspace.undo()
                }
                .disabled(!workspace.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                Button("やりなおす", systemImage: "arrow.uturn.forward") {
                    workspace.redo()
                }
                .disabled(!workspace.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .labelStyle(.iconOnly)
            .padding()
            Divider()
            if workspace.blocks.isEmpty {
                ContentUnavailableView(
                    "ブロックをならべよう",
                    systemImage: "square.stack.3d.up",
                    description: Text("パレットのブロックをタップすると\nここにならびます")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    BlockListView(blocks: workspace.blocks, workspace: workspace)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Renders a sibling sequence of blocks (recursively via BlockRowView).
struct BlockListView: View {
    let blocks: [Block]
    let workspace: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                BlockRowView(block: block, workspace: workspace)
            }
        }
    }
}

/// One block in the workspace. A repeat renders as a container with its
/// body indented beneath it; every row carries move/delete controls.
struct BlockRowView: View {
    let block: Block
    let workspace: WorkspaceModel

    var body: some View {
        if case .repeatBlock(let count, let body) = block.kind {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("くりかえす", systemImage: "repeat")
                    NumberValueButton(value: count) { new in
                        workspace.updateKind(of: block.id, to: .repeatBlock(count: new, body: body))
                    }
                    Text("かい")
                    InsertionTargetButton(blockID: block.id, workspace: workspace)
                    Spacer(minLength: 0)
                    RowControls(blockID: block.id, workspace: workspace)
                }
                .padding(8)
                .background(BlockCategory.control.color.opacity(0.15), in: .rect(cornerRadius: 8))

                BlockListView(blocks: body, workspace: workspace)
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(BlockCategory.control.color.opacity(0.5))
                            .frame(width: 3)
                            .padding(.leading, 4)
                    }
            }
        } else {
            HStack(spacing: 8) {
                SimpleBlockLabel(kind: block.kind) { new in
                    workspace.updateKind(of: block.id, to: new)
                }
                Spacer(minLength: 0)
                RowControls(blockID: block.id, workspace: workspace)
            }
            .padding(8)
            .background(block.kind.category.color.opacity(0.15), in: .rect(cornerRadius: 8))
        }
    }
}

/// Label + argument slots for every non-container kind.
struct SimpleBlockLabel: View {
    let kind: BlockKind
    let onChange: (BlockKind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .forward(let value):
                Label("まえへ", systemImage: "arrow.up")
                NumberValueButton(value: value) { onChange(.forward($0)) }
            case .backward(let value):
                Label("うしろへ", systemImage: "arrow.down")
                NumberValueButton(value: value) { onChange(.backward($0)) }
            case .turnRight(let value):
                Label("みぎへまわる", systemImage: "arrow.clockwise")
                NumberValueButton(value: value) { onChange(.turnRight($0)) }
            case .turnLeft(let value):
                Label("ひだりへまわる", systemImage: "arrow.counterclockwise")
                NumberValueButton(value: value) { onChange(.turnLeft($0)) }
            case .home:
                Label("ホームへもどる", systemImage: "house")
            case .penUp:
                Label("ペンをあげる", systemImage: "pencil.slash")
            case .penDown:
                Label("ペンをおろす", systemImage: "pencil")
            case .penColor(let color):
                Label("ペンのいろ", systemImage: "paintpalette")
                ColorValueButton(color: color) { onChange(.penColor($0)) }
            case .penWidth(let value):
                Label("ペンのふとさ", systemImage: "lineweight")
                NumberValueButton(value: value) { onChange(.penWidth($0)) }
            case .fillColor(let color):
                Label("ぬりのいろ", systemImage: "drop.fill")
                ColorValueButton(color: color) { onChange(.fillColor($0)) }
            case .beginFill:
                Label("ぬりはじめ", systemImage: "paintbrush.fill")
            case .endFill:
                Label("ぬりおわり", systemImage: "paintbrush")
            case .repeatBlock:
                // Containers are rendered by BlockRowView, never here.
                EmptyView()
            }
        }
    }
}

/// Marks a repeat as the palette's insertion target.
struct InsertionTargetButton: View {
    let blockID: UUID
    let workspace: WorkspaceModel

    private var isTarget: Bool { workspace.insertionTargetID == blockID }

    var body: some View {
        Toggle(
            "ここへついか", systemImage: isTarget ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle",
            isOn: Binding(
                get: { isTarget },
                set: { workspace.insertionTargetID = $0 ? blockID : nil }
            )
        )
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .tint(BlockCategory.control.color)
        .accessibilityHint("オンにするとパレットのブロックがこのなかにはいります")
    }
}

/// Move-up / move-down / delete for one row.
struct RowControls: View {
    let blockID: UUID
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 2) {
            Button("うえへ", systemImage: "chevron.up") {
                workspace.move(blockID, by: -1)
            }
            Button("したへ", systemImage: "chevron.down") {
                workspace.move(blockID, by: 1)
            }
            Button("けす", systemImage: "xmark.circle", role: .destructive) {
                workspace.delete(blockID)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}
