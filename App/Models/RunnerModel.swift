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
    /// exports render exactly what is on screen.
    private(set) var lastRunCommands: [TortoiseCommand] = []

    /// Bounding box of the last run's visible output, or nil when it drew
    /// nothing. `nil` on an empty stream, exactly as `DrawingBounds` reports it.
    ///
    /// Computed once per run rather than per use, because both users want it
    /// repeatedly and neither can afford the replay: the export sizes its
    /// frame from it (once per export, previously replaying the stream again),
    /// and the visionOS table maps the 3-D tortoise's position through the
    /// same `autoFit` transform the canvas uses — *every display frame*.
    private(set) var drawingBounds: DrawingBounds?

    /// Set when expansion fails; drives a kid-friendly alert.
    var showsExpansionError = false

    /// *Why* it failed, which is what the alert's wording follows from: too
    /// many blocks and a block that calls itself forever are different
    /// mistakes, and a child can only fix the one they actually made.
    private(set) var expansionFailure: BlockExpansionError?

    /// Title and message for that alert. Kept here rather than in the view so
    /// the pairing lives with the error it explains — there is exactly one
    /// alert in `CanvasPane` (two would clobber each other), so it switches on
    /// this instead.
    var expansionAlert: (title: LocalizedStringResource, message: LocalizedStringResource) {
        switch expansionFailure {
        case .nestingLimitExceeded:
            ("Too Much Calling!", "Your block keeps calling itself. Use an if block to stop it.")
        default:
            ("Too Many Blocks!", "Try a smaller repeat count.")
        }
    }

    /// Bumped by every successful run. `ContentView` watches this number and
    /// stores a fresh thumbnail (#15) — one observer instead of a call at each
    /// of the four places a run can start (the transport's centre button, the
    /// canvas's ⟳, and both Run-menu items), which is a list that can be
    /// forgotten. A counter rather than the command stream: comparing
    /// thousands of commands on every change would cost more than the write it
    /// guards.
    private(set) var runGeneration = 0

    /// Identity of the block tree the current run was expanded from. Editing
    /// the workspace makes the drawing on screen stale, which is what turns
    /// the transport's centre button back into "run" (#28). A hash is enough:
    /// it never leaves the process, and a collision would only cost a
    /// stale-looking button until the next edit.
    private var lastRunTreeHash: Int?

    /// Set by the macOS menu's Export commands; `CanvasPane` watches this,
    /// runs the same export it would from its own menu, and clears it back
    /// to nil. `CanvasPane` still owns the actual `fileExporter` state.
    var pendingExport: UTType?

    // Export renders are cached per run: `ShareLink(item:)` evaluates its
    // item eagerly whenever the Export menu is drawn, so without this an
    // ImageRenderer pass would fire on every menu open. Cleared in `run()`,
    // the only place `lastRunCommands` changes.
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

    /// Whether the frame-by-frame controls apply: there is a drawing, and it
    /// is standing still. While the animation runs they would fight it, so
    /// they wait rather than yanking playback to a stop.
    ///
    /// Deliberately not gated on staleness — editing a block doesn't stop the
    /// drawing already on screen from being worth stepping through.
    var canStep: Bool {
        commandCount > 0 && (player.isPaused || player.isFinished)
    }

    var canExport: Bool { !lastRunCommands.isEmpty }

    /// Whether `blocks` has been edited since the run that is on screen.
    /// `true` before anything has run at all, so the one check covers both
    /// "nothing to play yet" and "what's playing is out of date".
    func isStale(comparedTo blocks: [Block]) -> Bool {
        lastRunTreeHash != blocks.hashValue
    }

    /// Expands `blocks` and starts drawing. Randomness is drawn fresh every
    /// time, so this is also the "roll again" action — a program with dice
    /// draws a different picture on each run.
    ///
    /// `startPaused` loads the new stream without playing it: rolling again
    /// from the canvas swaps in a fresh set of dice and waits at the start,
    /// so the drawing appears only when the transport says to.
    func run(_ blocks: [Block], startPaused: Bool = false) {
        do {
            let expanded = try BlockExpander.expand(blocks)
            expandedBlockIDs = expanded.map(\.blockID)
            lastRunCommands = expanded.map(\.command)
            drawingBounds = DrawingBounds.compute(
                from: CommandPlayer.play(commands: lastRunCommands))
            lastRunTreeHash = blocks.hashValue
            player.isPaused = startPaused
            tortoise.reset()
            tortoise.apply(lastRunCommands)
            svgDataCache = nil
            pngDataCache = [:]
            runGeneration += 1
        }
        catch {
            expansionFailure = error as? BlockExpansionError
            showsExpansionError = true
        }
    }

    /// Moves the playhead without ever starting playback that wasn't already
    /// running.
    ///
    /// A finished stream is held still by `isFinished`, not by `isPaused` —
    /// seeking away from the end clears that flag, and an unpaused player
    /// takes off on its own. So the stop has to be made explicit first.
    /// Scrubbing *during* playback still tracks live, which is why this
    /// pauses only when the drawing had already played out.
    func seek(to index: Int) {
        if player.isFinished { player.isPaused = true }
        player.seek(to: index)
    }

    /// Replays the run already on screen from the beginning — the same
    /// command stream, so the picture is identical (dice are not re-rolled;
    /// that is what `run(_:)` is for).
    func replay() {
        player.seek(to: -1)
        player.isPaused = false
    }

    // MARK: - Export

    /// SVG of the last run, straight from the library's exporter. `svg()`
    /// defaults to `fit: true` — cropped tight to the drawing, tortoise-free
    /// (#25); `pngData` deliberately mirrors that framing.
    ///
    /// The transparent ground is now asked for outright. Since 2.0.0-beta12 a
    /// stream that never names a background renders on white, so leaving this
    /// implicit would put a `<rect fill="#ffffff"/>` under every export — and
    /// an export is a picture you place somewhere yourself.
    func svgData() -> Data? {
        if let svgDataCache { return svgDataCache }
        guard canExport else { return nil }
        let export = Tortoise()
        export.backgroundColor = .clear
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
        let data = Self.renderPNG(
            lastRunCommands, bounds: drawingBounds, longSide: 512, scale: scale)
        pngDataCache[scale] = data
        return data
    }

    /// The picture stored in the document for the QuickLook thumbnail
    /// extension (#15): the same render as the PNG export, at a long side of
    /// 256pt and no pixel doubling.
    ///
    /// Not cached. It is asked for once per run, right after the render, and a
    /// second copy of every drawing in memory buys nothing.
    ///
    /// 256 is a deliberate ceiling: measured across the sample programs a
    /// thumbnail costs 3–51KB of base64 in the document, and the *size follows
    /// the ink, not the command count* — the 10,000-command drawing is the
    /// smallest of them. Doubling to 512 would quadruple that for a picture
    /// mostly shown at icon size. QuickLook may ask for more on a Retina
    /// display and upscale ours; that softness is the accepted trade.
    ///
    /// Opaque, unlike the exports: this one is drawn onto someone else's
    /// background. An exported PNG is an artifact you place yourself, so
    /// transparency is a feature there; a thumbnail is composited by Finder and
    /// the Files app, and against their dark appearance a black-pen drawing on
    /// a transparent ground all but disappears — which would undo the point of
    /// putting the picture on the file in the first place.
    func thumbnailData() -> Data? {
        guard canExport else { return nil }
        return Self.renderPNG(
            lastRunCommands, bounds: drawingBounds, longSide: 256, scale: 1, onWhite: true)
    }

    /// Renders a command stream to PNG, cropped tight to the drawing and
    /// tortoise-free so it matches the SVG export (#25). The render frame takes
    /// the drawing's bounding-box aspect ratio; `.autoFit` then fills it,
    /// leaving only its own small uniform margin. The tortoise sprite is a
    /// cursor, not part of the picture — the SVG export omits it, so this does
    /// too (`hideTortoise`). `speed(0)` makes `CanvasModel` flush every frame at
    /// init, so `ImageRenderer` sees the finished drawing without a running
    /// timeline. `scale` is the pixel density applied on top.
    ///
    /// `onWhite` decides the ground, and says so outright rather than leaning
    /// on a default: before 2.0.0-beta12 a stream that never named a background
    /// rendered transparent, and since then it renders white. Neither default
    /// is what both callers want, so both are asked for explicitly — the
    /// exports transparent, because an export is a picture you place somewhere
    /// yourself, and the thumbnail white, because Finder places that one.
    private static func renderPNG(
        _ commands: [TortoiseCommand], bounds: DrawingBounds?, longSide: Double, scale: CGFloat,
        onWhite: Bool = false
    ) -> Data? {
        let export = Tortoise()
        export.speed = 0
        export.backgroundColor = onWhite ? .white : .clear
        export.apply(commands)
        export.hideTortoise()
        let size = exportFrameSize(for: bounds, longSide: longSide)
        let renderer = ImageRenderer(
            content: TortoiseCanvas(export)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        #if os(macOS)
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        #else
            return UIImage(cgImage: cgImage).pngData()
        #endif
    }

    /// Base render size (before `scale`) for the tight PNG: the drawing's
    /// bounding-box aspect ratio with the long side at `longSide` (#25). A
    /// near-straight-line drawing is clamped to at most 3:1 so it can't produce
    /// an unusable sliver; an empty drawing (no bounds) falls back to a square,
    /// mirroring SVG's own "no visible output" fallback.
    private static func exportFrameSize(
        for bounds: DrawingBounds?, longSide long: Double
    ) -> CGSize {
        let square = CGSize(width: long, height: long)
        guard let bounds else { return square }
        // Mirrors TortoiseUI's autoFit inset — the tortoise sprite's
        // half-extent × tortoiseScaleMax — so the drawing fills the frame with
        // a uniform margin instead of a lopsided one. 20 is the *triangle's*
        // (half-height 10 × 2), which is why the export canvas above is the one
        // place that keeps the default sprite: `CanvasPane`'s 23×32 artwork
        // insets by ~39 instead (its half-diagonal × 2), and the picture would
        // sit in a wider border than the SVG's. It is hidden there anyway. If
        // the library changes the inset this only shifts the margin slightly —
        // never breaks.
        let inset = 20.0
        let w = bounds.width + 2 * inset
        let h = bounds.height + 2 * inset
        guard w > 0, h > 0 else { return square }
        let aspect = min(max(w / h, 1.0 / 3.0), 3.0)
        return aspect >= 1
            ? CGSize(width: long, height: long / aspect)
            : CGSize(width: long * aspect, height: long)
    }
}
