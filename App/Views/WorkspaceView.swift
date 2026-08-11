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
        Group {
            if workspace.blocks.isEmpty {
                ContentUnavailableView {
                    Label("Build with Blocks", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Tap a palette block, or drag one here")
                } actions: {
                    // A one-tap educational on-ramp: dropping in a whole
                    // sample goes through insertSample -> setBlocks, so it's
                    // undoable and dirties the document like any other edit.
                    // Each sample wears the picture it draws. The emoji is
                    // artwork, not text — the same in every language — so it
                    // is a `verbatim` icon rather than part of the localized
                    // title, and the string catalog stays free of it.
                    VStack(alignment: .leading, spacing: 8) {
                        SampleButton("🟦", "Sample: Filled Square") {
                            workspace.insertSample(SampleBlocks.filledSquare())
                        }
                        SampleButton("⭐️", "Sample: Star") {
                            workspace.insertSample(SampleBlocks.star())
                        }
                        SampleButton("🌀", "Sample: Spiral") {
                            workspace.insertSample(SampleBlocks.spiral())
                        }
                        SampleButton("🌳", "Sample: Tree") {
                            workspace.insertSample(SampleBlocks.fractalTree())
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .dropDestination(for: Block.self) { items, _ in
                    guard let block = items.first else { return false }
                    return workspace.handleDrop(block, at: 0, inBodyAt: .topLevel)
                }
            }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        BlockListView(
                            blocks: workspace.blocks, address: .topLevel, workspace: workspace,
                            highlightedID: runner.currentBlockID,
                            // Computed once per render and passed as plain
                            // data — rows only need the list, not the tree.
                            usedVariableNames: BlockTree.usedVariableNames(in: workspace.blocks),
                            usedFunctionNames: BlockTree.usedFunctionNames(in: workspace.blocks)
                        )
                        // Ambient default for every value slot in the tree
                        // (NumberValueButton, ComparisonButton, etc.): the
                        // white "chip" look that reads on a solid,
                        // category-colored block (#21). ConditionEditor's
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
                        if let lastScrollTime,
                            now.timeIntervalSince(lastScrollTime) < minScrollInterval
                        {
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
        // `safeAreaInset` rather than an overlay: it also insets the scroll
        // content, so the last block can still be scrolled clear of the can
        // instead of sitting under it for good. Nothing to throw away means
        // no can — the empty state has its own drop target already.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !workspace.blocks.isEmpty {
                WorkspaceTrashZone(workspace: workspace)
                    .padding(.vertical, 12)
            }
        }
        // Puts the inset on the window's bottom edge. Without it SwiftUI keeps
        // the home indicator's 20pt *inside* the inset, which reads as 36pt
        // under the can against 12pt above it. Note it has to be applied here
        // rather than to the inset's own content, where it does nothing.
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    workspace.undo()
                }
                .disabled(!workspace.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") {
                    workspace.redo()
                }
                .disabled(!workspace.canRedo)
            }
        }
    }
}

/// One entry in the empty workspace's "start from a sample" list: the drawing
/// it makes, then what it is called.
private struct SampleButton: View {
    let emoji: String
    let title: LocalizedStringResource
    let action: () -> Void

    init(_ emoji: String, _ title: LocalizedStringResource, action: @escaping () -> Void) {
        self.emoji = emoji
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Text(verbatim: emoji)
            }
        }
    }
}

/// Somewhere to put a block you have picked up and thought better of — the one
/// thing dragging was missing (#30). Deleting was never hidden: every row's
/// menu carries it (a ✕ of its own, when this was written — #44). What there
/// was no answer for was "I'm holding this and I don't want it", where the only
/// way out was to put it back exactly where it came from.
///
/// It is always visible rather than appearing mid-drag because SwiftUI has no
/// cross-platform signal for "a drag started" — `onDragSessionUpdated` is
/// macOS-only — so a zone that appeared on drag could not reliably learn that
/// the drag was cancelled, and would sooner or later be a zone that never went
/// away. Being visible up front is the better trade regardless: you can see
/// where to aim before you pick anything up.
struct WorkspaceTrashZone: View {
    let workspace: WorkspaceEditor

    @State private var isTargeted = false

    @ScaledMetric private var diameter: CGFloat = 56

    var body: some View {
        Image(systemName: isTargeted ? "trash.fill" : "trash")
            .font(.title2)
            .foregroundStyle(isTargeted ? Color.red : Color.secondary)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(isTargeted ? Color.red.opacity(0.15) : Color.clear)
                    .stroke(
                        isTargeted ? Color.red : Color.secondary.opacity(0.4),
                        lineWidth: 2)
            }
            .scaleEffect(isTargeted ? 1.1 : 1)
            .dropDestination(for: Block.self) { items, _ in
                guard let dropped = items.first else { return false }
                // A palette-origin block has no ID in the tree, so this is a
                // no-op for it (`BlockTree.removing` returns nil and
                // `delete` bails before touching undo). That is the right
                // outcome: throwing away a block you were carrying but never
                // placed just means not placing it.
                workspace.delete(dropped.id)
                return true
            } isTargeted: {
                isTargeted = $0
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            // The icon carries the meaning on its own, but a pointer gets the
            // words too.
            .help("Drop to Delete")
            // Drop-only, so VoiceOver can't operate it at all; the ✕ on every
            // row and the context menu's Delete stay the accessible paths.
            .accessibilityHidden(true)
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
    /// Block names in use anywhere in the program (#14), likewise.
    var usedFunctionNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                DropGap(address: address, index: index, workspace: workspace)
                BlockRowView(
                    block: block, workspace: workspace,
                    isHighlighted: block.id == highlightedID,
                    highlightedID: highlightedID,
                    usedVariableNames: usedVariableNames,
                    usedFunctionNames: usedFunctionNames,
                    // Only this list knows where the row sits, and a VoiceOver
                    // user has no other way to tell. 1-based: it is spoken
                    // to a child, not indexed by one.
                    position: index + 1
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
                // An empty mouth's drop zone stands in for the block that
                // would sit there, so it takes a block row's shape rather
                // than a height of its own.
                Text("Drop Here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .rowShape()
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 2, dash: [5])
                            )
                    }
                    .padding(.vertical, 2)
            }
            else {
                Capsule()
                    .fill(isTargeted ? Color.accentColor : Color.clear)
                    .frame(height: isTargeted ? 4 : 2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    // Grows the drop-target hit area to roughly ±12pt (#21)
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
        // Drop-only, so VoiceOver can't operate it: the invisible variant would
        // be an empty stop between every pair of rows, and the "Drop Here" of
        // an empty mouth would be read as if it were something to do. The
        // "Add Here" toggle on the container header is the accessible way in,
        // the same trade the trash zone makes.
        .accessibilityHidden(true)
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
    var usedFunctionNames: [String] = []
    /// Where this row sits among its siblings, 1-based, for VoiceOver.
    var position: Int = 1

    @ScaledMetric private var rowSpacing: CGFloat = 8

    var body: some View {
        switch block.kind {
        case .repeatBlock(let count, let body):
            ContainerBlockRow(
                block: block, childBlocks: body, workspace: workspace,
                highlightedID: highlightedID, usedVariableNames: usedVariableNames,
                usedFunctionNames: usedFunctionNames
            ) {
                Label("Repeat", systemImage: "repeat")
                    .labelStyle(BlockLabelStyle())
                NumberValueButton(
                    value: count, usedNames: usedVariableNames,
                    domain: block.kind.numberDomain ?? .repeatCount
                ) { new in
                    workspace.updateKind(of: block.id, to: .repeatBlock(count: new, body: body))
                }
                Text("times")
            }
        case .ifBlock(let condition, let body, let elseBody):
            ContainerBlockRow(
                block: block, childBlocks: body, workspace: workspace,
                highlightedID: highlightedID, usedVariableNames: usedVariableNames,
                usedFunctionNames: usedFunctionNames,
                elseBlocks: elseBody,
                // そうでなければ lives in the row's menu (#44) — the header is
                // the widest row in the app, and this is 52pt of it. Offered
                // only while there is no else mouth yet, exactly as the button
                // it replaced was (#24).
                addElseAction: elseBody == nil
                    ? {
                        workspace.updateKind(
                            of: block.id,
                            to: .ifBlock(condition: condition, body: body, elseBody: []))
                    }
                    : nil
            ) {
                Label("If", systemImage: "questionmark.diamond")
                    .labelStyle(BlockLabelStyle())
                // The three-slot condition collapses into one summary chip
                // (#21) — this is what makes the header fit at 360pt.
                ConditionButton(condition: condition, usedNames: usedVariableNames) { new in
                    workspace.updateKind(
                        of: block.id,
                        to: .ifBlock(condition: new, body: body, elseBody: elseBody))
                }
                Text("then")
            }
        case .defineBlock(let name, let body):
            ContainerBlockRow(
                block: block, childBlocks: body, workspace: workspace,
                highlightedID: highlightedID, usedVariableNames: usedVariableNames,
                usedFunctionNames: usedFunctionNames,
                headerCorners: .definitionHeader
            ) {
                Label("Make Block", systemImage: "puzzlepiece.extension")
                    .labelStyle(BlockLabelStyle())
                // Renaming the definition renames every call to it — the one
                // edit on a row that deliberately reaches outside its own
                // block, since the alternative is silently unhooking every
                // call from the block it names.
                NameButton(
                    name: name, kind: .block, usedNames: usedFunctionNames
                ) { new in
                    workspace.renameFunction(name, to: new)
                }
            }
        default:
            HStack(spacing: rowSpacing) {
                SimpleBlockLabel(
                    kind: block.kind, usedVariableNames: usedVariableNames,
                    usedFunctionNames: usedFunctionNames
                ) { new in
                    workspace.updateKind(of: block.id, to: new)
                }
                Spacer(minLength: 0)
                RowControls(blockID: block.id, workspace: workspace)
                    // Promoted to the custom action below: as a child it
                    // would be a second stop on every row, and its "Delete"
                    // would be read as part of the block's own sentence.
                    .accessibilityHidden(true)
            }
            .blockChrome(block.kind.category.color, isHighlighted: isHighlighted)
            .draggable(block)
            // One stop per block instead of three: the kind, its value
            // chips, and the running state read as a single sentence —
            // "Forward, Number 100, Running" — rather than as separate
            // elements a child has to swipe between. `.combine` keeps the
            // chips' own actions, so editing a value stays reachable.
            .accessibilityElement(children: .combine)
            // *After* the combine, deliberately: these attach to the element it
            // just built. Applied before, they would be properties of a child
            // being merged, which is a subtler thing to depend on.
            .rowContextMenu(blockID: block.id, workspace: workspace)
            .accessibilityValue(isHighlighted ? "Running" : "")
            // Where the row sits is context, not name: custom content carries
            // it without displacing the label `.combine` just assembled.
            // `.high` speaks it outright rather than burying it in the rotor.
            // "Order", not "Position" — that key is the scrubber's playback
            // position (さいせいいち) and would be read out here as one.
            .accessibilityCustomContent(
                Text("Order"), Text("item \(position)"), importance: .high
            )
            .accessibilityAction(named: Text("Delete")) {
                workspace.delete(block.id)
            }
        }
    }
}

/// Chrome shared by every container kind (repeat, if). The container is drawn
/// as one C-shaped block that holds its children in the mouth — the Scratch /
/// Blockly vocabulary — rather than as a header with an indented list under
/// it: header along the top, a solid spine down the left, a foot along the
/// bottom, all in the category color, with the workspace showing through the
/// mouth between them. The kind-specific header cells come in as a
/// ViewBuilder.
///
/// The C is assembled from parts rather than cut out of one shape, so no piece
/// ever has to know the mouth's geometry and nothing has to match the pane's
/// background color: the arms are drawn where they are, and the mouth is
/// simply where nothing is drawn.
struct ContainerBlockRow<Header: View>: View {
    let block: Block
    let childBlocks: [Block]
    let workspace: WorkspaceEditor
    var highlightedID: UUID?
    var usedVariableNames: [String] = []
    var usedFunctionNames: [String] = []
    /// The if block's else mouth; nil for every other container (and for an
    /// if without else). Rendered as a divider row plus a second body list.
    var elseBlocks: [Block]? = nil
    /// The shape of the C's top arm. A definition takes `.definitionHeader`
    /// instead, which is the whole visual difference between "this runs here"
    /// and "this is a block being named" (#14).
    var headerCorners: RowCorners = .containerHeader
    /// An extra entry for this header's menu — the if block's そうでなければ,
    /// which used to be a button of its own on the header (#44).
    var addElseAction: (() -> Void)? = nil
    @ViewBuilder let header: Header

    @State private var isDropTargeted = false
    /// The left arm: wide enough to read as a limb of the block rather than
    /// as a rule beside it (the guide bar it replaces was 3pt).
    @ScaledMetric private var spine: CGFloat = 12
    /// Clearance between the spine and the blocks it holds, so a child's
    /// corner doesn't touch the arm.
    @ScaledMetric private var gutter: CGFloat = 6
    /// The bottom arm. Thinner than a row — it closes the shape, it isn't
    /// something to read — but thick enough not to look like a hairline.
    @ScaledMetric private var foot: CGFloat = 11
    /// Gap between the header's own cells.
    @ScaledMetric private var headerSpacing: CGFloat = 8

    var body: some View {
        // Spacing 0: the arms have to meet. What separates the header from the
        // first child is the mouth's own leading `DropGap`, which is also what
        // separates any two sibling rows.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: headerSpacing) {
                header
                InsertionTargetButton(
                    address: BodyAddress(containerID: block.id), workspace: workspace)
                Spacer(minLength: 0)
                RowControls(
                    blockID: block.id, workspace: workspace, addElseAction: addElseAction)
            }
            .blockChrome(
                block.kind.category.color, corners: headerCorners,
                isDropTargeted: isDropTargeted
            )
            .draggable(block)
            .rowContextMenu(blockID: block.id, workspace: workspace)
            // The menu holds it, and a menu is reachable — but an action says
            // it out loud, the way Move Up / Move Down do.
            .accessibilityActions {
                if let addElseAction {
                    Button("Add Otherwise", action: addElseAction)
                }
            }
            // Dropping onto the header appends into this container's body.
            .dropDestination(for: Block.self) { items, _ in
                guard let dropped = items.first else { return false }
                return workspace.handleDrop(
                    dropped, at: childBlocks.count,
                    inBodyAt: BodyAddress(containerID: block.id))
            } isTargeted: {
                isDropTargeted = $0
            }

            mouth(
                BlockListView(
                    blocks: childBlocks,
                    address: BodyAddress(containerID: block.id),
                    workspace: workspace,
                    highlightedID: highlightedID,
                    usedVariableNames: usedVariableNames,
                    usedFunctionNames: usedFunctionNames
                ))

            if let elseBlocks {
                ElseDividerRow(blockID: block.id, elseCount: elseBlocks.count, workspace: workspace)
                mouth(
                    BlockListView(
                        blocks: elseBlocks,
                        address: BodyAddress(containerID: block.id, slot: .elseBody),
                        workspace: workspace,
                        highlightedID: highlightedID,
                        usedVariableNames: usedVariableNames,
                        usedFunctionNames: usedFunctionNames
                    ))
            }

            UnevenRoundedRectangle(cornerRadii: RowCorners.containerFoot.radii)
                .fill(block.kind.category.color)
                .frame(height: foot)
        }
    }

    /// One mouth: the children, held off the left edge far enough to clear the
    /// spine, with the spine drawn behind that clearance. A background rather
    /// than an overlay — the arm sits under the blocks it holds, and can never
    /// cover a drop target.
    private func mouth(_ list: BlockListView) -> some View {
        list
            .padding(.leading, spine + gutter)
            .background(alignment: .leading) {
                Rectangle()
                    .fill(block.kind.category.color)
                    .frame(width: spine)
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

    @ScaledMetric private var spacing: CGFloat = 8

    private var address: BodyAddress {
        BodyAddress(containerID: blockID, slot: .elseBody)
    }

    var body: some View {
        HStack(spacing: spacing) {
            Label("Otherwise", systemImage: "arrow.triangle.branch")
                .labelStyle(BlockLabelStyle())
            InsertionTargetButton(address: address, workspace: workspace)
            Spacer(minLength: 0)
            // The same control every other row now carries: one menu, opened
            // either by the ⋯ or by long-press. The mouth is removed from
            // inside it, so "けす" means the same thing wherever it is found.
            Menu {
                removeButton
            } label: {
                // Inside the label, for the reason `RowControls` gives.
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .touchTarget()
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .tint(BlockCategory.ink)
        }
        .blockChrome(
            BlockCategory.control.color, corners: .containerDivider,
            isDropTargeted: isDropTargeted
        )
        .contextMenu { removeButton }
        // Dropping onto the divider appends into the else mouth.
        .dropDestination(for: Block.self) { items, _ in
            guard let dropped = items.first else { return false }
            return workspace.handleDrop(dropped, at: elseCount, inBodyAt: address)
        } isTargeted: {
            isDropTargeted = $0
        }
        // Reachable without opening the menu, the way every row's Delete is.
        .accessibilityAction(named: Text("Remove Otherwise"), removeElse)
    }

    private var removeButton: some View {
        Button(
            "Remove Otherwise", systemImage: "xmark.circle", role: .destructive, action: removeElse)
    }

    /// Drops the else mouth, contents included — tree-swap undo makes that
    /// safe.
    private func removeElse() {
        guard let block = BlockTree.block(withID: blockID, in: workspace.blocks),
            case .ifBlock(let condition, let body, _) = block.kind
        else { return }
        workspace.updateKind(
            of: blockID, to: .ifBlock(condition: condition, body: body, elseBody: nil))
    }
}

/// Label + argument slots for every non-container kind.
struct SimpleBlockLabel: View {
    let kind: BlockKind
    var usedVariableNames: [String] = []
    var usedFunctionNames: [String] = []
    let onChange: (BlockKind) -> Void

    /// Between the title and the value chips that trail it.
    @ScaledMetric private var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
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
                NameButton(name: name, kind: .box, usedNames: usedVariableNames) {
                    onChange(.setVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.setVariable(name: name, value: $0)) }
            case .addVariable(let name, let value):
                Label("Add to Box", systemImage: "plus.square")
                NameButton(name: name, kind: .box, usedNames: usedVariableNames) {
                    onChange(.addVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.addVariable(name: name, value: $0)) }
            case .subtractVariable(let name, let value):
                Label("Subtract from Box", systemImage: "minus.square")
                NameButton(name: name, kind: .box, usedNames: usedVariableNames) {
                    onChange(.subtractVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.subtractVariable(name: name, value: $0)) }
            case .multiplyVariable(let name, let value):
                Label("Multiply Box", systemImage: "multiply.square")
                NameButton(name: name, kind: .box, usedNames: usedVariableNames) {
                    onChange(.multiplyVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.multiplyVariable(name: name, value: $0)) }
            case .divideVariable(let name, let value):
                Label("Divide Box", systemImage: "divide.square")
                NameButton(name: name, kind: .box, usedNames: usedVariableNames) {
                    onChange(.divideVariable(name: $0, value: value))
                }
                numberButton(value) { onChange(.divideVariable(name: name, value: $0)) }
            case .callBlock(let name):
                Label("Call Block", systemImage: "puzzlepiece.extension.fill")
                // Changes *this* call only — retargeting one call is a
                // different operation from renaming the block itself, which
                // is the definition header's chip (`renameFunction`).
                NameButton(name: name, kind: .block, usedNames: usedFunctionNames) {
                    onChange(.callBlock(name: $0))
                }
            case .repeatBlock, .ifBlock, .defineBlock:
                // Containers are rendered by BlockRowView, never here.
                EmptyView()
            }
        }
        // Set once for all the cases above: sibling rows line their icons up
        // on one centre and their titles on one left edge. The value buttons
        // that follow can't align — the titles they trail are different
        // lengths — so this is deliberately only about the label.
        .labelStyle(BlockLabelStyle())
    }

    /// The slot's range comes from the kind being rendered, so every call site
    /// above gets it right by construction — and `BlockKind.numberDomain` is
    /// an exhaustive switch, so a new kind can't quietly land without one.
    private func numberButton(
        _ value: NumberValue, onChange: @escaping (NumberValue) -> Void
    ) -> NumberValueButton {
        NumberValueButton(
            value: value, usedNames: usedVariableNames,
            domain: kind.numberDomain ?? .general, onChange: onChange)
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
        // Every row this appears on (#21: container headers, the else
        // divider) is a filled block, so the tint follows the label rather
        // than the system accent — white against the pastel would be the
        // control nobody can see (#41).
        .tint(BlockCategory.ink)
        .accessibilityHint("When on, new palette blocks go inside this block")
    }
}

/// The row's one visible control: the menu, not the ✕ (#44).
///
/// Everything a row can do lives in one place — うえへ / したへ / けす, plus
/// whatever the row itself adds (the if block's そうでなければ). It replaced the
/// always-visible ✕ #21 had put there, and the trade is deliberate. Deleting
/// had three ways in (the ✕, the long-press menu, the trash can) and this was
/// the redundant one; moving a row had *none* a child would find, because the
/// menu it lived in only opens on long-press. A visible ⋯ costs けす one tap
/// and buys うえへ / したへ their first real affordance — children press what
/// looks pressable, and nobody presses a block hoping for a hidden menu.
///
/// It also buys the widest row its width back: the if header's そうでなければ
/// button moved in here, which is what stopped the condition chip wrapping at
/// one level of nesting on iPad.
struct RowControls: View {
    let blockID: UUID
    let workspace: WorkspaceEditor
    /// The if block's "add an otherwise mouth", when this row has one.
    var addElseAction: (() -> Void)? = nil

    var body: some View {
        Menu {
            Button("Move Up", systemImage: "chevron.up") {
                workspace.move(blockID, by: -1)
            }
            Button("Move Down", systemImage: "chevron.down") {
                workspace.move(blockID, by: 1)
            }
            if let addElseAction {
                Button("Add Otherwise", systemImage: "arrow.triangle.branch", action: addElseAction)
                    // The hint the button on the header used to carry: what an
                    // else mouth *is* still needs saying, and a menu entry is
                    // where it is now read.
                    .accessibilityHint(
                        Text("Adds an otherwise mouth that runs when the condition fails"))
            }
            Divider()
            Button("Delete", systemImage: "xmark.circle", role: .destructive) {
                workspace.delete(blockID)
            }
        } label: {
            // The finger target belongs *inside* the label: a `Menu` hit-tests
            // what it was handed to draw, so a `frame` wrapped around the menu
            // grows the layout and not the tappable area. The ✕ hid this — a
            // filled circle is a big shape on its own — and three dots on a
            // thin band are not, which is exactly how it came out on iPad.
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .touchTarget()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .controlSize(.large)
        .tint(BlockCategory.ink)
    }
}

/// Row reordering as a long-press / right-click menu (#21) — the primary
/// path stays drag & drop, but this is the discoverable fallback. Reuses
/// the same "Move Up" / "Move Down" / "Delete" strings the old
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
        // SwiftUI exposes a contextMenu's items to VoiceOver as custom
        // actions on its own, but that isn't guaranteed everywhere this
        // app runs (macOS's context menu is a right-click, not the
        // long-press VoiceOver users get on iOS/iPadOS) — these two make
        // ↑↓ reachable explicitly. Delete already has its own always-
        // visible button, so it doesn't need a duplicate action.
        .accessibilityAction(named: Text("Move Up")) {
            workspace.move(blockID, by: -1)
        }
        .accessibilityAction(named: Text("Move Down")) {
            workspace.move(blockID, by: 1)
        }
    }
}

/// Which corners a piece of the workspace rounds.
///
/// A free-standing row is a rounded rectangle. A container is one C-shaped
/// block assembled from three pieces (`ContainerBlockRow`), so its corners
/// split three ways: the four *outer* corners of the C round at 10 — a little
/// wider than a row, because the shape they enclose is; the two corners facing
/// the *mouth* round at a row's own 8; and every edge where the spine runs on
/// into the next piece stays square, which is what makes the parts read as one
/// block.
enum RowCorners {
    /// A row that stands on its own.
    case standalone
    /// A container header — the C's top arm, with the spine leaving its
    /// bottom-left.
    case containerHeader
    /// A definition's header (#14) — the same arm, but with the top corners
    /// rounded twice as wide, into a hat.
    ///
    /// It is the one thing on screen that says a block is *not part of the
    /// sequence it sits in*: the program is a single column, so a definition
    /// dropped into it otherwise reads as something that happens at that
    /// point, which is precisely what a definition doesn't do. Scratch says
    /// this with a hat block on a 2-D canvas; a column has only the silhouette
    /// to say it with.
    case definitionHeader
    /// The if block's else divider — an arm with spine both above and below,
    /// so neither leading corner rounds.
    case containerDivider
    /// The C's bottom arm, closing the shape.
    case containerFoot

    var radii: RectangleCornerRadii {
        switch self {
        case .standalone:
            RectangleCornerRadii(topLeading: 8, bottomLeading: 8, bottomTrailing: 8, topTrailing: 8)
        case .containerHeader:
            RectangleCornerRadii(
                topLeading: 10, bottomLeading: 0, bottomTrailing: 8, topTrailing: 10)
        case .definitionHeader:
            RectangleCornerRadii(
                topLeading: 20, bottomLeading: 0, bottomTrailing: 8, topTrailing: 20)
        case .containerDivider:
            RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: 8, topTrailing: 8)
        case .containerFoot:
            RectangleCornerRadii(
                topLeading: 0, bottomLeading: 10, bottomTrailing: 10, topTrailing: 8)
        }
    }
}

/// The shared "block" look for workspace rows (#21, recolored in #41): an
/// opaque pastel category fill under fixed dark ink, matching the palette
/// entries. Opacity has no room to signal state once the background is already
/// opaque, so the execution highlight and drop-target feedback are a border —
/// and only a border, since anything that touches the fill takes the label's
/// contrast with it.
private struct BlockChrome: ViewModifier {
    let color: Color
    var corners: RowCorners = .standalone
    var isHighlighted = false
    var isDropTargeted = false

    @Environment(\.colorScheme) private var scheme

    private var shape: UnevenRoundedRectangle { .rect(cornerRadii: corners.radii) }

    /// The ring *does* follow the appearance, where the fill and the label
    /// don't. Its job is to stand out against two things at once — the pastel
    /// inside it and the pane outside — and which of black or white manages
    /// that is exactly what the appearance decides. White vanished into the
    /// pastel in light mode; ink would read as a gap against a dark pane.
    private var ring: Color { scheme == .dark ? .white : BlockCategory.ink }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(BlockCategory.ink)
            .rowShape()
            .background(color, in: shape)
            .overlay {
                shape.stroke(ring, lineWidth: isHighlighted ? 3 : (isDropTargeted ? 2 : 0))
            }
            // The ring is the whole of it, and the fill is left alone on
            // purpose. State used to add `.brightness`, which is a filter over
            // the composited row: it moves the card *and* its label the same
            // way, and the label is already white, so only the card travelled
            // — toward the text. Highlighting made a row harder to read the
            // more it was highlighted. Measured white-on-card in dark mode,
            // the fill green went 1.92:1 to 1.24:1 the moment it started
            // running. So the two channels are now separate: the fill says
            // which kind of block this is, the ring says what it is doing, and
            // the ring can never eat the label's contrast.
            .shadow(color: ring.opacity(isHighlighted ? 0.5 : 0), radius: 6)
            .animation(.easeOut(duration: 0.15), value: isHighlighted)
            .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }
}

extension View {
    /// The outer shape every block-sized thing in the workspace shares: held
    /// to a common minimum height, then the row padding. Carried by the block
    /// rows themselves and by an empty mouth's "drop here" zone, which stands
    /// in for a row and so has to measure like one.
    ///
    /// Height otherwise follows whatever the row happens to hold, which at the
    /// macOS body size means 32pt for a bare label, 40pt with a value chip and
    /// 43pt for a container header — a program that steps unevenly down the
    /// page.
    fileprivate func rowShape() -> some View {
        modifier(RowShape())
    }
}

/// A modifier rather than a plain `View` extension so it can hold
/// `@ScaledMetric`: at the largest Dynamic Type sizes the text grows but a
/// hard-coded inset does not, and the words end up crowding the block's edge.
private struct RowShape: ViewModifier {
    @ScaledMetric private var inset: CGFloat = 8

    func body(content: Content) -> some View {
        ZStack {
            RowHeightFloor()
            content
        }
        .padding(inset)
    }
}

/// The minimum, as a hidden copy of the tallest control a row can hold rather
/// than a fixed number — for the same reason `BlockLabelStyle` sizes its icon
/// slot from a hidden glyph. Control metrics differ between macOS and iOS and
/// move again with Dynamic Type, so no single hard-coded value is right for
/// all of them, and too small a one wouldn't fail loudly: the tall rows would
/// simply stay tall.
private struct RowHeightFloor: View {
    var body: some View {
        // Matches `InsertionTargetButton`, the tallest of them: a bordered
        // control at `.large`. Update this if a taller one joins a row.
        Button("", systemImage: "arrow.down.to.line.circle") {}
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .hidden()
            // An invisible control has no business in the accessibility tree.
            .accessibilityHidden(true)
    }
}

extension View {
    fileprivate func blockChrome(
        _ color: Color, corners: RowCorners = .standalone, isHighlighted: Bool = false,
        isDropTargeted: Bool = false
    ) -> some View {
        modifier(
            BlockChrome(
                color: color, corners: corners, isHighlighted: isHighlighted,
                isDropTargeted: isDropTargeted))
    }
}
