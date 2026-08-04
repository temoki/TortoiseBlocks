import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing

/// Draws the picture stored in a `.tortoise` document as its Finder / Files
/// thumbnail (#15) — the app's own folder in the Files app is the gallery, so
/// the documents in it have to be tellable apart at a glance.
///
/// This target deliberately does **not** link `TortoiseBlocksKit`. The document
/// already carries a rendered PNG (`BlocksProject.thumbnail`), so the whole job
/// is: read the file, lift one base64 field out of the JSON, draw it. No block
/// format, no expander, no SwiftUI — which is also why an unknown block kind or
/// a `schemaVersion` from a future release still gets a thumbnail.
final class ThumbnailProvider: QLThumbnailProvider {
    /// Everything the extension needs from the document. Decoding only this
    /// key is what keeps it independent of the block format; `Data` arrives
    /// base64-decoded, since that is how `JSONEncoder` wrote it.
    private struct DocumentProbe: Decodable {
        let thumbnail: Data?
    }

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        // Declining (nil, nil) hands the file back to the system, which draws
        // the document-type icon. That is the right answer for a document that
        // has never run, and for anything unreadable — a thumbnail extension
        // must never be the reason something fails to display.
        guard let image = Self.storedImage(at: request.fileURL) else {
            handler(nil, nil)
            return
        }

        let size = Self.fittedSize(of: image, within: request.maximumSize)
        let reply = QLThumbnailReply(contextSize: size) { (context: CGContext) -> Bool in
            // `contextSize` is in points, but the context handed back measures
            // in device pixels with an identity CTM — drawing into a rect of
            // `size` on a 2× display fills a quarter of it and leaves the
            // thumbnail in a corner. Ask the context how big it actually is
            // and map that back through its own transform, which is right at
            // either scale. Filling it whole never distorts: `fittedSize`
            // already carries the image's aspect ratio.
            let pixels = CGRect(
                x: 0, y: 0, width: CGFloat(context.width), height: CGFloat(context.height))
            context.draw(image, in: pixels.applying(context.ctm.inverted()))
            return true
        }
        handler(reply, nil)
    }

    /// The document's stored PNG, or nil for anything that isn't one — a
    /// document that has never run, a file written before thumbnails existed,
    /// truncated JSON, a corrupt image. Every step is failable on purpose.
    private static func storedImage(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
            let probe = try? JSONDecoder().decode(DocumentProbe.self, from: data),
            let png = probe.thumbnail,
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    /// Aspect-fit into what QuickLook asked for. The stored picture is at most
    /// 256pt on its long side, so a large request upscales it — a deliberate
    /// trade for a bounded document (see `RunnerModel.thumbnailData`).
    private static func fittedSize(of image: CGImage, within maximum: CGSize) -> CGSize {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0, maximum.width > 0, maximum.height > 0 else { return maximum }
        let scale = min(maximum.width / width, maximum.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}
