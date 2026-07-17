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
        let project = try JSONDecoder().decode(BlocksProject.self, from: data)
        // The model layer preserves an unknown (newer) schemaVersion; the
        // document layer is where "made with a newer version" is surfaced.
        guard project.schemaVersion <= BlocksProject.currentSchemaVersion else {
            throw DocumentError.newerSchema
        }
        self.project = project
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        // Deterministic, diff-friendly files (also what the JSON snapshot
        // tests assume about the format).
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return FileWrapper(regularFileWithContents: try encoder.encode(project))
    }
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
