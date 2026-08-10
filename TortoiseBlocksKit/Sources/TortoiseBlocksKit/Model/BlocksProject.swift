import Foundation

/// The document: a titled top-level block sequence.
///
/// Serialized as JSON inside the `.tortoise` document.
/// `schemaVersion` guards future migrations — decoding a newer version
/// than ``BlocksProject/currentSchemaVersion`` should be surfaced to the
/// user as "made with a newer version" rather than silently mangled.
public struct BlocksProject: Codable, Hashable, Sendable {
    /// 1 = the original format; 2 adds variables (`NumberValue.variable` and
    /// the set / add / subtract / multiply / divide blocks) and the if block
    /// with its optional else; 3 adds blocks the child defines (the define /
    /// call blocks). Documents are written with ``requiredSchemaVersion``, not
    /// this constant, so files that don't use newer features stay openable in
    /// older apps.
    ///
    /// Version 3 is a bump rather than another rider on 2 because 2 has
    /// *shipped*: a released decoder meets `{"define":…}` as an unknown
    /// top-level key and fails the whole document, so the version has to be
    /// what tells it the file is from the future (`BlocksDocument` probes the
    /// number before the full decode and shows the friendly message).
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var title: String
    public var blocks: [Block]

    /// PNG of the last run, long side 256pt, for the QuickLook thumbnail
    /// extension (#15) — so the Files app and Finder show the drawing rather
    /// than a row of identical document icons.
    ///
    /// `JSONEncoder` writes `Data` as base64, so this needs no encoding of its
    /// own. It is optional *presence*: nil writes no key, which keeps a
    /// document that has never run byte-identical to what earlier apps wrote,
    /// and an earlier app ignores the key instead of choking on it. That is
    /// why this rides schema version 1 rather than bumping.
    ///
    /// It is metadata for the file browser, not program state. Nothing puts
    /// it back on the canvas: reopening a document starts with an empty
    /// canvas and one press of the run button (#10 closed that question).
    public var thumbnail: Data?

    /// The minimum schema version able to read this document: 3 when a block
    /// the child defined appears, 2 for a version-2 feature (variables, if
    /// blocks), otherwise 1 — so a file that uses none of them stays
    /// byte-identical to what a version-1 app writes, and a file that only
    /// uses variables still opens in the app that shipped them. (Version 2
    /// never shipped before gaining the if block, so those two share it.)
    public var requiredSchemaVersion: Int {
        let usesFunctions = BlockTree.contains(in: blocks) { block in
            switch block.kind {
            case .defineBlock, .callBlock: true
            default: false
            }
        }
        if usesFunctions { return 3 }
        let usesIf = BlockTree.contains(in: blocks) { block in
            if case .ifBlock = block.kind { return true }
            return false
        }
        return usesIf || !BlockTree.usedVariableNames(in: blocks).isEmpty ? 2 : 1
    }

    public init(
        schemaVersion: Int = BlocksProject.currentSchemaVersion,
        title: String,
        blocks: [Block],
        thumbnail: Data? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.blocks = blocks
        self.thumbnail = thumbnail
    }
}
