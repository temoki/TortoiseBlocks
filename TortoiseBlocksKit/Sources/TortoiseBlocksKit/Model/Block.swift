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
    /// もし◯◯なら — runs its body when the condition holds, the else
    /// mouth otherwise. `elseBody` is optional *presence*: nil means the
    /// block has no else mouth at all (the pre-else shape), `[]` means the
    /// mouth exists but is still empty — the distinction is what the UI
    /// shows and what the document round-trips.
    case ifBlock(condition: Condition, body: [Block], elseBody: [Block]?)

    // MARK: Variables
    /// はこに いれる — set the named variable ("box") to the value.
    case setVariable(name: String, value: NumberValue)
    /// はこに たす — add the value to the named variable.
    case addVariable(name: String, value: NumberValue)
}

/// Which mouth of a container a sibling list lives in. Only the if block
/// has an `elseBody`; every other container addresses `.body`.
public enum BodySlot: Hashable, Sendable {
    case body
    case elseBody
}

/// Where a sibling list lives: the top level (`containerID == nil`, slot
/// `.body` by convention) or one mouth of a container block.
public struct BodyAddress: Hashable, Sendable {
    public var containerID: UUID?
    public var slot: BodySlot

    public init(containerID: UUID?, slot: BodySlot = .body) {
        self.containerID = containerID
        self.slot = slot
    }

    public static let topLevel = BodyAddress(containerID: nil)
}

extension BlockKind {
    /// Every child list this kind carries, in display order — empty for
    /// simple blocks. `BlockTree` and the workspace treat containers
    /// uniformly through this and ``replacingBody(_:with:)``, so a new
    /// container kind only has to show up here (the exhaustive switch
    /// walks you there) and provide its own header UI.
    public var containerBodies: [(slot: BodySlot, blocks: [Block])] {
        switch self {
        case .repeatBlock(_, let body):
            [(.body, body)]
        case .ifBlock(_, let body, let elseBody):
            if let elseBody {
                [(.body, body), (.elseBody, elseBody)]
            } else {
                [(.body, body)]
            }
        case .forward, .backward, .turnRight, .turnLeft, .home,
            .penUp, .penDown, .penColor, .penWidth,
            .fillColor, .beginFill, .endFill,
            .setVariable, .addVariable:
            []
        }
    }

    /// The primary child list (a repeat's body, an if's then mouth);
    /// nil for simple blocks.
    public var containerBody: [Block]? { body(for: .body) }

    /// The child list in the given mouth; nil when this kind doesn't have
    /// that mouth (simple blocks, or `.elseBody` of an if without else).
    public func body(for slot: BodySlot) -> [Block]? {
        containerBodies.first { $0.slot == slot }?.blocks
    }

    /// The same kind with one mouth's list replaced — the write half of
    /// ``body(for:)``. Returns `self` unchanged for simple blocks, so
    /// callers must check ``body(for:)`` first.
    func replacingBody(_ slot: BodySlot, with newBody: [Block]) -> BlockKind {
        switch self {
        case .repeatBlock(let count, _):
            .repeatBlock(count: count, body: newBody)
        case .ifBlock(let condition, let body, let elseBody):
            slot == .body
                ? .ifBlock(condition: condition, body: newBody, elseBody: elseBody)
                : .ifBlock(condition: condition, body: body, elseBody: newBody)
        case .forward, .backward, .turnRight, .turnLeft, .home,
            .penUp, .penDown, .penColor, .penWidth,
            .fillColor, .beginFill, .endFill,
            .setVariable, .addVariable:
            self
        }
    }
}
