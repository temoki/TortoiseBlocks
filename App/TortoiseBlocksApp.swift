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

        // The custom launch screen (#32). `DocumentGroupLaunchScene` is
        // unavailable on macOS and SwiftUI has no empty `Scene` to return in
        // its place, so this `#if` can't hide inside a modifier the way the
        // ones in `PlatformModifiers` do.
        #if os(iOS)
            LaunchScene()
        #endif
    }
}
