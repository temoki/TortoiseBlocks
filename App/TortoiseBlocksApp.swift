import SwiftUI

@main
struct TortoiseBlocksApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: BlocksDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            TortoiseBlocksCommands()
        }
        // A default worth having anyway — three panes need room, and macOS
        // otherwise opens something narrower than the palette, workspace and
        // canvas want. It is also exactly the App Store's macOS screenshot
        // size: a Retina backing scale of 2 makes 1280×800pt capture as
        // 2560×1600px, so a window at its default size needs no cropping or
        // resampling. Only a default — macOS restores a window's saved frame
        // in preference to it, so a capture wants that state cleared first.
        .defaultWindowSize()

        // The custom launch screen (#32). `DocumentGroupLaunchScene` is
        // unavailable on macOS and SwiftUI has no empty `Scene` to return in
        // its place, so this `#if` can't hide inside a modifier the way the
        // ones in `PlatformModifiers` do.
        #if !os(macOS)
            LaunchScene()
        #endif
    }
}
