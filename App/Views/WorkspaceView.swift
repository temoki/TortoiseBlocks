import SwiftUI
import TortoiseBlocksKit

/// The program pane: title bar with undo/redo, then the block tree.
/// During playback the executing block is highlighted and kept in view.
struct WorkspaceView: View {
    let workspace: WorkspaceEditor
    let runner: RunnerModel

    /// The last blockID actually scrolled to, and when — lets repeat loops
    /// (which revisit the same few rows) skip redundant `scrollTo` calls and
    /// caps the fire rate to ~4/sec instead of once per committed command.
    @State private var lastScrolledBlockID: UUID?
    @State private var lastScrollTime: Date?
    private let minScrollInterval: TimeInterval = 0.25

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Program")
                    .font(.headline)
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    workspace.undo()
                }
                .disabled(!workspace.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") {
                    workspace.redo()
                }
                .disabled(!workspace.canRedo)
            }
            .labelStyle(.iconOnly)
            .padding()
            Divider()
            if workspace.blocks.isEmpty {
                ContentUnavailableView {
                    Label("Build with Blocks", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Tap a palette block, or drag one here")
                } actions: {
                    // A one-tap educational on-ramp: dropping in a whole
                    // sample goes through insertSample -> setBlocks, so it's
                    // undoable and dirties the document like any other edit.
                    VStack(spacing: 8) {
                        Button("Sample: Filled Square") {
                            workspace.insertSample(SampleBlocks.filledSquare())
                        }
                        Button("Sample: Star") {
                            workspace.insertSample(SampleBlocks.star())
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .dropDestination(for: Block.self) { items, _ in
                    guard let block = items.first else { return false }
                    return workspace.handleDrop(block, at: 0, inBodyOf: nil)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        BlockListView(
                            blocks: workspace.blocks, containerID: nil, workspace: workspace,
                            highlightedID: runner.currentBlockID
                        )
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: runner.currentBlockID) { _, id in
                        guard let id, id != lastScrolledBlockID else { return }
                        let now = Date()
                        if let lastScrollTime, now.timeIntervalSince(lastScrollTime) < minScrollInterval {
                            return
                        }
                        lastScrolledBlockID = id
                        lastScrollTime = now
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

/// Renders a sibling sequence of blocks (recursively via BlockRowView),
/// with a drop gap before every row and after the last one.
/// `highlightedID` is passed as plain data (not the runner model) so each
/// row depends on exactly the value it renders.
struct BlockListView: View {
    let blocks: [Block]
    /// The repeat whose body this list renders; nil at the top level.
    let containerID: UUID?
    let workspace: WorkspaceEditor
    var highlightedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                DropGap(containerID: containerID, index: index, workspace: workspace)
                BlockRowView(
                    block: block, workspace: workspace,
                    isHighlighted: block.id == highlightedID,
                    highlightedID: highlightedID
                )
                .id(block.id)
            }
            DropGap(
                containerID: containerID, index: blocks.count, workspace: workspace,
                isEmphasized: blocks.isEmpty && containerID != nil
            )
        }
    }
}

/// Insertion point between rows. Invisible until a drag hovers over it,
/// then shows the accent insertion line. The trailing gap of an empty
/// repeat body renders as an explicit "drop here" zone instead.
struct DropGap: View {
    let containerID: UUID?
    let index: Int
    let workspace: WorkspaceEditor
    var isEmphasized = false

    @State private var isTargeted = false

    var body: some View {
        Group {
            if isEmphasized {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [5])
                    )
                    .frame(height: 32)
                    .overlay {
                        Text("Drop Here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
            } else {
                Capsule()
                    .fill(isTargeted ? Color.accentColor : Color.clear)
                    .frame(height: isTargeted ? 4 : 2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
        }
        .contentShape(.rect)
        .dropDestination(for: Block.self) { items, _ in
            guard let block = items.first else { return false }
            return workspace.handleDrop(block, at: index, inBodyOf: containerID)
        } isTargeted: {
            isTargeted = $0
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }
}

/// One block in the workspace. A repeat renders as a container with its
/// body indented beneath it; every row carries move/delete controls.
/// `isHighlighted` marks the executing block during playback.
struct BlockRowView: View {
    let block: Block
    let workspace: WorkspaceEditor
    var isHighlighted = false
    var highlightedID: UUID?

    @State private var isDropTargeted = false

    var body: some View {
        if case .repeatBlock(let count, let body) = block.kind {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Repeat", systemImage: "repeat")
                    NumberValueButton(value: count) { new in
                        workspace.updateKind(of: block.id, to: .repeatBlock(count: new, body: body))
                    }
                    Text("times")
                    InsertionTargetButton(blockID: block.id, workspace: workspace)
                    Spacer(minLength: 0)
                    RowControls(blockID: block.id, workspace: workspace)
                }
                .padding(8)
                .background(
                    BlockCategory.control.color.opacity(isDropTargeted ? 0.35 : 0.15),
                    in: .rect(cornerRadius: 8)
                )
                .draggable(block)
                // Dropping onto the header appends into this repeat's body.
                .dropDestination(for: Block.self) { items, _ in
                    guard let dropped = items.first else { return false }
                    return workspace.handleDrop(dropped, at: body.count, inBodyOf: block.id)
                } isTargeted: {
                    isDropTargeted = $0
                }

                BlockListView(
                    blocks: body, containerID: block.id, workspace: workspace,
                    highlightedID: highlightedID
                )
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
            .background(
                block.kind.category.color.opacity(isHighlighted ? 0.4 : 0.15),
                in: .rect(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: isHighlighted ? 3 : 0)
            }
            .animation(.easeOut(duration: 0.15), value: isHighlighted)
            .draggable(block)
            .accessibilityValue(isHighlighted ? "Running" : "")
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
                Label("Forward", systemImage: "arrow.up")
                NumberValueButton(value: value) { onChange(.forward($0)) }
            case .backward(let value):
                Label("Backward", systemImage: "arrow.down")
                NumberValueButton(value: value) { onChange(.backward($0)) }
            case .turnRight(let value):
                Label("Turn Right", systemImage: "arrow.clockwise")
                NumberValueButton(value: value) { onChange(.turnRight($0)) }
            case .turnLeft(let value):
                Label("Turn Left", systemImage: "arrow.counterclockwise")
                NumberValueButton(value: value) { onChange(.turnLeft($0)) }
            case .home:
                Label("Go Home", systemImage: "house")
            case .penUp:
                Label("Pen Up", systemImage: "pencil.slash")
            case .penDown:
                Label("Pen Down", systemImage: "pencil")
            case .penColor(let color):
                Label("Pen Color", systemImage: "paintpalette")
                ColorValueButton(color: color) { onChange(.penColor($0)) }
            case .penWidth(let value):
                Label("Pen Width", systemImage: "lineweight")
                NumberValueButton(value: value) { onChange(.penWidth($0)) }
            case .fillColor(let color):
                Label("Fill Color", systemImage: "drop.fill")
                ColorValueButton(color: color) { onChange(.fillColor($0)) }
            case .beginFill:
                Label("Start Fill", systemImage: "paintbrush.fill")
            case .endFill:
                Label("End Fill", systemImage: "paintbrush")
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
    let workspace: WorkspaceEditor

    private var isTarget: Bool { workspace.insertionTargetID == blockID }

    var body: some View {
        Toggle(
            "Add Here",
            systemImage: isTarget ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle",
            isOn: Binding(
                get: { isTarget },
                set: { workspace.insertionTargetID = $0 ? blockID : nil }
            )
        )
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .tint(BlockCategory.control.color)
        .accessibilityHint("When on, new palette blocks go inside this repeat")
    }
}

/// Move-up / move-down / delete for one row.
struct RowControls: View {
    let blockID: UUID
    let workspace: WorkspaceEditor

    var body: some View {
        HStack(spacing: 2) {
            Button("Move Up", systemImage: "chevron.up") {
                workspace.move(blockID, by: -1)
            }
            Button("Move Down", systemImage: "chevron.down") {
                workspace.move(blockID, by: 1)
            }
            Button("Delete", systemImage: "xmark.circle", role: .destructive) {
                workspace.delete(blockID)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}
