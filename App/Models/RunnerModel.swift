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
        } catch {
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

    /// SVG of the last run, straight from the library's exporter.
    func svgData() -> Data? {
        if let svgDataCache { return svgDataCache }
        guard canExport else { return nil }
        let export = Tortoise()
        export.apply(lastRunCommands)
        let data = Data(export.svg().utf8)
        svgDataCache = data
        return data
    }

    /// PNG of the last run: an instant-mode tortoise rendered statically —
    /// `speed(0)` makes `CanvasModel` flush every frame at init, so
    /// `ImageRenderer` sees the finished drawing without a running timeline.
    /// `scale` is the pixel density (1x = 512px, 2x = 1024px, 3x = 1536px).
    func pngData(scale: CGFloat = 2) -> Data? {
        if let cached = pngDataCache[scale] { return cached }
        guard canExport else { return nil }
        let export = Tortoise()
        export.speed = 0
        export.apply(lastRunCommands)
        let renderer = ImageRenderer(
            content: TortoiseCanvas(export)
                .padding(16)
                .frame(width: 512, height: 512)
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
}
