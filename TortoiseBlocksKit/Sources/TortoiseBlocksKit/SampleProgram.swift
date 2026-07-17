import TortoiseCore

/// Hardcoded command streams for the M0 walking skeleton.
/// Replaced by `BlockExpander` output once the block model lands (M1).
public enum SampleProgram {
    /// A 36-point orange star (the TortoiseGraphics2 README example).
    public static func star() -> [TortoiseCommand] {
        var commands: [TortoiseCommand] = [
            .penColor(.orange),
            .penWidth(2),
        ]
        for _ in 1...36 {
            commands.append(.forward(200))
            commands.append(.rotate(170))
        }
        return commands
    }

    /// A filled square — exercises pen color, fill, and rotation.
    public static func filledSquare() -> [TortoiseCommand] {
        var commands: [TortoiseCommand] = [
            .penColor(.blue),
            .fillColor(.cyan),
            .penWidth(3),
            .beginFill,
        ]
        for _ in 1...4 {
            commands.append(.forward(120))
            commands.append(.rotate(90))
        }
        commands.append(.endFill)
        return commands
    }
}
