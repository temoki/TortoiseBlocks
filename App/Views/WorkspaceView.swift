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
                        Button("Sample: Spiral") {
                            workspace.insertSample(SampleBlocks.spiral())
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .dropDestination(for: Block.self) { items, _ in
                    guard let block = items.first else { return false }
                    return workspace.handleDrop(block, at: 0, inBodyAt: .topLevel)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        BlockListView(
                            blocks: workspace.blocks, address: .topLevel, workspace: workspace,
                            highlightedID: runner.currentBlockID,
                            // Computed once per render and passed as plain
                            // data — rows only need the list, not the tree.
                            usedVariableNames: BlockTree.usedVariableNames(in: workspace.blocks)
                        )
                        // Ambient default for every value slot in the tree
                        // (NumberValueButton, ComparisonButton, etc.): the
                        // white "chip" look that reads on a solid,
                        // category-colored block (§21). ConditionEditor's
                        // popover — the one place these slots sit on a
                        // light background instead — resets back to
                        // `.bordered` locally.
                        .buttonStyle(WorkspaceChipButtonStyle())
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
    /// The mouth this list renders (container + slot); `.topLevel` at the top.
    let address: BodyAddress
    let workspace: WorkspaceEditor
    var highlightedID: UUID?
    /// Variable names in use anywhere in the program — quick choices for
    /// the name/number editors.
    var usedVariableNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                DropGap(address: address, index: index, workspace: workspace)
                BlockRowView(
                    block: block, workspace: workspace,
                    isHighlighted: block.id == highlightedID,
                    highlightedID: highlightedID,
                    usedVariableNames: usedVariableNames
                )
                .id(block.id)
            }
            DropGap(
                address: address, index: blocks.count, workspace: workspace,
                isEmphasized: blocks.isEmpty && address.containerID != nil
            )
        }
    }
}

/// Insertion point between rows. Invisible until a drag hovers over it,
/// then shows the accent insertion line. The trailing gap of an empty
/// repeat body renders as an explicit "drop here" zone instead.
struct DropGap: View {
    let address: BodyAddress
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
                    // Grows the drop-target hit area to roughly ±12pt (§21)
                    // without widening the row-to-row margin: the negative
                    // padding shrinks what this view reports to the
                    // enclosing VStack back down near its original ~8–10pt
                    // footprint, while its actual (rendered and
                    // hit-tested) frame stays 24pt tall, centered on the
                    // same line as before. Caveat to confirm on-device: a
                    // VStack paints siblings in order, so this reliably
                    // extends into the row *above* (painted earlier) but a
                    // row *below* (painted after, so it covers the
                    // overlap) may still win right at its own top edge.
                    .frame(height: 24)
                    .padding(.vertical, -7)
            }
        }
        .contentShape(.rect)
        .dropDestination(for: Block.self) { items, _ in
            guard let block = items.first else { return false }
            return workspace.handleDrop(block, at: index, inBodyAt: address)
        } isTargeted: {
            isTargeted = $0
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }
}

/// One block in the workspace. Containers (repeat, if) render their
/// kind-specific header over the shared container chrome; every row carries
/// a delete control, with move up/down in its context menu. `isHighlighted`
/// marks the executing block during playback.
struct BlockRowView: View {
    let block: Block
    let workspace: WorkspaceEditor
    var isHighlighted = false
    var highlightedID: UUID?
    var usedVariableNames: [String] = []

    var body: some View {
        switch block.kind {
        case .repeatBlock(let count, let body):
            ContainerBlockRow(
                block: block, childBlocks: body, workspace: workspace,
                highlightedID: highlightedID, usedVariableNames: usedVariableNames
            ) {
                Label("Repeat", systemImage: "repeat")
                NumberValueButton(value: count, usedNames: usedVariableNames) { new in
                    workspace.updateKind(of: block.id, to: .repeatBlock(count: new, body: body))
                }
                Text("times")
            }
        case .ifBlock(let condition, let body, let elseBody):
            ContainerBlockRow(
                block: block, childBlocks: body, workspace: workspace,
                highlightedID: highlightedID, usedVariableNames: usedVariableNames,
                elseBlocks: elseBody
            ) {
                Label("If", systemImage: "questionmark.diamond")
                // The three-slot condition collapses into one summary chip
                // (§21) — this is what makes the header fit at 360pt.
                ConditionButton(condition: condition, usedNames: usedVariableNames) { new in
                    workspace.updateKind(
                        of: block.id,
                        to: .ifBlock(condition: new, body: body, elseBody: elseBody))
                }
                Text("then")
                // Omitted (not just faded) once there's already an else
                // mouth, so it stops reserving header width for nothing
                // (#24).
                if elseBody == nil {
                    Button("Add Otherwise", systemImage: "arrow.triangle.branch") {
                        workspace.updateKind(
                            of: block.id,
                            to: .ifBlock(condition: condition, body: body, elseBody: []))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.large)
                    .tint(.white)
                    .accessibilityHint(
                        "Adds an otherwise mouth that runs when the condition fails")
                }
            }
        default:
            HStack(spacing: 8) {
                SimpleBlockLabel(kind: block.kind, usedVariableNames: usedVariableNames) { new in
                    workspace.updateKind(of: block.id, to: new)
                }
                Spacer(minLength: 0)
                RowControls(blockID: block.id, workspace: workspace)
            }
            .blockChrome(block.kind.category.color, isHighlighted: isHighlighted)
            .draggable(block)
            .rowContextMenu(blockID: block.id, workspace: workspace)
            .accessibilityValue(isHighlighted ? "Running" : "")
        }
    }
}

/// Chrome shared by every container kind (repeat, if): the solid,
/// category-colored header row with target/delete controls (move up/down in
/// the context menu) and drop-to-append, then the indented body list with
/// its guide bar. The kind-specific header cells come in as a ViewBuilder.
struct ContainerBlockRow<Header: View>: View {
    let block: Block
    let childBlocks: [Block]
    let workspace: WorkspaceEditor
    var highlightedID: UUID?
    var usedVariableNames: [String] = []
    /// The if block's else mouth; nil for every other container (and for an
    /// if without else). Rendered as a divider row plus a second body list.
    var elseBlocks: [Block]? = nil
    @ViewBuilder let header: Header

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                header
                InsertionTargetButton(
                    address: BodyAddress(containerID: block.id), workspace: workspace)
                Spacer(minLength: 0)
                RowControls(blockID: block.id, workspace: workspace)
            }
            .blockChrome(block.kind.category.color, isDropTargeted: isDropTargeted)
            .draggable(block)
            .rowContextMenu(blockID: block.id, workspace: workspace)
            // Dropping onto the header appends into this container's body.
            .dropDestination(for: Block.self) { items, _ in
                guard let dropped = items.first else { return false }
                return workspace.handleDrop(
                    dropped, at: childBlocks.count,
                    inBodyAt: BodyAddress(containerID: block.id))
            } isTargeted: {
                isDropTargeted = $0
            }

            indented(
                BlockListView(
                    blocks: childBlocks,
                    address: BodyAddress(containerID: block.id),
                    workspace: workspace,
                    highlightedID: highlightedID,
                    usedVariableNames: usedVariableNames
                ))

            if let elseBlocks {
                ElseDividerRow(blockID: block.id, elseCount: elseBlocks.count, workspace: workspace)
                indented(
                    BlockListView(
                        blocks: elseBlocks,
                        address: BodyAddress(containerID: block.id, slot: .elseBody),
                        workspace: workspace,
                        highlightedID: highlightedID,
                        usedVariableNames: usedVariableNames
                    ))
            }
        }
    }

    private func indented(_ list: BlockListView) -> some View {
        list
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(block.kind.category.color.opacity(0.5))
                    .frame(width: 3)
                    .padding(.leading, 4)
            }
    }
}

/// The if block's "otherwise" divider: labels the else mouth, hosts its
/// insertion target and drop-to-append, and can remove the mouth (contents
/// included — tree-swap undo makes that safe).
struct ElseDividerRow: View {
    let blockID: UUID
    let elseCount: Int
    let workspace: WorkspaceEditor

    @State private var isDropTargeted = false

    private var address: BodyAddress {
        BodyAddress(containerID: blockID, slot: .elseBody)
    }

    var body: some View {
        HStack(spacing: 8) {
            Label("Otherwise", systemImage: "arrow.triangle.branch")
            InsertionTargetButton(address: address, workspace: workspace)
            Spacer(minLength: 0)
            Button("Remove Otherwise", systemImage: "xmark.circle", role: .destructive) {
                guard let block = BlockTree.block(withID: blockID, in: workspace.blocks),
                    case .ifBlock(let condition, let body, _) = block.kind
                else { return }
                workspace.updateKind(
                    of: blockID, to: .ifBlock(condition: condition, body: body, elseBody: nil))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .blockChrome(BlockCategory.control.color, isDropTargeted: isDropTargeted)
        // Dropping onto the divider appends into the else mouth.
        .dropDestination(for: Block.self) { items, _ in
            guard let dropped = items.first else { return false }
            return workspace.handleDrop(dropped, at: elseCount, inBodyAt: address)
        } isTargeted: {
            isDropTargeted = $0
        }
    }
}

/// Label + argument slots for every non-container kind.
struct SimpleBlockLabel: View {
    let kind: BlockKind
    var usedVariableNames: [String] = []
    let onChange: (BlockKind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .forward(let value):
                Label("Forward", systemImage: "arrow.up")
                numberButton(value) { onChange(.forward($0)) }
            case .backward(let value):
                Label("Backward", systemImage: "arrow.down")
                numberButton(value) { onChange(.backward($0)) }
            case .turnRight(let value):
                Label("Turn Right", systemImage: "arrow.clockwise")
                numberButton(value) { onChange(.turnRight($0)) }
            case .turnLeft(let value):
                Label("Turn Left", systemImage: "arrow.counterclockwise")
                numberButton(value) { onChange(.turnLeft($0)) }
            case .home:
                Label("Go Home", systemImage: "house")
            case .penUp:
                Label("Pen Up", systemImage: "pencil.slash")
            case .penDown:
                Label("Pen Down", systemImage: "pencil")
            case .penColor(let color):
                Label("Pen Color", systemImage: "paintpalette")
                ColorValueButton(value: color) { onChange(.penColor($0)) }
            case .penWidth(let value):
                Label("Pen Width", systemImage: "lineweight")
                numberButton(value) { onChange(.penWidth($0)) }
            case .fillColor(let color):
                Label("Fill Color", systemImage: "drop.fill")
                ColorValueButton(value: color) { onChange(.fillColor($0)) }
            case .beginFill:
                Label("Start Fill", systemImage: "paintbrush.fill")
            case .endFill:
                Label("End Fill", systemImage: "paintbrush")
            case .setVariable(let name, let value):
                Label("Put in Box", systemImage: "tray.and.arrow.down")
                VariableNameButton(name: name, usedNames: usedVariableNames) {
                    onChange(.setVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.setVariable(name: name, value: $0)) }
            case .addVariable(let name, let value):
                Label("Add to Box", systemImage: "plus.square")
                VariableNameButton(name: name, usedNames: usedVariableNames) {
                    onChange(.addVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.addVariable(name: name, value: $0)) }
            case .subtractVariable(let name, let value):
                Label("Subtract from Box", systemImage: "minus.square")
                VariableNameButton(name: name, usedNames: usedVariableNames) {
                    onChange(.subtractVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.subtractVariable(name: name, value: $0)) }
            case .multiplyVariable(let name, let value):
                Label("Multiply Box", systemImage: "multiply.square")
                VariableNameButton(name: name, usedNames: usedVariableNames) {
                    onChange(.multiplyVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.multiplyVariable(name: name, value: $0)) }
            case .divideVariable(let name, let value):
                Label("Divide Box", systemImage: "divide.square")
                VariableNameButton(name: name, usedNames: usedVariableNames) {
                    onChange(.divideVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.divideVariable(name: name, value: $0)) }
            case .repeatBlock, .ifBlock:
                // Containers are rendered by BlockRowView, never here.
                EmptyView()
            }
        }
    }

    private func numberButton(
        _ value: NumberValue, onChange: @escaping (NumberValue) -> Void
    ) -> NumberValueButton {
        NumberValueButton(value: value, usedNames: usedVariableNames, onChange: onChange)
    }
}

/// Marks a container mouth as the palette's insertion target.
struct InsertionTargetButton: View {
    let address: BodyAddress
    let workspace: WorkspaceEditor

    private var isTarget: Bool { workspace.insertionTarget == address }

    var body: some View {
        Toggle(
            "Add Here",
            systemImage: isTarget ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle",
            isOn: Binding(
                get: { isTarget },
                set: { workspace.insertionTarget = $0 ? address : nil }
            )
        )
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .controlSize(.large)
        // Every row this appears on (§21: container headers, the else
        // divider) is now a solid `.control`-orange block, so white is the
        // one tint that's never fighting its own background.
        .tint(.white)
        .accessibilityHint("When on, new palette blocks go inside this block")
    }
}

/// Delete for one row — the only row operation that stays always visible
/// (§21); move up/down live in the row's context menu instead, where
/// SwiftUI also surfaces them to VoiceOver as custom actions.
struct RowControls: View {
    let blockID: UUID
    let workspace: WorkspaceEditor

    var body: some View {
        Button("Delete", systemImage: "xmark.circle", role: .destructive) {
            workspace.delete(blockID)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
    }
}

/// Row reordering as a long-press / right-click menu (§21) — the primary
/// path stays drag & drop, but this is the discoverable fallback, and
/// SwiftUI automatically exposes a `contextMenu`'s items to VoiceOver as
/// custom actions, which covers the accessibility requirement for free.
/// Reuses the same "Move Up" / "Move Down" / "Delete" strings the old
/// always-visible buttons used, so no new localization keys are needed.
extension View {
    fileprivate func rowContextMenu(blockID: UUID, workspace: WorkspaceEditor) -> some View {
        contextMenu {
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
    }
}

/// The shared "block" look for workspace rows (§21): a solid, saturated
/// category color with white text, matching the palette's `.borderedProminent`
/// buttons instead of the old pale tint. Opacity has no more room to signal
/// state once the background is already opaque, so the execution highlight
/// and drop-target feedback are a white border plus a brightness bump.
private struct BlockChrome: ViewModifier {
    let color: Color
    var isHighlighted = false
    var isDropTargeted = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .padding(8)
            .background(color, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white, lineWidth: isHighlighted ? 3 : (isDropTargeted ? 2 : 0))
            }
            .brightness(isHighlighted ? 0.2 : (isDropTargeted ? 0.12 : 0))
            .animation(.easeOut(duration: 0.15), value: isHighlighted)
            .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }
}

extension View {
    fileprivate func blockChrome(
        _ color: Color, isHighlighted: Bool = false, isDropTargeted: Bool = false
    ) -> some View {
        modifier(BlockChrome(color: color, isHighlighted: isHighlighted, isDropTargeted: isDropTargeted))
    }
}
