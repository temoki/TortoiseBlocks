import Foundation
import Observation
import SwiftUI
import TortoiseBlocksKit
import TortoiseSVG
import TortoiseUI

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
        } catch {
            showsExpansionError = true
        }
    }

    func clear() {
        expandedBlockIDs = []
        lastRunCommands = []
        tortoise.reset()
    }

    // MARK: - Export

    /// SVG of the last run, straight from the library's exporter.
    func svgData() -> Data? {
        guard canExport else { return nil }
        let export = Tortoise()
        export.apply(lastRunCommands)
        return Data(export.svg().utf8)
    }

    /// PNG of the last run: an instant-mode tortoise rendered statically —
    /// `speed(0)` makes `CanvasModel` flush every frame at init, so
    /// `ImageRenderer` sees the finished drawing without a running timeline.
    func pngData() -> Data? {
        guard canExport else { return nil }
        let export = Tortoise()
        export.speed = 0
        export.apply(lastRunCommands)
        let renderer = ImageRenderer(
            content: TortoiseCanvas(export)
                .frame(width: 512, height: 512)
                .padding(16)
        )
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        #if os(macOS)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .png, properties: [:])
        #else
            return UIImage(cgImage: cgImage).pngData()
        #endif
    }
}
