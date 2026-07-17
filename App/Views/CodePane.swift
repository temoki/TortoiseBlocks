import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The blocks-to-Swift learning bridge: shows the generated source with a
/// copy button. Content comes in as plain text; generation happens at the
/// call site from the current block tree.
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
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background.secondary)
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
