#if os(visionOS)

    import SwiftUI

    /// The generated Swift, on a surface of its own (#53 Phase 3).
    ///
    /// The third surface, and the one that makes the platform's whole argument
    /// concrete: the drawing on the table, the blocks that make it, and the
    /// code they stand for, **all three at once**. On iPad and Mac the canvas
    /// and the code are the two states of one toggle, because a window has
    /// room for one of them; a headset has as many surfaces as you like, so the
    /// choice never has to be made. That is the same reason the program got a
    /// window rather than a pane.
    ///
    /// It is `CodePane`, unchanged — the app's own paper, the same
    /// `CodeTokenizer` colouring, the same copy button. The pane was already
    /// made to work here: #11 took it off `.background.secondary`, which
    /// resolves to translucent glass on this platform and left the syntax
    /// colours with nothing to stand on.
    struct CodeWindow: View {
        let model: ViewerModel

        var body: some View {
            // An `if`, where `ProgramWindow` puts the empty state in an
            // `.overlay`. Deliberate, and the difference is what is behind it:
            // an empty block list is nothing, while an empty code pane is a
            // sheet of white paper carrying a "Copy Code" button that would
            // copy an empty string.
            if model.hasProgram {
                CodePane(code: model.code)
                    .padding()
            }
            else {
                ContentUnavailableView(
                    "No Drawing", systemImage: "curlybraces",
                    description: Text("Open a drawing, or start from a sample."))
            }
        }
    }

#endif
