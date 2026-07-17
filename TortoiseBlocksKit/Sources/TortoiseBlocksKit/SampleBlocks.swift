/// Sample block programs — the block-tree counterpart of `SampleProgram`,
/// exercising repeat + random end to end until the editor (M2) exists.
public enum SampleBlocks {
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
}
