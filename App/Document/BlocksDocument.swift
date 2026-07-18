import SwiftUI
import TortoiseBlocksKit
import UniformTypeIdentifiers

extension UTType {
    /// The `.tortoiseblocks` document — a `BlocksProject` as JSON (the
    /// frozen wire format pinned by `BlockCodableTests`).
    static let tortoiseBlocksProject = UTType(exportedAs: "space.hiraku.tortoiseblocks.project")
}

struct BlocksDocument: FileDocument {
    var project: BlocksProject

    static let readableContentTypes: [UTType] = [.tortoiseBlocksProject]

    init(project: BlocksProject = BlocksProject(title: "", blocks: [])) {
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Probe just the version before the full decode: a newer file's
        // unknown block shapes would fail the full decode with a generic
        // "corrupt" error before the version gate could explain it.
        let probe = try JSONDecoder().decode(SchemaVersionProbe.self, from: data)
        guard probe.schemaVersion <= BlocksProject.currentSchemaVersion else {
            throw DocumentError.newerSchema
        }
        self.project = try JSONDecoder().decode(BlocksProject.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Write the *minimum* version able to read the document, so files
        // that don't use newer features stay openable (and byte-identical)
        // in older apps.
        var project = self.project
        project.schemaVersion = project.requiredSchemaVersion
        let encoder = JSONEncoder()
        // Deterministic, diff-friendly files (also what the JSON snapshot
        // tests assume about the format).
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return FileWrapper(regularFileWithContents: try encoder.encode(project))
    }
}

/// The version-gate half of the two-phase decode — tolerant of everything
/// except the field it exists to check.
private struct SchemaVersionProbe: Decodable {
    let schemaVersion: Int
}

enum DocumentError: LocalizedError {
    case newerSchema

    var errorDescription: String? {
        switch self {
        case .newerSchema:
            String(localized: "This file was made with a newer version of TortoiseBlocks.")
        }
    }
}
