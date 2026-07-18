import Foundation
import TortoiseCore

/// One expanded command, tagged with the block that produced it —
/// the link that lets the workspace highlight the executing block from
/// `TortoisePlayer.currentCommandIndex`.
public struct ExpandedCommand: Equatable, Sendable {
    public let command: TortoiseCommand
    public let blockID: UUID

    public init(command: TortoiseCommand, blockID: UUID) {
        self.command = command
        self.blockID = blockID
    }
}

public enum BlockExpansionError: Error, Hashable, Sendable {
    /// The program expands to more commands than `limit` — in practice,
    /// runaway nested repeats. Surface as a kid-friendly message.
    case commandLimitExceeded(limit: Int)
}

/// Flattens a block tree into the command stream it stands for.
///
/// Pure function over an injected random source, so tests are deterministic.
/// Randomness rules: a repeat *count* is evaluated once when the repeat
/// starts; values in the *body* are re-evaluated on every iteration.
public enum BlockExpander {
    public static let defaultLimit = 10_000

    /// Expands with the system random source (production path).
    public static func expand(
        _ blocks: [Block],
        limit: Int = BlockExpander.defaultLimit
    ) throws -> [ExpandedCommand] {
        var rng = SystemRandomNumberGenerator()
        return try expand(blocks, using: &rng, limit: limit)
    }

    /// Expands drawing all randomness from `rng` (deterministic under a
    /// seeded generator).
    public static func expand(
        _ blocks: [Block],
        using rng: inout some RandomNumberGenerator,
        limit: Int = BlockExpander.defaultLimit
    ) throws -> [ExpandedCommand] {
        var result: [ExpandedCommand] = []
        try expand(blocks, into: &result, using: &rng, limit: limit)
        return result
    }

    private static func expand(
        _ blocks: [Block],
        into result: inout [ExpandedCommand],
        using rng: inout some RandomNumberGenerator,
        limit: Int
    ) throws {
        for block in blocks {
            switch block.kind {
            case .forward(let value):
                try emit(.forward(value.evaluated(using: &rng)), block, &result, limit)
            case .backward(let value):
                try emit(.forward(-value.evaluated(using: &rng)), block, &result, limit)
            case .turnRight(let value):
                try emit(.rotate(value.evaluated(using: &rng)), block, &result, limit)
            case .turnLeft(let value):
                try emit(.rotate(-value.evaluated(using: &rng)), block, &result, limit)
            case .home:
                try emit(.home, block, &result, limit)
            case .penUp:
                try emit(.penUp, block, &result, limit)
            case .penDown:
                try emit(.penDown, block, &result, limit)
            case .penColor(let color):
                try emit(.penColor(color.evaluated(using: &rng).tortoiseColor), block, &result, limit)
            case .penWidth(let value):
                try emit(.penWidth(value.evaluated(using: &rng)), block, &result, limit)
            case .fillColor(let color):
                try emit(.fillColor(color.evaluated(using: &rng).tortoiseColor), block, &result, limit)
            case .beginFill:
                try emit(.beginFill, block, &result, limit)
            case .endFill:
                try emit(.endFill, block, &result, limit)
            case .repeatBlock(let count, let body):
                let iterations = max(0, Int(count.evaluated(using: &rng).rounded()))
                for _ in 0..<iterations {
                    try expand(body, into: &result, using: &rng, limit: limit)
                }
            }
        }
    }

    private static func emit(
        _ command: TortoiseCommand,
        _ block: Block,
        _ result: inout [ExpandedCommand],
        _ limit: Int
    ) throws {
        guard result.count < limit else {
            throw BlockExpansionError.commandLimitExceeded(limit: limit)
        }
        result.append(ExpandedCommand(command: command, blockID: block.id))
    }
}
