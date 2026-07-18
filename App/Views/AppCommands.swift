import SwiftUI
import TortoiseBlocksKit
import UniformTypeIdentifiers

/// `.commands` is evaluated at the Scene level, one level above any single
/// document window, so the per-window `RunnerModel` has to be threaded
/// through `@FocusedValue` — `ContentView` publishes it via
/// `.focusedSceneValue`, and this menu reads it back. When no document
/// window is focused, `runner` is nil and every item disables itself.
extension FocusedValues {
    @Entry var runner: RunnerModel?
    @Entry var workspaceBlocks: [Block]?
}

/// Run / pause / step / export, wired to the front document window only.
struct TortoiseBlocksCommands: Commands {
    @FocusedValue(\.runner) private var runner
    @FocusedValue(\.workspaceBlocks) private var workspaceBlocks

    var body: some Commands {
        CommandMenu("Run") {
            Button("Run") {
                runner?.run(workspaceBlocks ?? [])
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(runner == nil || (workspaceBlocks ?? []).isEmpty)

            Button(runner?.player.isPaused == true ? "Resume" : "Pause") {
                runner?.player.isPaused.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(runner == nil)

            Button("Step") {
                runner?.player.step()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            .disabled(runner?.player.isPaused != true)
        }
        CommandGroup(after: .importExport) {
            // Just sets pendingExport; CanvasPane owns the actual
            // fileExporter and clears it back to nil once handled.
            Button("Export SVG…") {
                runner?.pendingExport = .svg
            }
            .disabled(runner == nil || runner?.canExport != true)

            Button("Export PNG…") {
                runner?.pendingExport = .png
            }
            .disabled(runner == nil || runner?.canExport != true)
        }
    }
}
