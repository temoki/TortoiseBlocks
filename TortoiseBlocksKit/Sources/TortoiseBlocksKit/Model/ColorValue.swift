/// A pen/fill color block argument: either a fixed palette color, or "roll
/// the dice" — a random pick re-evaluated on every execution.
///
/// Mirrors `NumberValue`'s literal/random split so color slots (pen, fill)
/// get the same randomness affordance as numeric ones.
public enum ColorValue: Hashable, Sendable {
    case literal(BlockColor)
    case random
}

extension ColorValue {
    /// Evaluates the value, drawing from `rng` for the random case.
    /// See `BlockColor.randomizable` for the excluded-white draw pool.
    func evaluated(using rng: inout some RandomNumberGenerator) -> BlockColor {
        switch self {
        case .literal(let color):
            return color
        case .random:
            return BlockColor.randomizable.randomElement(using: &rng)!
        }
    }
}
