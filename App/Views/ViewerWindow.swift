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
        @Environment(\.openWindow) private var openWindow

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
            // **Opening a drawing puts it down.** The viewer has exactly one
            // job, so choosing a drawing and then being asked where to put it
            // is a question with one sensible answer — and until it is
            // answered the room stays empty and nothing on screen says why,
            // which reads as an app that did not open the file. An alert
            // ("shall I put it on the table?") was the other candidate and
            // fails for the same reason twice over: a modal whose answer is
            // always yes, stacked in front of the world-sensing prompt that
            // the first placement already brings with it.
            //
            // It stays an ordinary *placement*, not a special case. The picker
            // below moves to wherever this put it and 「ださない」 takes it
            // away again, so nothing here is a state the wearer cannot get
            // out of. Opening a second drawing while one is already out
            // changes what is on the sheet and leaves the sheet where it was
            // dragged to — `place` sees the drawing is already there and
            // returns.
            .onChange(of: model.loadGeneration) {
                Task { await place(model.sitsOnTable ? .table : .inFront) }
            }
            .task {
                // Development only: the simulator cannot press any of these
                // buttons (simctl sends no input), so the launch arguments
                // stand in for the hands.
                //
                //   -TBPlace YES      load a sample, open the program window,
                //                     put the drawing down
                //   -TBSample <name>  square | star | spiral | tree
                //   -TBDraw <0…1>     run the drawing that far and stop
                //   -TBSheet s,r,d    the sheet's side, how far ahead of the
                //                     eyes it lands, and how far below them
                //
                // Without the first one a simulator run is a window of buttons
                // nobody can reach, and the immersive space never opens at all.
                // The other two exist because App Store screenshots are shot
                // here rather than on a headset: a real room cannot be framed
                // the same way twice and is somebody's home besides, while
                // these four arguments describe a picture exactly.
                //
                // `-TBSheet` is the framing one, and it exists because
                // nothing in the simulator can reach out and pinch the sheet
                // bigger or drag it further off. It moves the two constants
                // the placement is built from — reach and drop — rather than
                // the position they produce, so a forced framing still lands
                // in front of the camera and turned to face it.
                //
                // Worth knowing, since it was got wrong first: the simulator
                // *does* report a usable head pose, so placement takes the
                // aimed branch here exactly as a headset does, and an override
                // written against the no-pose fallback silently does nothing.
                //
                // **The simulator does show the drawing.** This comment said
                // the opposite for a while, and the mistake is worth recording
                // rather than quietly deleting: what was actually broken was
                // that `-TBPlace` placed by calling `place(.inFront)` *after*
                // the load, which flipped `sitsOnTable` and so changed the
                // `.id()` on the immersive space's `RealityView` — tearing the
                // scene down and rebuilding it, with the attachment failing to
                // come back. The sheet stayed blank, `currentTortoiseState`
                // stayed nil, and that looked exactly like a platform that
                // hosts no `ViewAttachmentComponent`. Setting the preference
                // before the load leaves the id alone, and the paper, the
                // drawing and the tortoise all render.
                //
                // Read off the launch arguments rather than through
                // `UserDefaults`, which is where a `-flag value` pair normally
                // arrives. **`UserDefaults` is one of Apple's required-reason
                // APIs**, so touching it — even for a debug flag, even for a
                // read — obliges the app to ship a `PrivacyInfo.xcprivacy`
                // declaring `CA92.1`. This app has no privacy manifest and
                // needs none, which is a property worth keeping for one line:
                // nothing else here touches a required-reason API, and the
                // launch command is unchanged either way.
                let arguments = ProcessInfo.processInfo.arguments
                guard arguments.contains("-TBPlace"), !model.hasProgram else { return }

                // Loading is what places it now, so the destination is
                // chosen by setting the preference first. In front rather
                // than on a table because the simulator finds no planes at
                // all, and a table search there only spends its fifteen
                // seconds before falling back to exactly this.
                model.sitsOnTable = false
                if let framing = Self.framing(from: Self.value(of: "-TBSheet", in: arguments)) {
                    model.side = framing.side
                    model.framing = framing
                }
                let (blocks, title) = Self.sample(named: Self.value(of: "-TBSample", in: arguments))
                model.load(blocks, title: title)
                openWindow(id: ViewerModel.programWindowID)

                if let fraction = Self.value(of: "-TBDraw", in: arguments).flatMap(Double.init) {
                    await draw(upTo: fraction)
                }
            }
        }

        /// The value of a `-flag value` pair on the command line.
        private static func value(of flag: String, in arguments: [String]) -> String? {
            guard let flagIndex = arguments.firstIndex(of: flag),
                arguments.index(after: flagIndex) < arguments.endIndex
            else {
                return nil
            }
            return arguments[arguments.index(after: flagIndex)]
        }

        /// `side,reach,drop` in metres — how big the sheet is, how far ahead
        /// of the eyes it lands, and how far below them.
        ///
        /// All three or nothing: a partial list would leave some of the
        /// framing to a default and the rest to the argument, which is the one
        /// thing a reproducible capture cannot have.
        private static func framing(from value: String?) -> ViewerModel.Framing? {
            let numbers = (value ?? "").split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 3 else { return nil }

            return ViewerModel.Framing(
                side: numbers[0], reach: Float(numbers[1]), drop: Float(numbers[2]))
        }

        /// The sample `-TBSample` names, defaulting to the spiral.
        private static func sample(named name: String?) -> ([Block], String) {
            switch name?.lowercased() {
            case "square": (SampleBlocks.filledSquare(), String(localized: "Filled Square"))
            case "star": (SampleBlocks.star(), String(localized: "Star"))
            case "tree": (SampleBlocks.fractalTree(), String(localized: "Tree"))
            default: (SampleBlocks.spiral(), String(localized: "Spiral"))
            }
        }

        /// Draws `fraction` of the program and stops there.
        ///
        /// The seek cannot go out until the sheet's canvas has attached itself
        /// to the player: `TortoisePlayer.seek` is a no-op before that, and the
        /// attachment cannot happen until the immersive space has opened and
        /// its view has rendered. `currentTortoiseState` turning non-nil *is*
        /// that moment and there is nothing to await on, so this waits for it —
        /// with a deadline, since a run where the space never opens should end
        /// rather than spin.
        private func draw(upTo fraction: Double) async {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(20)
            while model.runner.player.currentTortoiseState == nil, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let commands = model.runner.lastRunCommands.count
            guard commands > 0 else { return }

            let clamped = min(max(fraction, 0), 1)
            model.runner.seek(to: Int((Double(commands - 1) * clamped).rounded()))
        }

        /// Moves the drawing to `destination`, opening or closing the
        /// immersive space as that requires.
        ///
        /// The table/in-front choice is set *before* the space opens, because
        /// the space reads it as it starts looking for somewhere to put the
        /// sheet. Changing it while already placed rebuilds the sheet and
        /// starts that search again, which is the intent — it is the wearer
        /// saying "not there, here".
        private func place(_ destination: ViewerModel.Placing) async {
            guard destination != model.placing else { return }
            guard destination != .away else {
                await dismissSpace()
                model.isPlaced = false
                return
            }
            model.sitsOnTable = destination == .table
            guard !model.isPlaced else { return }
            if case .opened = await openSpace(id: ViewerModel.spaceID) {
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
    ///
    /// **There is no export here, and that is the same decision as everything
    /// else this window leaves out** (#53). The viewer cannot change a drawing,
    /// so the file it was given is already the artifact; a second one written
    /// from it belongs where the drawing is *made*, which is the iPad and the
    /// Mac. It also kept a remote control down to the controls that place and
    /// play — the row had reached four buttons before this came out.
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

    /// Where the drawing goes, and the two other surfaces it can be seen on.
    ///
    /// **Grouped by what a control does, not by what it looks like** (#53).
    /// The row used to hold "put it on the table", "show blocks" and "show
    /// code" side by side, whose only shared property was being buttons: one
    /// was about placement and the other two opened windows, while placement's
    /// own mode switch and reset sat in a *different* row underneath, with
    /// those two wedged in between. Now placement is one group and the other
    /// surfaces are another, with a divider saying so.
    private struct TablePlacementControls: View {
        let model: ViewerModel
        let place: (ViewerModel.Placing) async -> Void

        var body: some View {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Where should the drawing go?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        PlacementPicker(placing: model.placing, place: place)
                        // Inline, icon-only, and last. Size, spin and position
                        // are gestures on the sheet itself, so all that is left
                        // for a control is the way back from having dragged the
                        // drawing out of reach — which is rare, and must not
                        // read as louder than the question above it. On its own
                        // row with a title it did exactly that.
                        Button("Reset Position", systemImage: "arrow.counterclockwise") {
                            model.resetPlacement()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .disabled(!model.isPlaced)
                    }
                }

                PlacementStatus(model: model)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                SurfaceToggles(model: model)
            }
        }
    }

    /// The one question the placement controls ask: where is the drawing?
    ///
    /// A picker rather than a button and a switch, because the answers are a
    /// closed set of three and naming them is clearer than composing them —
    /// see `ViewerModel.placing`. Selecting is asynchronous (opening an
    /// immersive space can fail, and does in a room that refuses world
    /// sensing), so the binding's setter starts the work and the picker
    /// follows whatever actually happened rather than what was asked for.
    private struct PlacementPicker: View {
        let placing: ViewerModel.Placing
        let place: (ViewerModel.Placing) async -> Void

        var body: some View {
            Picker(
                "Where should the drawing go?",
                selection: Binding(get: { placing }, set: { new in Task { await place(new) } })
            ) {
                Text("Away").tag(ViewerModel.Placing.away)
                Text("On a Table").tag(ViewerModel.Placing.table)
                Text("In Front of You").tag(ViewerModel.Placing.inFront)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// The other two surfaces this drawing can be shown on.
    ///
    /// **Toggles, not buttons**, so the control that opens a window can also
    /// close it. `openWindow` on a window that is already up only brings it
    /// forward, which made these a switch with one position — the way back was
    /// the window's own close button, somewhere else entirely. The windows
    /// report whether they are on screen (`ViewerModel.isProgramWindowOpen` /
    /// `isCodeWindowOpen`), since SwiftUI offers nothing to read that from.
    ///
    /// Short labels on purpose. Under a heading that has just said where the
    /// drawing goes, 「ブロック」 and 「コード」 are the two other things it can
    /// be, and "show" was a word every button in the row was already saying.
    private struct SurfaceToggles: View {
        let model: ViewerModel

        @Environment(\.openWindow) private var openWindow
        @Environment(\.dismissWindow) private var dismissWindow

        var body: some View {
            HStack(spacing: 12) {
                Toggle(
                    "Blocks", systemImage: "square.stack.3d.up",
                    isOn: binding(model.isProgramWindowOpen, ViewerModel.programWindowID))
                Toggle(
                    "Code", systemImage: "curlybraces",
                    isOn: binding(model.isCodeWindowOpen, ViewerModel.codeWindowID))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
        }

        private func binding(_ isOpen: Bool, _ id: String) -> Binding<Bool> {
            Binding(
                get: { isOpen },
                set: { $0 ? openWindow(id: id) : dismissWindow(id: id) })
        }
    }

    /// What the sheet is doing, under the placement controls.
    ///
    /// Finding a table takes **ten seconds or more** on device, and the sheet
    /// is deliberately not drawn until there is somewhere to put it — so
    /// without this the app spends that time looking broken. Saying what it is
    /// waiting for is the whole of the fix: a wait you understand is a wait,
    /// and a wait you don't is a bug.
    private struct PlacementStatus: View {
        let model: ViewerModel

        var body: some View {
            switch (model.isPlaced, model.placement) {
            // Nothing is out, so there is nothing to report and nothing to
            // pinch. The picker above has already said where the drawing is.
            case (false, _):
                EmptyView()
            case (_, .searching):
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Looking for a table…")
                }
            // Floating is two different things now that it can be *chosen*
            // (#53). Asking for a table and not getting one is news; asking for
            // the air and getting it is not, and telling someone their choice
            // failed when it did not is worse than saying nothing.
            case (_, .floating):
                Text(
                    model.sitsOnTable
                        ? "No table found, so it is floating in front of you."
                        : "Pinch to resize, twist to turn, drag to move.")
            case (_, .onTable):
                Text("Pinch to resize, twist to turn, drag to move.")
            }
        }
    }

#endif
