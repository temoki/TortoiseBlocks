#if os(visionOS)

    import SwiftUI
    import TortoiseBlocksKit

    /// The visionOS viewer's one window (#53) — **controls only**.
    ///
    /// The drawing is never here. It lives on the table, in the immersive
    /// space, and that is the whole reason this platform gets an app of its
    /// own: a second flat copy in the window would put the same picture in two
    /// places and take the reason away with it. So this window is what a
    /// remote control is: pick a drawing, put it down, play it.
    ///
    /// There is no editing anywhere in it. That is not a feature that was cut
    /// — text entry and precise dragging are worse in a headset than on an
    /// iPad in every respect, and being read-only is what lets the whole
    /// `DocumentGroup` apparatus go, taking with it the two visionOS problems
    /// that #52 could not solve (no way back to the browser, and the
    /// view-switching residue).
    struct ViewerWindow: View {
        let model: ViewerModel

        @Environment(\.openImmersiveSpace) private var openSpace
        @Environment(\.dismissImmersiveSpace) private var dismissSpace

        @State private var showsImporter = false

        var body: some View {
            @Bindable var model = model
            VStack(spacing: 24) {
                DrawingChooser(model: model, showsImporter: $showsImporter)

                if model.hasProgram {
                    PlaybackControls(
                        blocks: model.blocks, runner: model.runner,
                        isStale: model.runner.isStale(comparedTo: model.blocks)
                    )
                    TablePlacementControls(model: model, place: place)
                }
                else {
                    ContentUnavailableView(
                        "No Drawing", systemImage: "photo.on.rectangle.angled",
                        description: Text("Open a drawing, or start from a sample."))
                }
            }
            .padding(28)
            // A fixed width and *no* height at all. The window sizes itself to
            // this content (`windowResizability(.contentSize)`), so leaving the
            // height to the content is what stops the empty band under the
            // controls — a remote control should be exactly as tall as its
            // buttons, and it grows by itself when a drawing brings the
            // transport with it. The width is held because the scrubber has no
            // opinion of its own and would otherwise collapse toward the
            // widest label.
            .frame(width: 520)
            .fileImporter(
                isPresented: $showsImporter, allowedContentTypes: [.tortoiseBlocksProject]
            ) { result in
                if case .success(let url) = result { model.open(url) }
            }
            .alert(
                "Can't Open This",
                isPresented: Binding(
                    get: { model.openFailure != nil },
                    set: { if !$0 { model.openFailure = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.openFailure ?? "")
            }
            .task {
                // Development only: the simulator cannot press any of these
                // buttons (simctl sends no input), so `-TBPlace YES` loads a
                // sample and puts it down at launch. It is the only way to see
                // the immersive space without a headset on.
                guard UserDefaults.standard.bool(forKey: "TBPlace"), !model.hasProgram else {
                    return
                }
                model.load(SampleBlocks.spiral(), title: String(localized: "Spiral"))
                model.sitsOnTable = false
                await place()
            }
        }

        private func place() async {
            if model.isPlaced {
                await dismissSpace()
                model.isPlaced = false
            }
            else if case .opened = await openSpace(id: ViewerModel.spaceID) {
                model.isPlaced = true
            }
        }
    }

    /// Which drawing is on the table: a file, or one of the four samples the
    /// iPad and Mac workspace already offers.
    ///
    /// The samples are not a convenience — they are what stops a viewer with
    /// no files from being an empty app. Documents live in the app's own
    /// folder on whichever device made them, so a Vision Pro starts with none
    /// until something is AirDropped to it. `SampleBlocks` is already public
    /// and already what 「みほん」 uses, so this needs no bundled resources and
    /// no second set of names.
    private struct DrawingChooser: View {
        let model: ViewerModel
        @Binding var showsImporter: Bool

        var body: some View {
            VStack(spacing: 12) {
                // Verbatim on both sides: a file's name is the user's own text,
                // and the app name mirrors CFBundleDisplayName, which is
                // "Tortoise Blocks" in every language — localizing either would
                // put something in the string catalog that must never be
                // translated (the same reason `LaunchScene` says it verbatim).
                Text(verbatim: model.title.isEmpty ? "Tortoise Blocks" : model.title)
                    .font(.title)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Button("Open", systemImage: "folder") {
                        showsImporter = true
                    }
                    Menu {
                        // "Sample" is said once, over the list, rather than at
                        // the head of all four names — the same reasoning as
                        // the workspace's own menu.
                        SampleItem("🟦", "Filled Square", SampleBlocks.filledSquare, model)
                        SampleItem("⭐️", "Star", SampleBlocks.star, model)
                        SampleItem("🌀", "Spiral", SampleBlocks.spiral, model)
                        SampleItem("🌳", "Tree", SampleBlocks.fractalTree, model)
                    } label: {
                        Label("Samples", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// One sample entry. Takes the block-builder rather than the blocks so the
    /// program is only built when it is chosen — four sample trees built on
    /// every redraw of the menu's label would be four for nothing.
    private struct SampleItem: View {
        let icon: String
        /// A `LocalizedStringResource` rather than a `LocalizedStringKey`
        /// because this name is needed twice — as the menu entry, and as the
        /// title the window then shows — and only a resource can be both drawn
        /// and resolved to a `String`. Same reason the palette's titles are
        /// resources: a plain `String` there would skip localization outright.
        let title: LocalizedStringResource
        let build: () -> [Block]
        let model: ViewerModel

        init(
            _ icon: String, _ title: LocalizedStringResource, _ build: @escaping () -> [Block],
            _ model: ViewerModel
        ) {
            self.icon = icon
            self.title = title
            self.build = build
            self.model = model
        }

        var body: some View {
            Button {
                model.load(build(), title: String(localized: title))
            } label: {
                // The emoji is `verbatim` and separate from the title, so the
                // string catalog stays free of it.
                Label {
                    Text(title)
                } icon: {
                    Text(verbatim: icon)
                }
            }
        }
    }

    /// Putting the sheet down, and the two things about where it lands that
    /// are worth a control rather than a gesture.
    private struct TablePlacementControls: View {
        let model: ViewerModel
        let place: () async -> Void

        var body: some View {
            @Bindable var model = model
            VStack(spacing: 14) {
                Button(
                    model.isPlaced ? "Put Away" : "Place on Table",
                    systemImage: model.isPlaced ? "xmark.circle" : "table.furniture"
                ) {
                    Task { await place() }
                }
                .buttonStyle(.borderedProminent)

                // Size, spin and position are gestures on the sheet itself —
                // there is nothing here for them. What is left is the choice a
                // gesture cannot make (whether to look for a table at all) and
                // the way back from having dragged the drawing out of reach.
                HStack(spacing: 16) {
                    Toggle("Sit on a Table", isOn: $model.sitsOnTable)
                        .toggleStyle(.switch)
                        .fixedSize()
                    Button("Reset Position", systemImage: "arrow.counterclockwise") {
                        model.resetPlacement()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!model.isPlaced)
                }
                .font(.callout)

                Text("Pinch to resize, twist to turn, drag to move.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

#endif
