import TortoiseCore

/// The color palette for pen and fill slots.
///
/// A closed, serialization-friendly set (raw string on the wire) that maps
/// onto the TortoiseCore presets. The raw values double as the generated
/// Swift code (`🐢.penColor = .red`), so they must stay aligned with the
/// library's preset names.
public enum BlockColor: String, Codable, Hashable, CaseIterable, Sendable {
    case black, white, red, green, blue, yellow, orange, purple, cyan, magenta

    /// The TortoiseCore preset this palette entry stands for.
    public var tortoiseColor: TortoiseCore.Color {
        switch self {
        case .black: .black
        case .white: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .yellow: .yellow
        case .orange: .orange
        case .purple: .purple
        case .cyan: .cyan
        case .magenta: .magenta
        }
    }

    /// Colors eligible for `ColorValue.random`'s draw — `white` is excluded
    /// since the canvas background is white and a white pen/fill vanishes.
    public static let randomizable: [BlockColor] = allCases.filter { $0 != .white }
}
