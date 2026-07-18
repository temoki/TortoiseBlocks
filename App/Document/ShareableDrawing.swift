import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Writes already-rendered drawing data to a temp file for `ShareLink` —
/// every share destination (AirDrop, Messages, Files) understands a file,
/// and the URL's last component becomes the visible name on the other end.
private func writeSharedFile(_ data: Data, extension ext: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(String(localized: "Drawing"))
        .appendingPathExtension(ext)
    try data.write(to: url)
    return url
}

/// SVG data ready to share — `RunnerModel.svgData()` renders it once and
/// caches the result, since `ShareLink(item:)` evaluates eagerly whenever
/// the Export menu is drawn.
struct SVGDrawing: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .svg) { drawing in
            SentTransferredFile(try writeSharedFile(drawing.data, extension: "svg"))
        }
    }
}

/// PNG data ready to share — see `SVGDrawing`.
struct PNGDrawing: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { drawing in
            SentTransferredFile(try writeSharedFile(drawing.data, extension: "png"))
        }
    }
}
