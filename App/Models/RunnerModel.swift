import Foundation
import Observation
import TortoiseBlocksKit
import TortoiseUI

/// Owns the tortoise and the player; turns a block tree into a running
/// drawing. Keeps the expanded blockID list for the executing-block
/// highlight (M3).
@Observable
@MainActor
final class RunnerModel {
    let tortoise = Tortoise()
    let player = TortoisePlayer()

    /// blockIDs aligned with the expanded command stream —
    /// `expandedBlockIDs[player.currentCommandIndex]` is the executing block.
    private(set) var expandedBlockIDs: [UUID] = []

    /// Set when expansion fails (command limit); drives a kid-friendly alert.
    var showsExpansionError = false

    func run(_ blocks: [Block]) {
        do {
            let expanded = try BlockExpander.expand(blocks)
            expandedBlockIDs = expanded.map(\.blockID)
            player.isPaused = false
            tortoise.reset()
            tortoise.apply(expanded.map(\.command))
        } catch {
            showsExpansionError = true
        }
    }

    func clear() {
        expandedBlockIDs = []
        tortoise.reset()
    }
}
