import SwiftUI

#if os(visionOS)
    /// Which side of the remote a window opens on.
    ///
    /// An enum rather than passing `WindowPlacement.Position.leading` around:
    /// those are static *methods* taking the window to be beside, so they
    /// cannot be named without one, and the whole point here is to name the
    /// side before the window is known to be open.
    private enum WindowSide {
        case leading
        case trailing
    }

    /// A placement beside the window with `id` — or the system's own choice
    /// when there is no such window to be beside, which is what a restored
    /// window meets when it comes back before the remote does.
    private func placement(
        _ side: WindowSide, of id: String, in context: WindowPlacementContext
    ) -> WindowPlacement {
        guard let relative = context.windows.first(where: { $0.id == id }) else {
            return WindowPlacement()
        }

        switch side {
        case .leading: return WindowPlacement(.leading(relative))
        case .trailing: return WindowPlacement(.trailing(relative))
        }
    }
#endif

@main
struct TortoiseBlocksApp: App {
    // The viewer's whole state, shared by its two scenes (#53). One `Scene`
    // cannot see another's, and the window and the table are exactly that
    // split: controls here, drawing there.
    #if os(visionOS)
        @State private var viewer = ViewerModel()
    #endif

    var body: some Scene {
        // **visionOS is a viewer, not the editor** (#53), so its scene tree is
        // a different tree rather than the same one with adjustments.
        //
        // No `DocumentGroup`: a `.fileImporter` in a plain window opens a
        // drawing in one press, which is exactly what #52 could never make a
        // DocumentGroup do there — `dismiss()` only reveals the system's own
        // 「書類」 button, and `openDocument` / `newDocument` are unavailable on
        // the platform. Dropping the apparatus drops the editing UI with it,
        // and that is what makes a visionOS build worth having at all instead
        // of an iPad app in a window.
        #if os(visionOS)
            WindowGroup(id: ViewerModel.remoteWindowID) {
                ViewerWindow(model: viewer)
            }
            // The window is its contents, not a canvas they sit in — so no
            // `defaultSize`, which left a band of empty glass under the
            // controls on device. It shrinks to the "no drawing" state and
            // grows when a drawing brings the transport with it.
            .windowResizability(.contentSize)

            // The program, on a surface of its own (#53). A separate window
            // rather than a pane, because that is the version of this idea the
            // iPad cannot give: the blocks and the drawing at full size at the
            // same time, with nothing to switch between.
            WindowGroup(id: ViewerModel.programWindowID) {
                ProgramWindow(model: viewer)
            }
            .defaultSize(width: 480, height: 700)
            // **Beside the remote, not on top of it.** Left the system opens
            // every window in the same place — straight ahead — so asking for
            // the program put it over the controls that asked, and asking for
            // the code put it over both. Three surfaces at once is the entire
            // argument for this platform (#53), and stacking them is the one
            // arrangement that does not deliver it.
            //
            // Reading order decides which side: the blocks are what the
            // drawing is made *from*, so they sit to the left of the remote,
            // and the code — what the blocks become — to its right. On
            // visionOS a placement can only name another window and a side;
            // the absolute initialisers are all unavailable there, which is
            // exactly enough for this and nothing more.
            .defaultWindowPlacement { _, context in
                placement(.leading, of: ViewerModel.remoteWindowID, in: context)
            }

            // And the code on a third (#53 Phase 3). Same reasoning one step
            // further: iPad and Mac make the canvas and the code two states of
            // one toggle because a window holds one of them, and a headset
            // never has to choose.
            WindowGroup(id: ViewerModel.codeWindowID) {
                CodeWindow(model: viewer)
            }
            // Wider than the program's 480: source lines are longer than block
            // rows, and the pane scrolls horizontally rather than wrapping.
            .defaultSize(width: 620, height: 700)
            .defaultWindowPlacement { _, context in
                placement(.trailing, of: ViewerModel.remoteWindowID, in: context)
            }

            ImmersiveSpace(id: ViewerModel.spaceID) {
                TableCanvasSpace(model: viewer)
            }
            .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #else
            DocumentGroup(newDocument: BlocksDocument()) { file in
                ContentView(document: file.$document)
            }
            .commands {
                TortoiseBlocksCommands()
            }
            // A default worth having anyway — three panes need room, and macOS
            // otherwise opens something narrower than the palette, workspace
            // and canvas want. It is also exactly the App Store's macOS
            // screenshot size: a Retina backing scale of 2 makes 1280×800pt
            // capture as 2560×1600px, so a window at its default size needs no
            // cropping or resampling. Only a default — macOS restores a
            // window's saved frame in preference to it, so a capture wants that
            // state cleared first.
            .defaultWindowSize()

            // The custom launch screen (#32) — iPadOS only. It is
            // `DocumentGroupLaunchScene`, so it has nothing to attach to on the
            // platform with no DocumentGroup, and nothing to do on macOS, which
            // keeps the standard open panel. (It never appeared on visionOS
            // even while that platform had a DocumentGroup: the system document
            // browser is shown straight away there.)
            #if os(iOS)
                LaunchScene()
            #endif
        #endif
    }
}
