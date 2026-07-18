/// A numeric block argument: a literal, "roll the dice" — a random value
/// re-evaluated on every execution — or a variable ("box") reference.
///
/// Random and variable are *values*, not standalone blocks, so they can plug
/// into any numeric slot (distance, degrees, width, repeat count) — the same
/// flexibility Scratch gives its reporter blocks.
public enum NumberValue: Hashable, Sendable {
    case literal(Double)
    case random(min: Double, max: Double)
    /// The name *is* the identity — a variable exists by appearing in the
    /// tree, there is no separate registry (see `BlockTree.usedVariableNames`).
    case variable(String)
}

extension NumberValue {
    /// Evaluates the value, drawing from `rng` for the random case and from
    /// `variables` for a variable reference (an unset variable reads 0 —
    /// kid-friendly, never an error).
    /// An inverted range (min > max) is normalized instead of trapping.
    func evaluated(
        variables: [String: Double],
        using rng: inout some RandomNumberGenerator
    ) -> Double {
        switch self {
        case .literal(let value):
            return value
        case .random(let min, let max):
            let range = min <= max ? min...max : max...min
            return Double.random(in: range, using: &rng)
        case .variable(let name):
            return variables[name] ?? 0
        }
    }
}
