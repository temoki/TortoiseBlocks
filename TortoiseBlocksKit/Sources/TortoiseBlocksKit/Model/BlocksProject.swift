import Foundation

/// The document: a titled top-level block sequence.
///
/// Serialized as JSON inside the `.tortoiseblocks` document (M5).
/// `schemaVersion` guards future migrations — decoding a newer version
/// than ``BlocksProject/currentSchemaVersion`` should be surfaced to the
/// user as "made with a newer version" rather than silently mangled.
public struct BlocksProject: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var title: String
    public var blocks: [Block]

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
