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
    case penColor(BlockColor)
    /// ペンのふとさ
    case penWidth(NumberValue)

    // MARK: Fill
    /// ぬりのいろ
    case fillColor(BlockColor)
    /// ぬりはじめ
    case beginFill
    /// ぬりおわり
    case endFill

    // MARK: Control
    /// ◯かい くりかえす — the only tree-forming block in the initial set.
    case repeatBlock(count: NumberValue, body: [Block])
}
