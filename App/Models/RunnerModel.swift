import Foundation
import Observation
import SwiftUI
import TortoiseBlocksKit
import TortoiseSVG
import TortoiseUI
import UniformTypeIdentifiers

/// Owns the tortoise and the player; turns a block tree into a running
/// drawing and renders the last run for export.
@Observable
@MainActor
final class RunnerModel {
    let tortoise = Tortoise()
    let player = TortoisePlayer()

    /// blockIDs aligned with the expanded command stream —
    /// `expandedBlockIDs[player.currentCommandIndex]` is the executing block.
    private(set) var expandedBlockIDs: [UUID] = []

    /// The evaluated command stream of the last run (randomness resolved) —
    /// exports render exactly what is on screen (§9).
    private(set) var lastRunCommands: [TortoiseCommand] = []

    /// Set when expansion fails (command limit); drives a kid-friendly alert.
    var showsExpansionError = false

    /// Set by the macOS menu's Export commands; `CanvasPane` watches this,
    /// runs the same export it would from its own menu, and clears it back
    /// to nil. `CanvasPane` still owns the actual `fileExporter` state.
    var pendingExport: UTType?

    // Export renders are cached per run: `ShareLink(item:)` evaluates its
    // item eagerly whenever the Export menu is drawn, so without this an
    // ImageRenderer pass would fire on every menu open. Cleared in `run()`
    // and `clear()`, the only places `lastRunCommands` changes.
    private var svgDataCache: Data?
    private var pngDataCache: [CGFloat: Data] = [:]

    /// The block the canvas is currently executing (nil when idle/finished
    /// past the end). Observable through `player.currentCommandIndex`, so
    /// the workspace highlight tracks playback live.
    var currentBlockID: UUID? {
        let index = player.currentCommandIndex
        guard expandedBlockIDs.indices.contains(index) else { return nil }
        return expandedBlockIDs[index]
    }

    /// Total command count of the last run (the scrubber's range).
    var commandCount: Int { expandedBlockIDs.count }

    var canExport: Bool { !lastRunCommands.isEmpty }

    func run(_ blocks: [Block]) {
        do {
            let expanded = try BlockExpander.expand(blocks)
            expandedBlockIDs = expanded.map(\.blockID)
            lastRunCommands = expanded.map(\.command)
            player.isPaused = false
            tortoise.reset()
            tortoise.apply(lastRunCommands)
            svgDataCache = nil
            pngDataCache = [:]
        }
        catch {
            showsExpansionError = true
        }
    }

    func clear() {
        expandedBlockIDs = []
        lastRunCommands = []
        tortoise.reset()
        svgDataCache = nil
        pngDataCache = [:]
    }

    // MARK: - Export

    /// SVG of the last run, straight from the library's exporter. `svg()`
    /// defaults to `fit: true` — cropped tight to the drawing, tortoise-free
    /// (#25); `pngData` deliberately mirrors that framing.
    func svgData() -> Data? {
        if let svgDataCache { return svgDataCache }
        guard canExport else { return nil }
        let export = Tortoise()
        export.apply(lastRunCommands)
        let data = Data(export.svg().utf8)
        svgDataCache = data
        return data
    }

    /// PNG of the last run, cropped tight to the drawing and turtle-free, so
    /// it matches the SVG export instead of the old fixed 512×512 square
    /// (#25). The render frame takes the drawing's bounding-box aspect ratio;
    /// `.autoFit` then fills it, leaving only its own small uniform margin.
    /// The tortoise sprite is a cursor, not part of the picture — the SVG
    /// export omits it, so this does too (`hideTortoise`). `speed(0)` makes
    /// `CanvasModel` flush every frame at init, so `ImageRenderer` sees the
    /// finished drawing without a running timeline. `scale` is the pixel
    /// density applied on top (1x/2x/3x).
    func pngData(scale: CGFloat = 2) -> Data? {
        if let cached = pngDataCache[scale] { return cached }
        guard canExport else { return nil }
        let export = Tortoise()
        export.speed = 0
        export.apply(lastRunCommands)
        export.hideTortoise()
        let size = Self.exportFrameSize(for: lastRunCommands)
        let renderer = ImageRenderer(
            content: TortoiseCanvas(export)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        let data: Data?
        #if os(macOS)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            data = rep.representation(using: .png, properties: [:])
        #else
            data = UIImage(cgImage: cgImage).pngData()
        #endif
        pngDataCache[scale] = data
        return data
    }

    /// Base render size (before `scale`) for the tight PNG: the drawing's
    /// bounding-box aspect ratio with the long side at 512pt (#25). A near-
    /// straight-line drawing is clamped to at most 3:1 so it can't produce an
    /// unusable sliver; an empty drawing (no bounds) falls back to a 512×512
    /// square, mirroring SVG's own "no visible output" fallback.
    private static func exportFrameSize(for commands: [TortoiseCommand]) -> CGSize {
        let square = CGSize(width: 512, height: 512)
        guard let bounds = DrawingBounds.compute(from: CommandPlayer.play(commands: commands))
        else { return square }
        // Mirrors TortoiseUI's autoFit inset (sprite half-size, tortoiseBase
        // × tortoiseScaleMax = 20) so the drawing fills the frame with a
        // uniform margin instead of a lopsided one. If the library changes
        // that inset this only shifts the margin slightly — never breaks.
        let inset = 20.0
        let w = bounds.width + 2 * inset
        let h = bounds.height + 2 * inset
        guard w > 0, h > 0 else { return square }
        let aspect = min(max(w / h, 1.0 / 3.0), 3.0)
        let long = 512.0
        return aspect >= 1
            ? CGSize(width: long, height: long / aspect)
            : CGSize(width: long * aspect, height: long)
    }
}
