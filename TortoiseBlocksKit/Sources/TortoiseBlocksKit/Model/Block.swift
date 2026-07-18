import Foundation

/// One block in the workspace: a stable identity plus what the block does.
///
/// Blocks form a tree — control blocks (``BlockKind/repeatBlock(count:body:)``)
/// carry child blocks. The `id` is the anchor for everything identity-based:
/// SwiftUI lists, drag & drop, and highlighting the executing block via
/// `ExpandedCommand.blockID`.
public struct Block: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: BlockKind

    public init(id: UUID = UUID(), kind: BlockKind) {
        self.id = id
        self.kind = kind
    }
}

/// What a block does. One case per palette entry.
///
/// Adding a case: handle it in `BlockKind`'s Codable extension (see the
/// checklist there), in `BlockExpander`, and in `SwiftCodeGenerator` —
/// the latter two are exhaustive switches, so the compiler walks you there.
public enum BlockKind: Hashable, Sendable {
    // MARK: Movement
    /// まえへ すすむ
    case forward(NumberValue)
    /// うしろへ さがる
    case backward(NumberValue)
    /// みぎへ まわる (degrees)
    case turnRight(NumberValue)
    /// ひだりへ まわる (degrees)
    case turnLeft(NumberValue)
    /// ホームへ もどる
    case home

    // MARK: Pen
    /// ペンを あげる
    case penUp
    /// ペンを おろす
    case penDown
    /// ペンのいろ
    case penColor(ColorValue)
    /// ペンのふとさ
    case penWidth(NumberValue)

    // MARK: Fill
    /// ぬりのいろ
    case fillColor(ColorValue)
    /// ぬりはじめ
    case beginFill
    /// ぬりおわり
    case endFill

    // MARK: Control
    /// ◯かい くりかえす — repeats its body.
    case repeatBlock(count: NumberValue, body: [Block])
    /// もし◯◯なら — runs its body when the condition holds.
    case ifBlock(condition: Condition, body: [Block])

    // MARK: Variables
    /// はこに いれる — set the named variable ("box") to the value.
    case setVariable(name: String, value: NumberValue)
    /// はこに たす — add the value to the named variable.
    case addVariable(name: String, value: NumberValue)
}

extension BlockKind {
    /// The nested child list for container kinds (repeat, if); nil for
    /// simple blocks. `BlockTree` and the workspace treat containers
    /// uniformly through this pair, so a new container kind only has to
    /// show up here (the exhaustive switch walks you there) and provide
    /// its own header UI.
    public var containerBody: [Block]? {
        switch self {
        case .repeatBlock(_, let body), .ifBlock(_, let body):
            body
        case .forward, .backward, .turnRight, .turnLeft, .home,
            .penUp, .penDown, .penColor, .penWidth,
            .fillColor, .beginFill, .endFill,
            .setVariable, .addVariable:
            nil
        }
    }

    /// The same kind with its body replaced — the write half of
    /// ``containerBody``. Returns `self` unchanged for simple blocks, so
    /// callers must check ``containerBody`` first.
    func replacingBody(with newBody: [Block]) -> BlockKind {
        switch self {
        case .repeatBlock(let count, _):
            .repeatBlock(count: count, body: newBody)
        case .ifBlock(let condition, _):
            .ifBlock(condition: condition, body: newBody)
        case .forward, .backward, .turnRight, .turnLeft, .home,
            .penUp, .penDown, .penColor, .penWidth,
            .fillColor, .beginFill, .endFill,
            .setVariable, .addVariable:
            self
        }
    }
}
