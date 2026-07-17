import Foundation
import Testing

@testable import TortoiseBlocksKit

@Suite("Block model Codable")
struct BlockCodableTests {
    private static let childID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Every `BlockKind` case paired with its frozen wire format
    /// (keys sorted, as produced by `.sortedKeys`). These strings are the
    /// `.tortoiseblocks` document contract — breaking one breaks users'
    /// saved files and must not ship without a schema migration.
    private static let kindFixtures: [(kind: BlockKind, json: String)] = [
        (.forward(.literal(100)), #"{"forward":{"literal":100}}"#),
        (
            .backward(.random(min: 50, max: 150)),
            #"{"backward":{"random":{"max":150,"min":50}}}"#
        ),
        (.turnRight(.literal(90)), #"{"turnRight":{"literal":90}}"#),
        (.turnLeft(.literal(45.5)), #"{"turnLeft":{"literal":45.5}}"#),
        (.home, #"{"home":{}}"#),
        (.penUp, #"{"penUp":{}}"#),
        (.penDown, #"{"penDown":{}}"#),
        (.penColor(.red), #"{"penColor":"red"}"#),
        (.penWidth(.literal(3)), #"{"penWidth":{"literal":3}}"#),
        (.fillColor(.cyan), #"{"fillColor":"cyan"}"#),
        (.beginFill, #"{"beginFill":{}}"#),
        (.endFill, #"{"endFill":{}}"#),
        (
            .repeatBlock(
                count: .literal(4),
                body: [Block(id: childID, kind: .forward(.literal(10)))]
            ),
            #"{"repeat":{"body":[{"id":"00000000-0000-0000-0000-000000000001","kind":{"forward":{"literal":10}}}],"count":{"literal":4}}}"#
        ),
    ]

    private static func sortedKeysJSON(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test("every block kind encodes to its frozen wire format", arguments: kindFixtures)
    func kindEncodesToWireFormat(kind: BlockKind, expected: String) throws {
        #expect(try Self.sortedKeysJSON(kind) == expected)
    }

    @Test("every block kind decodes from its frozen wire format", arguments: kindFixtures)
    func kindDecodesFromWireFormat(expected: BlockKind, json: String) throws {
        let decoded = try JSONDecoder().decode(BlockKind.self, from: Data(json.utf8))
        #expect(decoded == expected)
    }

    @Test("a project with nested repeats round-trips through JSON")
    func projectRoundTrip() throws {
        let project = BlocksProject(
            title: "ほし",
            blocks: SampleBlocks.randomStar() + [
                Block(
                    kind: .repeatBlock(
                        count: .random(min: 2, max: 5),
                        body: [
                            Block(
                                kind: .repeatBlock(
                                    count: .literal(3),
                                    body: [Block(kind: .home)]
                                ))
                        ]
                    ))
            ]
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(BlocksProject.self, from: data)
        #expect(decoded == project)
        #expect(decoded.schemaVersion == BlocksProject.currentSchemaVersion)
    }

    @Test("an unknown block kind fails to decode")
    func unknownKindFails() {
        let json = #"{"teleport":{"literal":100}}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BlockKind.self, from: Data(json.utf8))
        }
    }

    @Test("an unknown key alongside a known kind fails to decode")
    func mixedKnownAndUnknownKeysFail() {
        let json = #"{"home":{},"teleport":{}}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BlockKind.self, from: Data(json.utf8))
        }
    }

    @Test("unrecognized fields inside a payload are ignored")
    func extraPayloadFieldsAreIgnored() throws {
        let json = #"{"repeat":{"count":{"literal":2},"body":[],"comment":"future"}}"#
        let decoded = try JSONDecoder().decode(BlockKind.self, from: Data(json.utf8))
        #expect(decoded == .repeatBlock(count: .literal(2), body: []))
    }

    @Test("a newer schemaVersion still decodes, preserving the value")
    func newerSchemaVersionDecodes() throws {
        // The app decides how to surface this; the model layer just
        // preserves the number instead of failing or mangling it.
        let json = #"{"schemaVersion":99,"title":"future","blocks":[]}"#
        let decoded = try JSONDecoder().decode(BlocksProject.self, from: Data(json.utf8))
        #expect(decoded.schemaVersion == 99)
    }
}
