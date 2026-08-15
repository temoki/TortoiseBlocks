import SwiftUI

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
            WindowGroup {
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
