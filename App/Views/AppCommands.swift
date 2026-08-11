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
    /// The front window's non-document editor state (#48). The menu only has
    /// to *ask* for the delete-everything confirmation; the workspace owns the
    /// dialog and does the deleting, so what travels here is this small
    /// observable rather than the `WorkspaceEditor` itself — a value type
    /// wrapping a `Binding`, which a focused value cannot carry.
    @Entry var workspaceUIState: WorkspaceUIState?
}

/// Run / pause / step / export, wired to the front document window only.
struct TortoiseBlocksCommands: Commands {
    @FocusedValue(\.runner) private var runner
    @FocusedValue(\.workspaceBlocks) private var workspaceBlocks
    @FocusedValue(\.workspaceUIState) private var workspaceUIState

    var body: some Commands {
        // Edit, after the pasteboard items, which is where a Mac user looks
        // for it. The can at the bottom of the workspace is the same command
        // (#48) and raises the same confirmation.
        CommandGroup(after: .pasteboard) {
            Button("Delete All", role: .destructive) {
                workspaceUIState?.confirmsDeleteAll = true
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(workspaceUIState == nil || (workspaceBlocks ?? []).isEmpty)
        }

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

            Button("Step Forward") {
                runner?.player.step()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            .disabled(runner?.canStep != true)

            Button("Step Back") {
                guard let runner else { return }
                runner.seek(to: runner.player.currentCommandIndex - 1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            .disabled(runner?.canStep != true || runner?.player.currentCommandIndex ?? -1 < 0)

            Button("Back to Start") {
                runner?.seek(to: -1)
            }
            .disabled(runner?.canStep != true)

            Divider()

            // The same action as the canvas's ⟳, down to the argument (#34):
            // same name, same result, wherever it is pressed. It replaced
            // "Clear", which looked identical on screen — both leave an empty
            // canvas — and differed only in state a child never sees.
            // Enabled by the blocks, not by `commandCount`: rolling a first
            // set of dice is exactly what this is for.
            Button("Roll Again") {
                runner?.run(workspaceBlocks ?? [], startPaused: true)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(runner == nil || (workspaceBlocks ?? []).isEmpty)

            Button("Copy Code") {
                copyCodeToPasteboard(SwiftCodeGenerator.code(for: workspaceBlocks ?? []))
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled((workspaceBlocks ?? []).isEmpty)
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
