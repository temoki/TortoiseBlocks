/// Renders a block tree as the equivalent Swift source (Tortoise API) —
/// the learning bridge from blocks to text programming.
///
/// The output is language-independent (API names as-is) and mirrors what
/// `BlockExpander` executes: a repeat becomes a `for` loop, a random value
/// becomes `Double.random(in:)` (`Int.random(in:)` for repeat counts), and
/// every used variable becomes a `var name = 0.0` declaration up front
/// (matching the expander's "unset reads 0" rule).
public enum SwiftCodeGenerator {
    public static func code(for blocks: [Block]) -> String {
        var lines = ["let 🐢 = Tortoise()"]
        for name in BlockTree.usedVariableNames(in: blocks) {
            lines.append("var \(name) = 0.0")
        }
        append(blocks, to: &lines, indent: 0)
        return lines.joined(separator: "\n")
    }

    private static func append(_ blocks: [Block], to lines: inout [String], indent: Int) {
        let pad = String(repeating: "    ", count: indent)
        for block in blocks {
            switch block.kind {
            case .forward(let value):
                lines.append("\(pad)🐢.forward(\(doubleExpression(value)))")
            case .backward(let value):
                lines.append("\(pad)🐢.backward(\(doubleExpression(value)))")
            case .turnRight(let value):
                lines.append("\(pad)🐢.right(\(doubleExpression(value)))")
            case .turnLeft(let value):
                lines.append("\(pad)🐢.left(\(doubleExpression(value)))")
            case .home:
                lines.append("\(pad)🐢.home()")
            case .penUp:
                lines.append("\(pad)🐢.penUp()")
            case .penDown:
                lines.append("\(pad)🐢.penDown()")
            case .penColor(let color):
                lines.append("\(pad)🐢.penColor = \(colorExpression(color))")
            case .penWidth(let value):
                lines.append("\(pad)🐢.penWidth = \(doubleExpression(value))")
            case .fillColor(let color):
                lines.append("\(pad)🐢.fillColor = \(colorExpression(color))")
            case .beginFill:
                lines.append("\(pad)🐢.beginFill()")
            case .endFill:
                lines.append("\(pad)🐢.endFill()")
            case .repeatBlock(let count, let body):
                lines.append("\(pad)for _ in 1...\(countExpression(count)) {")
                append(body, to: &lines, indent: indent + 1)
                lines.append("\(pad)}")
            case .ifBlock(let condition, let body, let elseBody):
                lines.append("\(pad)if \(conditionExpression(condition)) {")
                append(body, to: &lines, indent: indent + 1)
                if let elseBody {
                    lines.append("\(pad)} else {")
                    append(elseBody, to: &lines, indent: indent + 1)
                }
                lines.append("\(pad)}")
            case .setVariable(let name, let value):
                lines.append("\(pad)\(name) = \(doubleExpression(value))")
            case .addVariable(let name, let value):
                lines.append("\(pad)\(name) += \(doubleExpression(value))")
            case .subtractVariable(let name, let value):
                lines.append("\(pad)\(name) -= \(doubleExpression(value))")
            case .multiplyVariable(let name, let value):
                lines.append("\(pad)\(name) *= \(doubleExpression(value))")
            case .divideVariable(let name, let value):
                lines.append("\(pad)\(name) /= \(doubleExpression(value))")
            }
        }
    }

    // MARK: - Value formatting

    private static func conditionExpression(_ condition: Condition) -> String {
        "\(doubleExpression(condition.lhs)) \(condition.comparison.swiftOperator) "
            + doubleExpression(condition.rhs)
    }

    private static func doubleExpression(_ value: NumberValue) -> String {
        switch value {
        case .literal(let value):
            return format(value)
        case .random(let min, let max):
            return "Double.random(in: \(format(min))...\(format(max)))"
        case .variable(let name):
            return name
        }
    }

    private static func countExpression(_ value: NumberValue) -> String {
        switch value {
        case .literal(let value):
            return format(value)
        case .random(let min, let max):
            return "Int.random(in: \(format(min))...\(format(max)))"
        case .variable(let name):
            return "Int(\(name))"
        }
    }

    private static func colorExpression(_ value: ColorValue) -> String {
        switch value {
        case .literal(let color):
            return ".\(color.rawValue)"
        case .random:
            let cases = BlockColor.randomizable.map { ".\($0.rawValue)" }.joined(separator: ", ")
            return "[\(cases)].randomElement()!"
        }
    }

    /// Formats a number the way a person would write it in source:
    /// integral values without the trailing `.0`.
    private static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
