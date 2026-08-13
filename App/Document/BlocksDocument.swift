import SwiftUI
import TortoiseBlocksKit
import UniformTypeIdentifiers

extension UTType {
    /// The `.tortoise` document — a `BlocksProject` as JSON (the frozen wire
    /// format pinned by `BlockCodableTests`).
    ///
    /// The identifier keeps the `tortoiseblocks` spelling the app has always
    /// exported (and shares with the bundle ID); only the file extension is
    /// `.tortoise`.
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
        self.project = try Self.project(from: data)
    }

    /// Decoding, apart from `FileDocument`, because the visionOS viewer (#53)
    /// reads `.tortoise` files through a `fileImporter` and has no
    /// `DocumentGroup` to hand it a `ReadConfiguration`. The version gate has
    /// to be the same one, or the two ways in would disagree about which files
    /// are from the future.
    static func project(from data: Data) throws -> BlocksProject {
        // Probe just the version before the full decode: a newer file's
        // unknown block shapes would fail the full decode with a generic
        // "corrupt" error before the version gate could explain it.
        let probe = try JSONDecoder().decode(SchemaVersionProbe.self, from: data)
        guard probe.schemaVersion <= BlocksProject.currentSchemaVersion else {
            throw DocumentError.newerSchema
        }
        return try JSONDecoder().decode(BlocksProject.self, from: data)
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
