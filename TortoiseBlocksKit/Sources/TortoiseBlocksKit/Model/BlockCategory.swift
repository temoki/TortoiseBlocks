/// Palette category — drives grouping and the category color in the UI.
public enum BlockCategory: Hashable, CaseIterable, Sendable {
    case movement
    case pen
    case fill
    case control
    case variables
    case functions
}

extension BlockKind {
    public var category: BlockCategory {
        switch self {
        case .forward, .backward, .turnRight, .turnLeft, .home:
            .movement
        case .penUp, .penDown, .penColor, .penWidth:
            .pen
        case .fillColor, .beginFill, .endFill:
            .fill
        case .repeatBlock, .ifBlock:
            .control
        case .setVariable, .addVariable, .subtractVariable, .multiplyVariable, .divideVariable:
            .variables
        case .defineBlock, .callBlock:
            .functions
        }
    }
}
