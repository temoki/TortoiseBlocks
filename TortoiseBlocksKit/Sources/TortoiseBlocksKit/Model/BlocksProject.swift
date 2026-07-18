import Foundation

/// The document: a titled top-level block sequence.
///
/// Serialized as JSON inside the `.tortoiseblocks` document (M5).
/// `schemaVersion` guards future migrations — decoding a newer version
/// than ``BlocksProject/currentSchemaVersion`` should be surfaced to the
/// user as "made with a newer version" rather than silently mangled.
public struct BlocksProject: Codable, Hashable, Sendable {
    /// 1 = the original format; 2 adds variables (`NumberValue.variable`,
    /// set/add blocks). Documents are written with
    /// ``requiredSchemaVersion``, not this constant, so files that don't use
    /// newer features stay openable in older apps.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var title: String
    public var blocks: [Block]

    /// The minimum schema version able to read this document: 2 when any
    /// version-2 feature (variables, if blocks) appears in the tree,
    /// otherwise 1 — keeping such files byte-identical to what version-1
    /// apps write. (Version 2 never shipped before gaining the if block, so
    /// both features share it.)
    public var requiredSchemaVersion: Int {
        let usesIf = BlockTree.contains(in: blocks) { block in
            if case .ifBlock = block.kind { return true }
            return false
        }
        return usesIf || !BlockTree.usedVariableNames(in: blocks).isEmpty ? 2 : 1
    }

    public init(
        schemaVersion: Int = BlocksProject.currentSchemaVersion,
        title: String,
        blocks: [Block]
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.blocks = blocks
    }
}
