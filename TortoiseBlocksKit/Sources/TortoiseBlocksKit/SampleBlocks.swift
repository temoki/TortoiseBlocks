/// Sample block programs — the block-tree counterpart of `SampleProgram`,
/// exercising repeat + random end to end until the editor (M2) exists.
public enum SampleBlocks {
    /// A 36-point orange star — deterministic, unlike `randomStar()`, so it
    /// always comes out the same tidy shape (matches `SampleProgram.star()`).
    public static func star() -> [Block] {
        [
            Block(kind: .penColor(.orange)),
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
            Block(kind: .penColor(.purple)),
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

    /// A filled square — fill color, four repeated sides, then close the fill.
    public static func filledSquare() -> [Block] {
        [
            Block(kind: .fillColor(.cyan)),
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
