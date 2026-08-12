import SwiftUI
import TortoiseBlocksKit

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The blocks-to-Swift learning bridge: shows the generated source,
/// syntax-colored via `CodeTokenizer`, with a copy button. Content comes in
/// as plain text; generation happens at the call site from the current
/// block tree.
struct CodePane: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Copy Code", systemImage: "doc.on.doc") {
                    copyCodeToPasteboard(code)
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(8)
            // The code is on paper, the same paper the canvas is on (#11). It
            // used to sit on `.background.secondary`, which is a *semantic*
            // surface: near-white or near-black on iPad and Mac, and on
            // visionOS light translucent glass over a room. The syntax colors
            // then had nowhere to stand — system `.purple` and `.blue` are
            // tuned for an opaque backdrop, and `.plain` was `Color.primary`,
            // which is *white* there, so the plain text and the ground behind
            // it were both light. Opaque, named, and the same in both
            // appearances, for the reason the block fills are (#41): this is
            // the app's surface, not a response to its surroundings.
            //
            // White rather than an editor's dark theme because the code pane
            // and the canvas swap places inside one `ZStack` — the same sheet,
            // rounded the same 8, means pressing the toggle changes only the
            // *content*.
            //
            // The paper wraps the code and nothing else. The copy button stays
            // outside it, on the pane's own ground with the window's other
            // controls: inside, it needed the ink as a tint to be legible, and
            // on visionOS the tint went to the *capsule* instead of the label,
            // leaving a black lozenge with invisible text on it.
            ScrollView([.vertical, .horizontal]) {
                Text(highlightedCode)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A program narrower than the pane sat in the *middle* of it, which
            // is not where source starts. The `.leading` frame above cannot fix
            // that on its own: in a scroll view that scrolls both ways the
            // content is offered no width to fill, so it takes its own and the
            // scroll view centres what is left over. The anchor is what places
            // undersized content, on both axes at once.
            .defaultScrollAnchor(.topLeading)
            .background(Color.white, in: Self.sheet)
            .clipShape(Self.sheet)
        }
    }

    /// The canvas's shape, so the two panes are the same sheet — see
    /// `CanvasPane.sheet`, which this deliberately matches.
    private static let sheet = RoundedRectangle(cornerRadius: 8)

    /// Colors each `CodeTokenizer` span with a fixed color.
    ///
    /// Fixed, not semantic: the pane is white in both appearances, so a color
    /// that inverts with the appearance would be picking its contrast against
    /// a background it no longer has. These are measured against white —
    /// 8.6:1, 8.4:1, 5.1:1 and 16.9:1 — so every kind clears AA at the callout
    /// size, and the three accents stay far enough apart in hue to be told
    /// apart at a glance.
    private func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .keyword: Color(.sRGB, red: 0.604, green: 0.129, blue: 0.588)  // #9A2196
        case .number: Color(.sRGB, red: 0.106, green: 0.220, blue: 0.784)  // #1B38C8
        case .methodOrProperty: Color(.sRGB, red: 0.031, green: 0.396, blue: 0.435)  // #08656F
        case .plain: BlockCategory.ink
        }
    }

    /// Colors each `CodeTokenizer` span, so the pane reads as source.
    private var highlightedCode: AttributedString {
        var result = AttributedString()
        for token in CodeTokenizer.tokenize(code) {
            var piece = AttributedString(code[token.range])
            piece.foregroundColor = color(for: token.kind)
            result += piece
        }
        return result
    }
}

/// Shared with the Run menu's "Copy Code" command (#23), so both paths to
/// copying the generated source go through the same platform pasteboard call.
func copyCodeToPasteboard(_ string: String) {
    #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    #else
        UIPasteboard.general.string = string
    #endif
}
