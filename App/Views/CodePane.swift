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
                    copyToPasteboard(code)
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(8)
            ScrollView([.vertical, .horizontal]) {
                Text(highlightedCode)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background.secondary)
    }

    /// Colors each `CodeTokenizer` span with a semantic color, so both
    /// light and dark mode stay legible.
    private var highlightedCode: AttributedString {
        var result = AttributedString()
        for token in CodeTokenizer.tokenize(code) {
            var piece = AttributedString(code[token.range])
            piece.foregroundColor = color(for: token.kind)
            result += piece
        }
        return result
    }

    private func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .keyword: .purple
        case .number: .blue
        case .methodOrProperty: .teal
        case .plain: .primary
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }
}
