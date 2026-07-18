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
    }
}
