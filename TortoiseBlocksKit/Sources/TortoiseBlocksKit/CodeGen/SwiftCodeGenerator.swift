/// Renders a block tree as the equivalent Swift source (Tortoise API) —
/// the learning bridge from blocks to text programming.
///
/// The output is language-independent (API names as-is) and mirrors what
/// `BlockExpander` executes: a repeat becomes a `for` loop, a random value
/// becomes `Double.random(in:)` (`Int.random(in:)` for repeat counts).
public enum SwiftCodeGenerator {
    public static func code(for blocks: [Block]) -> String {
        var lines = ["let 🐢 = Tortoise()"]
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
                lines.append("\(pad)🐢.penColor = .\(color.rawValue)")
            case .penWidth(let value):
                lines.append("\(pad)🐢.penWidth = \(doubleExpression(value))")
            case .fillColor(let color):
                lines.append("\(pad)🐢.fillColor = .\(color.rawValue)")
            case .beginFill:
                lines.append("\(pad)🐢.beginFill()")
            case .endFill:
                lines.append("\(pad)🐢.endFill()")
            case .repeatBlock(let count, let body):
                lines.append("\(pad)for _ in 1...\(countExpression(count)) {")
                append(body, to: &lines, indent: indent + 1)
                lines.append("\(pad)}")
            }
        }
    }

    // MARK: - Value formatting

    private static func doubleExpression(_ value: NumberValue) -> String {
        switch value {
        case .literal(let value):
            return format(value)
        case .random(let min, let max):
            return "Double.random(in: \(format(min))...\(format(max)))"
        }
    }

    private static func countExpression(_ value: NumberValue) -> String {
        switch value {
        case .literal(let value):
            return format(value)
        case .random(let min, let max):
            return "Int.random(in: \(format(min))...\(format(max)))"
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
