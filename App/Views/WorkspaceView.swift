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

    /// Read here rather than hidden in a modifier the way `blockEditAnimation`
    /// hides it (#70): scrolling is an imperative `withAnimation`, so there is
    /// no modifier for the check to live inside. Reduced motion still moves
    /// the list — the block has to be on screen either way — it just arrives
    /// without the travel.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A `ZStack` rather than a `Group`, and that is the whole reason the
        // cross-fade below works (#72). `Group` hands its modifiers to each
        // *child*, so an `.animation(_:value:)` on one lands on whichever
        // branch is showing — and when the branch flips, the new child gets a
        // fresh modifier with no previous value to compare against, so the one
        // change you wanted animated is the one that cannot be. The can went
        // with it, its `safeAreaInset` being distributed the same way. A real
        // container is a stable ancestor, and it also puts the two states in
        // the same space, which is what a cross-fade is.
        ZStack {
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
                    //
                    // "Sample" is said once, over the list, rather than at the
                    // head of all four names: four labels that begin the same
                    // way are four labels a child has to read past to find the
                    // word that differs.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        SampleButton("🟦", "Filled Square") {
                            workspace.insertSample(SampleBlocks.filledSquare())
                        }
                        SampleButton("⭐️", "Star") {
                            workspace.insertSample(SampleBlocks.star())
                        }
                        SampleButton("🌀", "Spiral") {
                            workspace.insertSample(SampleBlocks.spiral())
                        }
                        SampleButton("🌳", "Tree") {
                            workspace.insertSample(SampleBlocks.fractalTree())
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .dropDestination(for: Block.self) { items, _ in
                    guard let block = items.first else { return false }
                    return workspace.handleDrop(block, at: 0, inBodyAt: .topLevel)
                }
                // The default for an inserted or removed view, said out loud:
                // this pane is the one place a transition is the point rather
                // than a side effect, and it should not change silently.
                .transition(.opacity)
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
                        // Every tree edit — add, delete, reorder, drop, undo,
                        // redo — moves the rows instead of replacing them
                        // (#70). Innermost, so it scopes to the block list:
                        // the same edit also changes the toolbar's undo/redo
                        // enablement and the transport's staleness, and
                        // neither of those should animate because a block
                        // moved.
                        .motion(Motion.blockEdit, value: workspace.editGeneration)
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
                        if let lastScrollTime,
                            Date().timeIntervalSince(lastScrollTime) < minScrollInterval
                        {
                            return
                        }
                        scroll(proxy, to: id)
                    }
                    // A block added from the palette lands at the end of the
                    // program, or in whichever mouth is the insertion target —
                    // either of which can be off screen once a program has
                    // grown, and then pressing a palette block looks like it
                    // did nothing (#71).
                    //
                    // Unthrottled, unlike the playback follow above: this is
                    // one press, not ten a second. It still records the time,
                    // so a run in progress waits its `minScrollInterval` before
                    // pulling the list back to the executing block.
                    .onChange(of: workspace.lastAddedBlockID) { _, id in
                        guard let id else { return }
                        scroll(proxy, to: id)
                    }
                }
                .transition(.opacity)
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
        // One dialog for both ways in — the can and the Mac's Edit menu —
        // because a second presentation modifier of the same kind would
        // silently swallow this one. It asks even though ⌘Z brings the
        // program straight back: a child who has just lost their work does
        // not know that yet.
        //
        // An alert rather than a `confirmationDialog`, which on iPad is a
        // popover hanging off the can: that form drops the title *and* the
        // cancel button (you dismiss it by tapping away), so the question
        // never gets asked and the way out is the one thing not on screen.
        // Both matter more here than the tidier anchoring.
        .alert(
            "Delete all blocks?",
            isPresented: Binding(
                get: { workspace.confirmsDeleteAll },
                set: { workspace.confirmsDeleteAll = $0 })
        ) {
            Button("Delete All", role: .destructive) {
                workspace.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can undo this.")
        }
        // The empty pane and the program are the same surface showing two
        // things, so they cross-fade rather than cut (#72). Applied *outside*
        // the inset above so the can fades in with the first block instead of
        // popping in beside a pane that faded — the two are one change.
        .motion(Motion.paneSwap, value: workspace.blocks.isEmpty)
        // Puts the inset on the window's bottom edge. Without it SwiftUI keeps
        // the home indicator's 20pt *inside* the inset, which reads as 36pt
        // under the can against 12pt above it. Note it has to be applied here
        // rather than to the inset's own content, where it does nothing.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Brings a row into view, and records that it did. Both callers write the
    /// same two pieces of state, so they share one place to write them: the
    /// throttle above reads `lastScrollTime` whoever set it, which is what
    /// keeps a palette press and a running program from fighting over the
    /// scroll position.
    private func scroll(_ proxy: ScrollViewProxy, to id: UUID) {
        lastScrolledBlockID = id
        lastScrollTime = Date()
        withAnimation(reduceMotion ? nil : Motion.scrollFollow) {
            proxy.scrollTo(id, anchor: .center)
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

/// The program pane's toolbar: undo, then redo.
///
/// A `ToolbarContent` type applied by the root views rather than a `.toolbar`
/// inside `WorkspaceView`, because `CompactRootView` has two buttons of its own
/// to put *after* these (#113) — and toolbar items are ordered by how deeply
/// their modifier sits, so a group added from outside `WorkspaceView` lands in
/// front of one added inside it, which is the wrong way round. One modifier,
/// one order, written where it is read.
struct WorkspaceToolbar: ToolbarContent {
    let workspace: WorkspaceEditor

    var body: some ToolbarContent {
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

/// Somewhere to put a block you have picked up and thought better of — the one
/// thing dragging was missing (#30) — and, since #48, the way to throw away the
/// whole program.
///
/// Deleting one block was never hidden: every row's menu carries it (a ✕ of its
/// own, when this was written — #44). What there was no answer for was "I'm
/// holding this and I don't want it", where the only way out was to put it back
/// exactly where it came from. Clearing the workspace had no answer either once
/// the row's ✕ went away, and a can you can only drop onto was the obvious
/// place to put one.
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
    /// Counts drops the can has accepted, so it can answer one (#76). A
    /// counter rather than a flag: two blocks thrown away in a row are two
    /// bounces, and a flag would have to be put back before it could fire
    /// again.
    @State private var acceptedDrops = 0

    @ScaledMetric private var diameter: CGFloat = 56

    var body: some View {
        // Tapping is the second thing it does (#48): a drop throws away the
        // one block you are holding, a tap offers to throw away the program.
        // The two never collide — they are different gestures — and the tap
        // asks first.
        //
        // It also stops being invisible to VoiceOver. The can was hidden
        // because a drop target is nothing a VoiceOver user can operate; a
        // button is, so it can finally say what it is.
        Button {
            workspace.confirmsDeleteAll = true
        } label: {
            Image(systemName: isTargeted ? "trash.fill" : "trash")
                .font(.title2)
                .foregroundStyle(isTargeted ? Color.red : Color.secondary)
                .frame(width: diameter, height: diameter)
                // Without this the can only answers on what it actually
                // *draws* — the glyph and the ring — and the transparent gap
                // between them, most of the target, is not there at all. The
                // symptom is the ⋯ menu's again (`touchTarget`): a control
                // that looks right and misses taps aimed at the middle of it.
                // A rect rather than a circle, so the corners of the 56pt
                // frame stay usable and the drop target does not shrink.
                .contentShape(.rect)
                .background {
                    Circle()
                        .fill(isTargeted ? Color.red.opacity(0.15) : Color.clear)
                        .stroke(
                            isTargeted ? Color.red : Color.secondary.opacity(0.4),
                            lineWidth: 2)
                }
                .scaleEffect(isTargeted ? 1.1 : 1)
                // The can reacts while a block is over it — red, filled,
                // larger — and used to fall silent at the moment that matters.
                // You let go, the block was gone, and the can was already back
                // to its resting grey as though nothing had been thrown into
                // it (#76).
                .symbolMotion(.bounce, trigger: acceptedDrops)
        }
        .buttonStyle(.plain)
        .pointerHover()
        .dropDestination(for: Block.self) { items, _ in
            guard let dropped = items.first else { return false }
            // A palette-origin block has no ID in the tree, so this is a
            // no-op for it (`BlockTree.removing` returns nil and
            // `delete` bails before touching undo). That is the right
            // outcome: throwing away a block you were carrying but never
            // placed just means not placing it.
            workspace.delete(dropped.id)
            // Bounces either way, including for that palette-origin block.
            // The tree may not have changed, but the child's answer to "what
            // happened to the thing I was holding?" is the same one, and the
            // can is what they were looking at when they let go.
            acceptedDrops += 1
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        // Both of its jobs, for a pointer.
        .help("Tap to delete every block, or drop one here to delete it")
        .accessibilityLabel("Delete All")
        .accessibilityHint("Deletes every block in the program. You can undo it.")
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
/// then parts to make room for it (#77). The trailing gap of an empty
/// repeat body renders as an explicit "drop here" zone instead.
struct DropGap: View {
    let address: BodyAddress
    let index: Int
    let workspace: WorkspaceEditor
    var isEmphasized = false

    @State private var isTargeted = false

    /// Targeted *and* able to do something (#98). A gap either side of the
    /// block being dragged, or one inside its own subtree, stays shut: the
    /// space a gap opens is a promise that a block will land there, and those
    /// drops land nothing. It is still a drop destination — leaving a hole in
    /// the tiling would bring back the pulsing #77 fixed — the drop is simply
    /// refused, as it always was.
    private var isOpen: Bool {
        isTargeted && acceptsDrop
    }

    /// Whether this gap can do anything at all with what is being carried.
    private var acceptsDrop: Bool {
        workspace.dropChangesTree(at: index, inBodyAt: address)
    }

    /// How far the rows part to show where the block will land (#77). Near a
    /// simple row's height, so the space that opens is the size of the thing
    /// that is about to fill it — the gap is the promise, not a hint.
    @ScaledMetric private var openHeight: CGFloat = 44
    /// What a closed gap reports to the `VStack` it sits in: the row-to-row
    /// margin, and nothing more (#21).
    @ScaledMetric private var closedFootprint: CGFloat = 10
    /// What a closed gap is *hit-tested* over — one row's pitch, so that the
    /// gaps tile the list with no dead ground between them (#77).
    ///
    /// At 24pt they did not: a row is around 44, so most of every row was
    /// ground where no gap was targeted at all. Dragging across the program
    /// then closed every gap and opened one again at each boundary, and the
    /// list pulsed the whole way down. Something has to be open at all times,
    /// and the way to get that is to leave nowhere that isn't a gap.
    @ScaledMetric private var closedHitHeight: CGFloat = 54

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
                                isOpen ? Color.accentColor : Color.secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 2, dash: [5])
                            )
                    }
                    .padding(.vertical, 2)
            }
            else {
                // No line in it. A 4pt accent capsule floating in 44pt of
                // opened space read as two different answers to the same
                // question — the space *is* the answer, and it is the size of
                // the block that will fill it.
                Color.clear
                    .frame(maxWidth: .infinity)
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
                    // Closed, this reports `closedFootprint` to the VStack
                    // while being hit-tested over a whole row's pitch (#21,
                    // #77) — the negative padding is what holds those two
                    // apart. Targeted, it opens for real: the rows below move
                    // down and the space is the size of a block. Reported
                    // height and hit area are the same number then, so the
                    // negative padding goes with them.
                    .frame(height: isOpen ? openHeight : closedHitHeight)
                    .padding(
                        .vertical,
                        isOpen ? 0 : -(closedHitHeight - closedFootprint) / 2)
            }
        }
        .contentShape(.rect)
        // Out of the way entirely when it can do nothing (#101). The system
        // puts a green ⊕ on the preview over any drop destination and never
        // asks whether the drop would achieve anything, so a gap that refuses
        // the block was still promising to take it — the badge said yes while
        // the space stayed shut.
        //
        // This is the hole in the tiling that #77 warns about, and it is
        // harmless in exactly these places: nothing is meant to open there, so
        // nothing being targeted there changes nothing. Move out of the band
        // and the next gap opens as usual.
        // iPadOS only, and not for want of trying: macOS routes drop targeting
        // somewhere hit testing does not reach, and `.disabled(_:)` does not
        // reach it either — both were built and watched on a Mac, and the
        // badge stayed. The lever Apple means for this is `isEnabled` on the
        // `dropDestination` that replaces ours (#99), which has no `isTargeted`
        // and so cannot be adopted without answering what drives the parting.
        // Until then the Mac shows a ⊕ over a gap that will refuse the block —
        // cosmetic, and the refusal itself has always been correct.
        .allowsHitTesting(acceptsDrop)
        .dropDestination(for: Block.self) { items, _ in
            guard let block = items.first else { return false }
            return workspace.handleDrop(block, at: index, inBodyAt: address)
        } isTargeted: {
            isTargeted = $0
        }
        // Reduce Motion switches the travel off, not the gap: where the block
        // is going has to be visible either way.
        .motion(Motion.dropGap, value: isOpen)
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

    /// The row's content width, for the drag preview on iPadOS (#95). macOS
    /// hands a preview the source view's size and `maxWidth` alone is enough;
    /// iPadOS proposes nothing, so a floor has to come from somewhere. It
    /// constrains a *different* view than the one it measures — a measurement
    /// fed back into its own size is the infinite layout loop.
    @State private var contentWidth: CGFloat = 0

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
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                contentWidth = $0
            }
            .blockChrome(block.kind.category, isHighlighted: isHighlighted)
            // The block without the furniture (#75). The default preview is a
            // snapshot of the row, which carries the ⋯ and the empty space the
            // spacer was holding for it — a picture of a row rather than the
            // block inside it. This is the same label in the same chrome, at
            // the size of its own content.
            //
            // The chip style has to be named here: it is applied ambiently to
            // the block list, and a drag preview is rendered outside that
            // hierarchy, where the chips would fall back to `.bordered` and
            // stop looking like the ones you were just looking at.
            .draggable(workspace.dragging(block)) {
                SimpleBlockLabel(
                    kind: block.kind, usedVariableNames: usedVariableNames,
                    usedFunctionNames: usedFunctionNames
                ) { _ in }
                .buttonStyle(WorkspaceChipButtonStyle())
                // `maxWidth` is what matches the row on macOS, where a preview
                // is proposed the source's size; `minWidth` is what matches it
                // on iPadOS, where nothing is proposed and the greedy frame
                // falls back to the content (#95). Neither alone covers both.
                .frame(
                    minWidth: contentWidth > 0 ? contentWidth : nil,
                    maxWidth: .infinity, alignment: .leading
                )
                .blockChrome(block.kind.category)
                // Where the block ends (#93). iPadOS composites a preview onto
                // an opaque backing and fills whatever the snapshot leaves
                // transparent, so the rounded corners came up white. It is
                // named here rather than inside `blockChrome`, which the real
                // rows wear too: a shape declared there reaches the *whole*
                // preview, and on a container that is the header's rectangle —
                // which clips the spine and the foot off the C.
                .contentShape(.dragPreview, RowCorners.standalone.shape)
            }
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
    /// The whole C's width, for the drag preview — see `BlockRowView` (#95).
    @State private var containerWidth: CGFloat = 0
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
    /// How far past the header a dragged container is allowed to show (#102):
    /// the mouth's leading gap, and then half of the first child.
    ///
    /// The cap was 220 at first — a guard against a deep container being
    /// taller than the screen — and that was the wrong quantity to pick. What
    /// matters is not how much fits but where the *header* ends up, because
    /// the header is what was grabbed: macOS holds a preview by its centre, so
    /// at 220 the block hung more than a hundred points from the pointer
    /// carrying it. iPadOS anchors nearer the top and hid that entirely.
    ///
    /// A multiple of the header was the next wrong answer. Header heights
    /// differ by platform — the macOS body size is 13pt against iOS's 17 — so
    /// the same multiple leaves a different amount showing, and what shows
    /// first is not a block at all but the mouth's own `DropGap`. Measuring
    /// the header and adding a fixed glimpse is the quantity that means
    /// something: enough to see a child hanging there, on both.
    @ScaledMetric private var previewGlimpse: CGFloat = 32
    /// Until the header has been measured. Near a macOS header plus the
    /// glimpse; only ever used for the frame or two before the real number
    /// arrives.
    @ScaledMetric private var previewHeightFallback: CGFloat = 76
    /// The rendered height of this container's header, measured (#102).
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        // Spacing 0: the arms have to meet. What separates the header from the
        // first child is the mouth's own leading `DropGap`, which is also what
        // separates any two sibling rows.
        VStack(alignment: .leading, spacing: 0) {
            headerArm
                .blockChrome(
                    block.kind.category, corners: headerCorners,
                    isDropTargeted: isReceiving
                )
                .measuringHeight(into: $headerHeight)
                // The whole block, children and all (#87). Dropping it moves the
                // whole container — mouths, children and foot — so that is what it
                // should look like in the air. It was the header alone in #75, on
                // the argument that a subtree is a lot to hang off one finger;
                // judged in the running app, a hat that leaves its body behind
                // reads as though the body is staying put.
                //
                // Read-only, through the flag the visionOS viewer already needed
                // (#53): the ⋯ and the mouths' "add here" toggles take themselves
                // off, so nothing that cannot be pressed is drawn.
                .draggable(workspace.dragging(block)) {
                    containerShape
                        .buttonStyle(WorkspaceChipButtonStyle())
                        .environment(\.showsBlockEditing, false)
                        .frame(
                            minWidth: containerWidth > 0 ? containerWidth : nil,
                            maxWidth: .infinity, alignment: .leading
                        )
                        // A card, because a C cannot be described as one shape
                        // (#93). iPadOS fills whatever a preview leaves
                        // transparent, and for a container that is the header's
                        // and foot's outer corners — the mouth, oddly, comes out
                        // right. There is no shape to hand `contentShape` that
                        // covers the arms and skips the mouth: the C is drawn
                        // additively from three pieces and its header's height
                        // is not known anywhere a `Shape` could read it.
                        //
                        // So the whole block goes on a surface instead, and the
                        // corners are the card's. The cost is the fade below:
                        // the system paints the named shape opaque, so the
                        // content dissolves into the card rather than into
                        // nothing. "More below" still reads; it just reads on a
                        // card.
                        .background(.background, in: previewCard)
                        .frame(maxHeight: previewHeightLimit, alignment: .top)
                        .clipped()
                        .mask(alignment: .top) { previewFade }
                        .contentShape(.dragPreview, previewCard)
                }
                .rowContextMenu(blockID: block.id, workspace: workspace)
                // The menu holds it, and a menu is reachable — but an action says
                // it out loud, the way Move Up / Move Down do.
                .accessibilityActions {
                    if let addElseAction {
                        Button("Add Otherwise", action: addElseAction)
                    }
                }
                // Dropping onto the header appends into this container's body.
                //
                // No `allowsHitTesting(acceptsDrop)` here, the way `DropGap`
                // has one (#101). This header is a drag *source* as well as a
                // destination, and taking it out of hit testing takes the drag
                // with it — and `draggedBlockID` outlives the drag that set it
                // (#98), so one drag of a container left that container and
                // every container inside it impossible to pick up again. The
                // ⊕ over your own header is the price; the arms stay put, and
                // the drop was always refused anyway.
                .dropDestination(for: Block.self) { items, _ in
                    guard let dropped = items.first else { return false }
                    return workspace.handleDrop(
                        dropped, at: childBlocks.count,
                        inBodyAt: BodyAddress(containerID: block.id))
                } isTargeted: {
                    isDropTargeted = $0
                }

            bodyArms
        }
        .motion(Motion.dropGap, value: isReceiving)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            containerWidth = $0
        }
    }

    /// What the spine and the foot are painted with: the same answer the
    /// header gives while a drag is over it (#78), so the C changes as one
    /// shape rather than one arm at a time. A scan down the spine has to read
    /// as an unbroken run of colour in either state.
    private var armColor: Color {
        isReceiving ? block.kind.category.dropFill : block.kind.category.color
    }

    /// Targeted *and* able to do anything about it (#78, extending #98). A
    /// container dragged over its own header is being offered to itself, and
    /// the tree refuses that — so the arms stay put rather than promising to
    /// open. The gaps learned this first; the header is the other drop target
    /// in a container and had been left out.
    private var isReceiving: Bool { isDropTargeted && acceptsDrop }

    /// Whether dropping what is being carried into this container's body would
    /// change anything.
    private var acceptsDrop: Bool {
        workspace.dropChangesTree(
            at: childBlocks.count, inBodyAt: BodyAddress(containerID: block.id))
    }

    /// The C with nothing attached: the same pieces the body assembles, in the
    /// same order, for the drag preview to render. The header wears its chrome
    /// here because the body wears a *stateful* version of it — the
    /// drop-target fill — which a preview has no business showing.
    private var containerShape: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerArm
                .blockChrome(block.kind.category, corners: headerCorners)
            bodyArms
        }
    }

    /// The surface a dragged container sits on — the silhouette the block
    /// already had, rather than a new one.
    ///
    /// Its top corners are the *header's*, which is the whole point: they were
    /// a flat 10 at first, and a definition's hat is 20 (#14), so dragging one
    /// showed a crescent of card between the block's curve and the card's — the
    /// white corner #93 had just taken off every other block. The bottom is the
    /// foot's, though the height cap usually cuts before it.
    ///
    /// Not `static`: this type is generic over its header, and a generic type
    /// cannot hold a stored one.
    private var previewCard: UnevenRoundedRectangle {
        .rect(
            cornerRadii: RectangleCornerRadii(
                topLeading: headerCorners.radii.topLeading,
                bottomLeading: RowCorners.containerFoot.radii.bottomLeading,
                bottomTrailing: RowCorners.containerFoot.radii.bottomTrailing,
                topTrailing: headerCorners.radii.topTrailing))
    }

    /// How tall the preview is allowed to be: the header as measured, plus the
    /// glimpse below it.
    private var previewHeightLimit: CGFloat {
        headerHeight > 0 ? headerHeight + previewGlimpse : previewHeightFallback
    }

    /// Opaque through the header and most of the glimpse, then out. The fade
    /// has to mean "there is more", so it may not reach the header — a faded
    /// header would read as the block itself being faint — and it may not take
    /// the whole glimpse either, or there is nothing left to glimpse.
    private var previewFade: some View {
        let opaque = (headerHeight + previewGlimpse * 0.55) / previewHeightLimit
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: min(max(opaque, 0), 1)),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// The top arm's contents. `InsertionTargetButton` and `RowControls` take
    /// themselves off when `showsBlockEditing` is false, which is what lets
    /// the preview reuse this instead of keeping a stripped copy in step.
    private var headerArm: some View {
        HStack(spacing: headerSpacing) {
            header
            InsertionTargetButton(
                address: BodyAddress(containerID: block.id), workspace: workspace)
            Spacer(minLength: 0)
            RowControls(
                blockID: block.id, workspace: workspace, addElseAction: addElseAction)
        }
    }

    /// Everything below the header: the mouth, the else mouth if there is one,
    /// and the foot that closes the shape.
    @ViewBuilder private var bodyArms: some View {
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
            .fill(armColor)
            .frame(height: foot)
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
                    .fill(armColor)
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
                // See `RowControls.editingMenu`: the tint below belongs to the
                // glyph, and a menu hands its tint to the popup as well.
                removeButton
                    .tint(nil)
            } label: {
                // Inside the label, for the reason `RowControls` gives.
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .touchTarget()
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .blockMenuInk()
        }
        .blockChrome(
            BlockCategory.control, corners: .containerDivider,
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

    @Environment(\.showsBlockEditing) private var showsBlockEditing

    private var isTarget: Bool { workspace.insertionTarget == address }

    var body: some View {
        // Gone entirely when the program is only being read (#53). This is the
        // palette's aim, and a viewer has no palette to aim.
        if showsBlockEditing {
            targetToggle
        }
    }

    private var targetToggle: some View {
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

    @Environment(\.showsBlockEditing) private var showsBlockEditing

    var body: some View {
        // Absent, not disabled, where the program is only being read (#53):
        // the visionOS viewer's constant document binding already makes this
        // menu incapable of changing anything, and a control that looks
        // pressable and does nothing is worse than no control.
        if showsBlockEditing {
            editingMenu
        }
    }

    private var editingMenu: some View {
        Menu {
            // The popup keeps the system's own colours. `blockMenuInk()` below
            // is a *tint*, and a tint reaches a menu's items as well as its
            // glyph — which put a fixed near-black (#41) on macOS's dark menu
            // background. Resetting it here is what lets the glyph keep the
            // ink it needs against a pastel block.
            Group {
                Button("Move Up", systemImage: "chevron.up") {
                    workspace.move(blockID, by: -1)
                }
                Button("Move Down", systemImage: "chevron.down") {
                    workspace.move(blockID, by: 1)
                }
                if let addElseAction {
                    Button(
                        "Add Otherwise", systemImage: "arrow.triangle.branch",
                        action: addElseAction
                    )
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
            }
            .tint(nil)
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
        .blockMenuInk()
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

    /// The outline itself, for the places that need a `Shape` rather than the
    /// radii — the block chrome's fill, and the drag preview's own shape.
    var shape: UnevenRoundedRectangle { .rect(cornerRadii: radii) }

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
    let category: BlockCategory
    var corners: RowCorners = .standalone
    var isHighlighted = false
    var isDropTargeted = false

    @Environment(\.colorScheme) private var scheme

    private var shape: UnevenRoundedRectangle { corners.shape }

    /// The ring *does* follow the appearance, where the fill and the label
    /// don't. Its job is to stand out against two things at once — the pastel
    /// inside it and the pane outside — and which of black or white manages
    /// that is exactly what the appearance decides. White vanished into the
    /// pastel in light mode; ink would read as a gap against a dark pane.
    private var ring: Color { scheme == .dark ? .white : BlockCategory.ink }

    /// How far the running block lifts (#78). Small on purpose: a row is over
    /// 400pt wide, so a percent of it is several points sideways — enough to
    /// read as a lift, and past a few percent the row starts shouldering into
    /// the column's edges.
    private static let highlightScale: CGFloat = 1.03

    func body(content: Content) -> some View {
        content
            .foregroundStyle(BlockCategory.ink)
            .rowShape()
            .background(isDropTargeted ? category.dropFill : category.color, in: shape)
            // No ring at all any more (#78). It marked the running block at
            // 3pt — a hard dark outline snapping from row to row ten times a
            // second, the loudest thing on a screen whose whole point is
            // watching a drawing appear — and it marked a drop target at 2,
            // where it read as something arriving from outside the block
            // rather than as the block answering. Running is a lift below;
            // being dropped into is the fill above.
            // Running is a lift instead: a little larger, with the shadow it
            // already had. `scaleEffect` is a transform, so the row grows
            // without moving its neighbours or costing a layout pass — which
            // matters at ten a second.
            //
            // The fill is still left alone, and that is the older rule (#41).
            // State used to add `.brightness`, a filter over the composited
            // row: it moved the card *and* its label the same way, and the
            // label is already white, so only the card travelled — toward the
            // text. Highlighting made a row harder to read the more it was
            // highlighted; in dark mode the green went 1.92:1 to 1.24:1 the
            // moment it started running. Scale cannot do that to a label.
            .scaleEffect(isHighlighted ? Self.highlightScale : 1)
            .shadow(color: ring.opacity(isHighlighted ? 0.5 : 0), radius: 6)
            .motion(Motion.highlight, value: isHighlighted)
            .motion(Motion.dropGap, value: isDropTargeted)
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
    /// Reports this view's rendered height into `height`.
    ///
    /// A `GeometryReader` in the background, rather than
    /// `onGeometryChange(for:of:action:)` — which is the modifier for this and
    /// **does not report the rendered geometry inside the workspace column**.
    /// Measured against each other on the same view, on macOS, the modifier
    /// said 159 for a header the reader put at 44 and a ruler confirmed at ~45
    /// (#102); the same modifier under-reports *width* there too (#95, 359
    /// against a row drawing 408). Why is unknown. The reader is right on both
    /// platforms, and that is what this uses.
    fileprivate func measuringHeight(into height: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, new in
                        height.wrappedValue = new
                    }
            }
        }
    }
}

extension View {
    fileprivate func blockChrome(
        _ category: BlockCategory, corners: RowCorners = .standalone, isHighlighted: Bool = false,
        isDropTargeted: Bool = false
    ) -> some View {
        modifier(
            BlockChrome(
                category: category, corners: corners, isHighlighted: isHighlighted,
                isDropTargeted: isDropTargeted))
    }
}

extension EnvironmentValues {
    /// Whether block rows draw the controls that *change* the program — the
    /// row menu (⋯) and the container mouths' "add here" target toggle.
    ///
    /// True everywhere the workspace is an editor, and false in the visionOS
    /// viewer's program window (#53), which shows the same rows for reading
    /// only. It is an environment value rather than a parameter because the
    /// two views that read it sit several layers below the one that knows —
    /// threading a flag through `BlockListView`, `BlockRowView` and
    /// `ContainerBlockRow` would put an argument on every one of them for the
    /// benefit of two leaves.
    ///
    /// Hiding is not what enforces read-only — a constant document binding is
    /// (see `ProgramWindow`). This is about not *offering* what cannot happen.
    @Entry var showsBlockEditing = true
}

extension View {
    /// The ⋯ glyph's colour, on the two menus a block row can carry.
    ///
    /// Every row this appears on is a filled pastel block, so the glyph takes
    /// the same fixed near-black the label does (#41) rather than the system
    /// accent — white on a pastel is the control nobody can see.
    ///
    /// It is a `tint` because that is what a `borderless` menu reads for its
    /// label; `foregroundStyle` on the label is ignored there, which is how the
    /// first attempt at this ended up with a white ⋯ in dark mode. The cost is
    /// that the tint reaches the *popup* too, so each menu's content resets it
    /// with `.tint(nil)` — a fixed dark ink is right against a pastel block and
    /// wrong against macOS's dark menu background, which is the whole of the
    /// bug this pair exists to hold apart.
    fileprivate func blockMenuInk() -> some View {
        tint(BlockCategory.ink)
    }
}
