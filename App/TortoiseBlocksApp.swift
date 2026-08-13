import SwiftUI

@main
struct TortoiseBlocksApp: App {
    // Phase 0 spike (#53) — the immersive space is its own Scene and cannot
    // see the document's RunnerModel, so the two meet here. Delete with
    // `TableSpike.swift`.
    #if os(visionOS)
        @State private var tableSpike = TableSpikeModel()
    #endif

    var body: some Scene {
        // Phase 0 spike (#53) — first in the body so `-TBSpike YES` can take
        // the launch off the DocumentGroup. Suppressed without the flag, so a
        // normal launch is unchanged. Delete with `TableSpike.swift`.
        #if os(visionOS)
            WindowGroup(id: "table-spike-launcher") {
                TableSpikeLauncher()
                    .environment(tableSpike)
            }
            .defaultLaunchBehavior(TableSpikeModel.autoOpens ? .presented : .suppressed)
            // Small, so it does not stand in front of the thing being looked at.
            .defaultSize(width: 320, height: 140)
        #endif

        DocumentGroup(newDocument: BlocksDocument()) { file in
            ContentView(document: file.$document)
                #if os(visionOS)
                    .environment(tableSpike)
                #endif
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

        // Phase 0 spike (#53) — delete with `TableSpike.swift`.
        #if os(visionOS)
            ImmersiveSpace(id: TableSpikeModel.spaceID) {
                TableSpikeSpace()
                    .environment(tableSpike)
            }
            .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}
