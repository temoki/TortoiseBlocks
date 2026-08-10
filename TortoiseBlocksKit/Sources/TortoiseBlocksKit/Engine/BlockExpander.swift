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
    /// Expansion nests more than `limit` deep — in practice a block that calls
    /// itself without ever stopping.
    ///
    /// Deliberately not covered by the step cap, and the two are not
    /// interchangeable: expansion descends on the Swift stack, which overflows
    /// — a crash, not an error — long before 10,000 steps. It counts *every*
    /// kind of nesting rather than calls alone, because that is what the stack
    /// counts: a definition holding five nested repeats around its own call
    /// spends six frames per call, and bounding only the calls would leave the
    /// crash exactly where it was.
    case nestingLimitExceeded(limit: Int)
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
///
/// Every value is saturated into its slot's ``NumberDomain`` on the way out.
/// This is the layer that has to do it: the editor refuses out-of-range input,
/// but boxes drift past the bounds through arithmetic, and dice bounds and
/// decoded documents never pass through the editor at all.
///
/// Blocks the child defines ("じぶんのブロック") make this two passes: every
/// definition in the tree is collected first, then the tree is expanded, so a
/// call works wherever it sits relative to the block it calls. A call splices
/// the definition's body in where the call is, which makes recursion fall out
/// for free — and is why expansion carries a nesting limit as well as a step
/// cap (see ``defaultNestingLimit``).
public enum BlockExpander {
    public static let defaultLimit = 10_000

    /// How deep expansion may nest — bodies and calls alike — before
    /// ``BlockExpansionError/nestingLimitExceeded(limit:)``.
    ///
    /// The number is measured, not chosen: expansion recurses on the Swift
    /// stack, and in a **debug** build on a 512KB stack (any caller that isn't
    /// the main actor — a `Task`, and every test in this package) it overflows
    /// between 55 and 60 levels. An optimized build clears 200. So the limit
    /// has to be set against the debug figure, with room to spare, because
    /// what is on the other side of it is a crash rather than a message.
    ///
    /// 30 is not a compromise for the drawings either. A branching fractal is
    /// stopped by the step cap first — depth 30 would be 2^30 branches — and
    /// "recursion as a counting loop", the one shape that wants real depth, is
    /// what くりかえす is already for.
    public static let defaultNestingLimit = 30

    /// Expands with the system random source (production path).
    public static func expand(
        _ blocks: [Block],
        limit: Int = BlockExpander.defaultLimit,
        nestingLimit: Int = BlockExpander.defaultNestingLimit
    ) throws -> [ExpandedCommand] {
        var rng = SystemRandomNumberGenerator()
        return try expand(blocks, using: &rng, limit: limit, nestingLimit: nestingLimit)
    }

    /// Expands drawing all randomness from `rng` (deterministic under a
    /// seeded generator).
    public static func expand(
        _ blocks: [Block],
        using rng: inout some RandomNumberGenerator,
        limit: Int = BlockExpander.defaultLimit,
        nestingLimit: Int = BlockExpander.defaultNestingLimit
    ) throws -> [ExpandedCommand] {
        var result: [ExpandedCommand] = []
        var variables: [String: Double] = [:]
        var steps = 0
        // Pass one. Definitions are read from the whole tree — nested ones
        // included — before anything runs, which is what lets a call appear
        // above the block it calls.
        let definitions = Dictionary(
            BlockTree.functionDefinitions(in: blocks).map { ($0.name, $0.body) },
            uniquingKeysWith: { first, _ in first })
        try expand(
            blocks, into: &result, variables: &variables, steps: &steps,
            using: &rng, limit: limit,
            definitions: definitions, depth: 0, nestingLimit: nestingLimit)
        return result
    }

    private static func expand(
        _ blocks: [Block],
        into result: inout [ExpandedCommand],
        variables: inout [String: Double],
        steps: inout Int,
        using rng: inout some RandomNumberGenerator,
        limit: Int,
        definitions: [String: [Block]],
        depth: Int,
        nestingLimit: Int
    ) throws {
        // One check for every way of descending — a body, a mouth, a call —
        // because the stack doesn't care which one it was. `depth` is this
        // function's own recursion depth, so the guard is exactly the frame
        // count it bounds.
        guard depth <= nestingLimit else {
            throw BlockExpansionError.nestingLimitExceeded(limit: nestingLimit)
        }
        /// Every value reaching a command is saturated into its slot's
        /// ``NumberDomain`` — the only layer that sees box drift, dice
        /// bounds, and values decoded from older documents.
        func evaluate(_ value: NumberValue, _ domain: NumberDomain) -> Double {
            value.evaluated(in: domain, variables: variables, using: &rng)
        }
        for block in blocks {
            switch block.kind {
            case .forward(let value):
                try emit(.forward(evaluate(value, .distance)), block, &result, &steps, limit)
            case .backward(let value):
                try emit(.forward(-evaluate(value, .distance)), block, &result, &steps, limit)
            case .turnRight(let value):
                try emit(.rotate(evaluate(value, .angle)), block, &result, &steps, limit)
            case .turnLeft(let value):
                try emit(.rotate(-evaluate(value, .angle)), block, &result, &steps, limit)
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
                try emit(.penWidth(evaluate(value, .penWidth)), block, &result, &steps, limit)
            case .fillColor(let color):
                try emit(
                    .fillColor(color.evaluated(using: &rng).tortoiseColor), block, &result, &steps,
                    limit)
            case .beginFill:
                try emit(.beginFill, block, &result, &steps, limit)
            case .endFill:
                try emit(.endFill, block, &result, &steps, limit)
            case .repeatBlock(let count, let body):
                // Never a bare `Int(_ :Double)`: that traps outside Int's
                // range and on inf/NaN, both reachable from ordinary input
                // (#27). The count cap also bounds an *empty* body, which
                // charges no step and so can't be stopped by `limit`.
                let iterations = NumberDomain.iterationCount(evaluate(count, .repeatCount))
                for _ in 0..<iterations {
                    try expand(
                        body, into: &result, variables: &variables, steps: &steps,
                        using: &rng, limit: limit,
                        definitions: definitions, depth: depth + 1, nestingLimit: nestingLimit)
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
                        using: &rng, limit: limit,
                        definitions: definitions, depth: depth + 1, nestingLimit: nestingLimit)
                }
                else if let elseBody {
                    try expand(
                        elseBody, into: &result, variables: &variables, steps: &steps,
                        using: &rng, limit: limit,
                        definitions: definitions, depth: depth + 1, nestingLimit: nestingLimit)
                }
            case .setVariable(let name, let value):
                try charge(&steps, limit)
                // Evaluate before touching storage — `evaluate` reads
                // `variables`, and overlapping that with the write would
                // violate exclusivity (the value may reference the variable
                // being assigned, e.g. 🌟 に 🌟 を たす).
                let newValue = evaluate(value, .general)
                variables[name] = newValue
            case .addVariable(let name, let value):
                try charge(&steps, limit)
                let delta = evaluate(value, .general)
                variables[name, default: 0] = saturate(variables[name, default: 0] + delta)
            case .subtractVariable(let name, let value):
                try charge(&steps, limit)
                let delta = evaluate(value, .general)
                variables[name, default: 0] = saturate(variables[name, default: 0] - delta)
            case .multiplyVariable(let name, let value):
                try charge(&steps, limit)
                let factor = evaluate(value, .general)
                variables[name, default: 0] = saturate(variables[name, default: 0] * factor)
            case .divideVariable(let name, let value):
                try charge(&steps, limit)
                // Dividing by zero is a kid-friendly no-op — the box keeps
                // its value. inf/NaN must never reach the tortoise.
                let divisor = evaluate(value, .general)
                if divisor != 0 {
                    variables[name, default: 0] = saturate(variables[name, default: 0] / divisor)
                }
            case .defineBlock:
                // Naming a block is not doing it: the definition draws
                // nothing where it sits (pass one has already read it). It
                // still charges a step, so a definition inside a runaway loop
                // is bounded like everything else.
                try charge(&steps, limit)
            case .callBlock(let name):
                try charge(&steps, limit)
                // A name nothing defines is a no-op — the same "never an
                // error for a kid" line as an unset box reading 0, and the
                // reason a call can't dangle when its definition is deleted.
                guard let body = definitions[name] else { break }
                // Depth is checked on the way in, at the top of this function,
                // so a runaway call is stopped by the same guard that stops
                // runaway nesting.
                try expand(
                    body, into: &result, variables: &variables, steps: &steps,
                    using: &rng, limit: limit,
                    definitions: definitions, depth: depth + 1, nestingLimit: nestingLimit)
            }
        }
    }

    /// Pins a box's new value into ``NumberDomain/general``. Arithmetic is the
    /// one place a value can leave its range at run time — repeated `*=` runs
    /// away to infinity in a handful of iterations — and the editor can't
    /// prevent it, so the result saturates rather than erroring out (the same
    /// line taken for dividing by zero).
    private static func saturate(_ value: Double) -> Double {
        NumberDomain.general.clamp(value)
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
