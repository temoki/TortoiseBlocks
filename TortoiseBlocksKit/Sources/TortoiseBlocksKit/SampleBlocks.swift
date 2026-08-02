/// Ready-made block programs. `star()`, `filledSquare()`, and `spiral()` are
/// the one-tap starting points an empty workspace offers (they go in through
/// the normal editing path, so they undo and dirty the document like any
/// other edit); `randomStar()` is the fixture the expander and Codable tests
/// build on.
public enum SampleBlocks {
    /// A 36-point orange star — deterministic, unlike `randomStar()`, so it
    /// always comes out the same tidy shape (matches `SampleProgram.star()`).
    public static func star() -> [Block] {
        [
            Block(kind: .penColor(.literal(.orange))),
            Block(kind: .penWidth(.literal(2))),
            Block(
                kind: .repeatBlock(
                    count: .literal(36),
                    body: [
                        Block(kind: .forward(.literal(200))),
                        Block(kind: .turnRight(.literal(170))),
                    ]
                )),
        ]
    }

    /// A 36-point star whose ray lengths are rolled per iteration.
    public static func randomStar() -> [Block] {
        [
            Block(kind: .penColor(.literal(.purple))),
            Block(kind: .penWidth(.literal(2))),
            Block(
                kind: .repeatBlock(
                    count: .literal(36),
                    body: [
                        Block(kind: .forward(.random(min: 100, max: 200))),
                        Block(kind: .turnRight(.literal(170))),
                    ]
                )),
        ]
    }

    /// A rotating square spiral — the step lives in a box (variable) that
    /// grows every lap, showcasing set/add + a variable in a value slot.
    public static func spiral() -> [Block] {
        [
            Block(kind: .penColor(.literal(.blue))),
            Block(kind: .penWidth(.literal(2))),
            Block(kind: .setVariable(name: "🌟", value: .literal(5))),
            Block(
                kind: .repeatBlock(
                    count: .literal(40),
                    body: [
                        Block(kind: .forward(.variable("🌟"))),
                        Block(kind: .turnRight(.literal(92))),
                        Block(kind: .addVariable(name: "🌟", value: .literal(5))),
                    ]
                )),
        ]
    }

    /// A filled square — fill color, four repeated sides, then close the fill.
    public static func filledSquare() -> [Block] {
        [
            Block(kind: .fillColor(.literal(.cyan))),
            Block(kind: .beginFill),
            Block(
                kind: .repeatBlock(
                    count: .literal(4),
                    body: [
                        Block(kind: .forward(.literal(100))),
                        Block(kind: .turnRight(.literal(90))),
                    ]
                )),
            Block(kind: .endFill),
        ]
    }
}
