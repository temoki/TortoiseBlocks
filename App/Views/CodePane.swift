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
            CodeScroll {
                Text(highlightedCode)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
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

/// The code's scroll view, which puts a program narrower than the pane in its
/// top-leading corner — by a different means on visionOS.
///
/// A program narrower than the pane sat in the *middle* of it, which is not
/// where source starts. A `.leading` frame cannot fix that on its own: in a
/// scroll view that scrolls both ways the content is offered no width to fill,
/// so it takes its own and the scroll view centres what is left over.
/// `defaultScrollAnchor(.topLeading)` is what places undersized content, on
/// both axes at once, and on iPadOS and macOS it still does.
///
/// On visionOS it stopped. The 1.2.0 captures, shot on visionOS 26.5 with this
/// code unchanged since 1.1.0, had the program back in the middle of the paper,
/// and naming the `.alignment` role explicitly changed nothing. There the text
/// is laid out in a frame at least the scroll view's own size, read with a
/// `GeometryReader`, so nothing is left undersized to be placed.
///
/// **That frame is visionOS-only on purpose, and has to stay that way.**
/// Applied on every platform it froze iPadOS: relaunching the app into a second
/// document left the window black, every render commit failing with
/// `invalid destination port`, and the screenshot rig's UI test was killed
/// waiting for the app to go idle. It was bisected across 1.1.0…1.2.0 to the
/// one commit that made the frame unconditional — every commit before it opens
/// the document — so the iPad and the Mac keep the anchor they always had.
private struct CodeScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(visionOS)
            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    content
                        .frame(
                            minWidth: proxy.size.width, minHeight: proxy.size.height,
                            alignment: .topLeading)
                }
                // Still wanted for code *larger* than the pane: it starts the
                // view at the top-leading corner rather than wherever the scroll
                // view would otherwise put its initial offset.
                .defaultScrollAnchor(.topLeading)
            }
        #else
            ScrollView([.vertical, .horizontal]) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
        #endif
    }
}
