/// How an if block compares its two values.
///
/// The raw strings are the wire format (frozen). Five operators instead of
/// Scratch's three because the flagship kid use case — "the dice shows 4 or
/// more" — needs ≥, and adding one after freezing would cost a schema bump.
public enum Comparison: String, Codable, Hashable, CaseIterable, Sendable {
    case less
    case lessOrEqual
    case equal
    case greaterOrEqual
    case greater

    /// The Swift operator this stands for — used verbatim by the code pane.
    public var swiftOperator: String {
        switch self {
        case .less: "<"
        case .lessOrEqual: "<="
        case .equal: "=="
        case .greaterOrEqual: ">="
        case .greater: ">"
        }
    }

    func holds(_ lhs: Double, _ rhs: Double) -> Bool {
        switch self {
        case .less: lhs < rhs
        case .lessOrEqual: lhs <= rhs
        case .equal: lhs == rhs
        case .greaterOrEqual: lhs >= rhs
        case .greater: lhs > rhs
        }
    }
}

/// An if block's test: two ordinary number slots around a comparison, so a
/// condition can compare literals, dice, and boxes in any combination —
/// "the dice shows 4 or more", "the counter box reached 3", and so on.
///
/// Equality is exact `Double` equality: right for the counter-variable
/// pattern (integer accumulation is exact), while continuous dice values
/// pair with the ordering operators instead.
public struct Condition: Hashable, Codable, Sendable {
    public var lhs: NumberValue
    public var comparison: Comparison
    public var rhs: NumberValue

    public init(lhs: NumberValue, comparison: Comparison, rhs: NumberValue) {
        self.lhs = lhs
        self.comparison = comparison
        self.rhs = rhs
    }

    /// Wire keys (frozen) — spelled out so renaming the properties can't
    /// silently change the document format.
    private enum CodingKeys: String, CodingKey {
        case lhs
        case comparison
        case rhs
    }
}

extension Condition {
    /// Evaluates both sides and applies the comparison. Called once per
    /// encounter, so dice in a condition re-roll every time (same rule as
    /// values in a repeat body).
    func holds(
        variables: [String: Double],
        using rng: inout some RandomNumberGenerator
    ) -> Bool {
        comparison.holds(
            lhs.evaluated(variables: variables, using: &rng),
            rhs.evaluated(variables: variables, using: &rng)
        )
    }
}
