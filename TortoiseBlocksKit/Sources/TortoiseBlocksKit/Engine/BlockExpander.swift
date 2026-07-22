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
    /// The program executes more steps than `limit` — in practice, runaway
    /// nested repeats. Surface as a kid-friendly message.
    case commandLimitExceeded(limit: Int)
}

/// Flattens a block tree into the command stream it stands for.
///
/// Pure function over an injected random source, so tests are deterministic.
/// Randomness rules: a repeat *count* is evaluated once when the repeat
/// starts; values in the *body* are re-evaluated on every iteration.
///
/// Variables are a single global scope, all reading 0 until set. The set/add
/// blocks emit *no* command — the 1:1 alignment between commands and
/// `blockID`s that highlighting relies on stays intact — but they still
/// count as steps against `limit`, so an assignment-only runaway loop can't
/// slip past the cap.
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
        var variables: [String: Double] = [:]
        var steps = 0
        try expand(
            blocks, into: &result, variables: &variables, steps: &steps,
            using: &rng, limit: limit)
        return result
    }

    private static func expand(
        _ blocks: [Block],
        into result: inout [ExpandedCommand],
        variables: inout [String: Double],
        steps: inout Int,
        using rng: inout some RandomNumberGenerator,
        limit: Int
    ) throws {
        func evaluate(_ value: NumberValue) -> Double {
            value.evaluated(variables: variables, using: &rng)
        }
        for block in blocks {
            switch block.kind {
            case .forward(let value):
                try emit(.forward(evaluate(value)), block, &result, &steps, limit)
            case .backward(let value):
                try emit(.forward(-evaluate(value)), block, &result, &steps, limit)
            case .turnRight(let value):
                try emit(.rotate(evaluate(value)), block, &result, &steps, limit)
            case .turnLeft(let value):
                try emit(.rotate(-evaluate(value)), block, &result, &steps, limit)
            case .home:
                try emit(.home, block, &result, &steps, limit)
            case .penUp:
                try emit(.penUp, block, &result, &steps, limit)
            case .penDown:
                try emit(.penDown, block, &result, &steps, limit)
            case .penColor(let color):
                try emit(
                    .penColor(color.evaluated(using: &rng).tortoiseColor), block, &result, &steps,
                    limit)
            case .penWidth(let value):
                try emit(.penWidth(evaluate(value)), block, &result, &steps, limit)
            case .fillColor(let color):
                try emit(
                    .fillColor(color.evaluated(using: &rng).tortoiseColor), block, &result, &steps,
                    limit)
            case .beginFill:
                try emit(.beginFill, block, &result, &steps, limit)
            case .endFill:
                try emit(.endFill, block, &result, &steps, limit)
            case .repeatBlock(let count, let body):
                let iterations = max(0, Int(evaluate(count).rounded()))
                for _ in 0..<iterations {
                    try expand(
                        body, into: &result, variables: &variables, steps: &steps,
                        using: &rng, limit: limit)
                }
            case .ifBlock(let condition, let body, let elseBody):
                // The test itself is a step (like set/add), so a
                // false-branch-only loop can't slip past the cap. Evaluated
                // per encounter — dice in a condition re-roll every time,
                // and that single evaluation picks exactly one mouth.
                try charge(&steps, limit)
                if condition.holds(variables: variables, using: &rng) {
                    try expand(
                        body, into: &result, variables: &variables, steps: &steps,
                        using: &rng, limit: limit)
                }
                else if let elseBody {
                    try expand(
                        elseBody, into: &result, variables: &variables, steps: &steps,
                        using: &rng, limit: limit)
                }
            case .setVariable(let name, let value):
                try charge(&steps, limit)
                // Evaluate before touching storage — `evaluate` reads
                // `variables`, and overlapping that with the write would
                // violate exclusivity (the value may reference the variable
                // being assigned, e.g. 🌟 に 🌟 を たす).
                let newValue = evaluate(value)
                variables[name] = newValue
            case .addVariable(let name, let value):
                try charge(&steps, limit)
                let delta = evaluate(value)
                variables[name, default: 0] += delta
            case .subtractVariable(let name, let value):
                try charge(&steps, limit)
                let delta = evaluate(value)
                variables[name, default: 0] -= delta
            case .multiplyVariable(let name, let value):
                try charge(&steps, limit)
                let factor = evaluate(value)
                variables[name, default: 0] *= factor
            case .divideVariable(let name, let value):
                try charge(&steps, limit)
                // Dividing by zero is a kid-friendly no-op — the box keeps
                // its value. inf/NaN must never reach the tortoise.
                let divisor = evaluate(value)
                if divisor != 0 {
                    variables[name, default: 0] /= divisor
                }
            }
        }
    }

    private static func charge(_ steps: inout Int, _ limit: Int) throws {
        guard steps < limit else {
            throw BlockExpansionError.commandLimitExceeded(limit: limit)
        }
        steps += 1
    }

    private static func emit(
        _ command: TortoiseCommand,
        _ block: Block,
        _ result: inout [ExpandedCommand],
        _ steps: inout Int,
        _ limit: Int
    ) throws {
        try charge(&steps, limit)
        result.append(ExpandedCommand(command: command, blockID: block.id))
    }
}
