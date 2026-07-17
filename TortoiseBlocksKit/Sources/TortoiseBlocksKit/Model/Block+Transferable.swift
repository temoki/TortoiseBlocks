import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// A single block (subtree) in transit — palette → workspace drags and
    /// workspace reordering. Declared in the app's Info.plist
    /// (UTExportedTypeDeclarations).
    public static let tortoiseBlock = UTType(exportedAs: "space.hiraku.tortoiseblocks.block")
}

extension Block: Transferable {
    /// JSON payload via the frozen Codable format. Drops carry the whole
    /// block (including a repeat's body); whether a drop *moves* an existing
    /// block or *inserts* a new one is decided by looking the ID up in the
    /// destination tree.
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tortoiseBlock)
    }
}
