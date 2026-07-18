import Foundation

/// JSON serialization for the block model — the `.tortoiseblocks` document
/// format, so the wire format is a long-term contract.
///
/// Same discipline as TortoiseGraphics2's command serialization: explicit
/// coding keys and hand-written encode/decode decouple the format from
/// Swift identifier names. A case (or `NumberValue` variant) encodes as an
/// object with exactly one key; decode rejects anything else. Unknown
/// fields *inside* a payload are tolerated (future payload extensions).

/// Accepts any key; used to count the raw keys of a single-key object so an
/// unknown key riding alongside a known one is rejected, not ignored.
private struct RawCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func singleKnownKey<Keys: CodingKey>(
    of decoder: any Decoder, as keys: Keys.Type
) throws -> Keys {
    let rawKeys = try decoder.container(keyedBy: RawCodingKey.self).allKeys
    guard rawKeys.count == 1, let rawKey = rawKeys.first,
        let key = Keys(stringValue: rawKey.stringValue)
    else {
        let found = rawKeys.map(\.stringValue).sorted().joined(separator: ", ")
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected an object with exactly one known key, found: [\(found)]"
            ))
    }
    return key
}

// MARK: - NumberValue

extension NumberValue: Codable {
    /// Wire format: `{"literal":100}` / `{"random":{"min":50,"max":150}}` /
    /// `{"variable":"🌟"}`. The variable shape is what bumps a document to
    /// schema version 2 (`BlocksProject.requiredSchemaVersion`).
    private enum CodingKeys: String, CodingKey {
        case literal
        case random
        case variable
    }

    private enum RandomKeys: String, CodingKey {
        case min
        case max
    }

    public init(from decoder: any Decoder) throws {
        let key = try singleKnownKey(of: decoder, as: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch key {
        case .literal:
            self = .literal(try container.decode(Double.self, forKey: .literal))
        case .random:
            let payload = try container.nestedContainer(keyedBy: RandomKeys.self, forKey: .random)
            self = .random(
                min: try payload.decode(Double.self, forKey: .min),
                max: try payload.decode(Double.self, forKey: .max)
            )
        case .variable:
            self = .variable(try container.decode(String.self, forKey: .variable))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .literal(let value):
            try container.encode(value, forKey: .literal)
        case .random(let min, let max):
            var payload = container.nestedContainer(keyedBy: RandomKeys.self, forKey: .random)
            try payload.encode(min, forKey: .min)
            try payload.encode(max, forKey: .max)
        case .variable(let name):
            try container.encode(name, forKey: .variable)
        }
    }
}

// MARK: - ColorValue

extension ColorValue: Codable {
    /// Wire format: a bare preset string for `.literal` — unchanged from
    /// the pre-`ColorValue` format, so old files decode as-is and new
    /// literal-only files stay byte-identical to what an older app would
    /// write — or `{"random":{}}` for `.random`.
    private enum CodingKeys: String, CodingKey {
        case random
    }

    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
            let color = try? container.decode(BlockColor.self)
        {
            self = .literal(color)
            return
        }
        _ = try singleKnownKey(of: decoder, as: CodingKeys.self)
        self = .random
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .literal(let color):
            var container = encoder.singleValueContainer()
            try container.encode(color)
        case .random:
            var container = encoder.container(keyedBy: CodingKeys.self)
            _ = container.nestedContainer(keyedBy: RawCodingKey.self, forKey: .random)
        }
    }
}

// MARK: - BlockKind

extension BlockKind: Codable {
    /// Wire-format block names — the serialized contract, independent of
    /// Swift case names (note `repeatBlock` → `"repeat"`).
    ///
    /// When adding a block kind: add a key here, handle it in both switches
    /// below, add a fixture to `BlockCodableTests.kindFixtures`, and cover
    /// it in `BlockExpanderTests` / `SwiftCodeGeneratorTests`. Only the
    /// switches are compiler-enforced.
    private enum CodingKeys: String, CodingKey {
        case forward
        case backward
        case turnRight
        case turnLeft
        case home
        case penUp
        case penDown
        case penColor
        case penWidth
        case fillColor
        case beginFill
        case endFill
        case repeatBlock = "repeat"
        case ifBlock = "if"
        case setVariable
        case addVariable
        case subtractVariable
        case multiplyVariable
        case divideVariable
    }

    private enum RepeatKeys: String, CodingKey {
        case count
        case body
    }

    /// `elseBody` is optional on the wire: absent = no else mouth (the
    /// pre-else shape, so older files decode as-is and else-free blocks
    /// stay byte-identical), `[]` = the mouth exists but is empty.
    private enum IfKeys: String, CodingKey {
        case condition
        case body
        case elseBody
    }

    private enum VariableKeys: String, CodingKey {
        case name
        case value
    }

    public init(from decoder: any Decoder) throws {
        let key = try singleKnownKey(of: decoder, as: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func number() throws -> NumberValue {
            try container.decode(NumberValue.self, forKey: key)
        }
        func color() throws -> ColorValue {
            try container.decode(ColorValue.self, forKey: key)
        }

        switch key {
        case .forward: self = .forward(try number())
        case .backward: self = .backward(try number())
        case .turnRight: self = .turnRight(try number())
        case .turnLeft: self = .turnLeft(try number())
        case .home: self = .home
        case .penUp: self = .penUp
        case .penDown: self = .penDown
        case .penColor: self = .penColor(try color())
        case .penWidth: self = .penWidth(try number())
        case .fillColor: self = .fillColor(try color())
        case .beginFill: self = .beginFill
        case .endFill: self = .endFill
        case .repeatBlock:
            let payload = try container.nestedContainer(
                keyedBy: RepeatKeys.self, forKey: .repeatBlock)
            self = .repeatBlock(
                count: try payload.decode(NumberValue.self, forKey: .count),
                body: try payload.decode([Block].self, forKey: .body)
            )
        case .ifBlock:
            let payload = try container.nestedContainer(keyedBy: IfKeys.self, forKey: .ifBlock)
            self = .ifBlock(
                condition: try payload.decode(Condition.self, forKey: .condition),
                body: try payload.decode([Block].self, forKey: .body),
                elseBody: try payload.decodeIfPresent([Block].self, forKey: .elseBody)
            )
        case .setVariable:
            let payload = try container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .setVariable)
            self = .setVariable(
                name: try payload.decode(String.self, forKey: .name),
                value: try payload.decode(NumberValue.self, forKey: .value)
            )
        case .addVariable:
            let payload = try container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .addVariable)
            self = .addVariable(
                name: try payload.decode(String.self, forKey: .name),
                value: try payload.decode(NumberValue.self, forKey: .value)
            )
        case .subtractVariable:
            let payload = try container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .subtractVariable)
            self = .subtractVariable(
                name: try payload.decode(String.self, forKey: .name),
                value: try payload.decode(NumberValue.self, forKey: .value)
            )
        case .multiplyVariable:
            let payload = try container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .multiplyVariable)
            self = .multiplyVariable(
                name: try payload.decode(String.self, forKey: .name),
                value: try payload.decode(NumberValue.self, forKey: .value)
            )
        case .divideVariable:
            let payload = try container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .divideVariable)
            self = .divideVariable(
                name: try payload.decode(String.self, forKey: .name),
                value: try payload.decode(NumberValue.self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        func encodeEmpty(_ key: CodingKeys) {
            _ = container.nestedContainer(keyedBy: RepeatKeys.self, forKey: key)
        }

        switch self {
        case .forward(let value):
            try container.encode(value, forKey: .forward)
        case .backward(let value):
            try container.encode(value, forKey: .backward)
        case .turnRight(let value):
            try container.encode(value, forKey: .turnRight)
        case .turnLeft(let value):
            try container.encode(value, forKey: .turnLeft)
        case .home:
            encodeEmpty(.home)
        case .penUp:
            encodeEmpty(.penUp)
        case .penDown:
            encodeEmpty(.penDown)
        case .penColor(let color):
            try container.encode(color, forKey: .penColor)
        case .penWidth(let value):
            try container.encode(value, forKey: .penWidth)
        case .fillColor(let color):
            try container.encode(color, forKey: .fillColor)
        case .beginFill:
            encodeEmpty(.beginFill)
        case .endFill:
            encodeEmpty(.endFill)
        case .repeatBlock(let count, let body):
            var payload = container.nestedContainer(keyedBy: RepeatKeys.self, forKey: .repeatBlock)
            try payload.encode(count, forKey: .count)
            try payload.encode(body, forKey: .body)
        case .ifBlock(let condition, let body, let elseBody):
            var payload = container.nestedContainer(keyedBy: IfKeys.self, forKey: .ifBlock)
            try payload.encode(condition, forKey: .condition)
            try payload.encode(body, forKey: .body)
            try payload.encodeIfPresent(elseBody, forKey: .elseBody)
        case .setVariable(let name, let value):
            var payload = container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .setVariable)
            try payload.encode(name, forKey: .name)
            try payload.encode(value, forKey: .value)
        case .addVariable(let name, let value):
            var payload = container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .addVariable)
            try payload.encode(name, forKey: .name)
            try payload.encode(value, forKey: .value)
        case .subtractVariable(let name, let value):
            var payload = container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .subtractVariable)
            try payload.encode(name, forKey: .name)
            try payload.encode(value, forKey: .value)
        case .multiplyVariable(let name, let value):
            var payload = container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .multiplyVariable)
            try payload.encode(name, forKey: .name)
            try payload.encode(value, forKey: .value)
        case .divideVariable(let name, let value):
            var payload = container.nestedContainer(
                keyedBy: VariableKeys.self, forKey: .divideVariable)
            try payload.encode(name, forKey: .name)
            try payload.encode(value, forKey: .value)
        }
    }
}
