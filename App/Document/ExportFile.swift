import SwiftUI
import UniformTypeIdentifiers

/// Write-only wrapper for `fileExporter` — the actual content type (SVG or
/// PNG) is supplied by the exporter call site.
struct ExportFile: FileDocument {
    // Never read back; empty keeps this type out of any open panel.
    static let readableContentTypes: [UTType] = []
    // The exporter's contentType must be listed here, or the save panel
    // cannot infer the filename extension.
    static let writableContentTypes: [UTType] = [.svg, .png]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
