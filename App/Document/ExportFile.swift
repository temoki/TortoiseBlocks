import SwiftUI
import UniformTypeIdentifiers

/// Write-only wrapper for `fileExporter` — the actual content type (SVG or
/// PNG) is supplied by the exporter call site.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

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
