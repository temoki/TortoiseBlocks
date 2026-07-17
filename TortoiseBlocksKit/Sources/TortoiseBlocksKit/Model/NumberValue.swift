/// A numeric block argument: either a literal, or "roll the dice" —
/// a random value re-evaluated on every execution.
///
/// Random is a *value*, not a standalone block, so it can plug into any
/// numeric slot (distance, degrees, width, repeat count) — the same
/// flexibility Scratch gives its reporter blocks.
public enum NumberValue: Hashable, Sendable {
    case literal(Double)
    case random(min: Double, max: Double)
}

extension NumberValue {
    /// Evaluates the value, drawing from `rng` for the random case.
    /// An inverted range (min > max) is normalized instead of trapping.
    func evaluated(using rng: inout some RandomNumberGenerator) -> Double {
        switch self {
        case .literal(let value):
            return value
        case .random(let min, let max):
            let range = min <= max ? min...max : max...min
            return Double.random(in: range, using: &rng)
        }
    }
}
