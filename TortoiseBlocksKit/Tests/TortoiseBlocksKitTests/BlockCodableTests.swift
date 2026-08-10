import Foundation
import Testing

@testable import TortoiseBlocksKit

@Suite("Block model Codable")
struct BlockCodableTests {
    private static let childID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Every `BlockKind` case paired with its frozen wire format
    /// (keys sorted, as produced by `.sortedKeys`). These strings are the
    /// `.tortoise` document contract — breaking one breaks users'
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
        // Bare preset strings — unchanged from before `ColorValue` existed,
        // so old files decode as-is and new literal-only files stay
        // byte-identical to what an older app would have written.
        (.penColor(.literal(.red)), #"{"penColor":"red"}"#),
        (.penWidth(.literal(3)), #"{"penWidth":{"literal":3}}"#),
        (.fillColor(.literal(.cyan)), #"{"fillColor":"cyan"}"#),
        (.beginFill, #"{"beginFill":{}}"#),
        (.endFill, #"{"endFill":{}}"#),
        (
            .repeatBlock(
                count: .literal(4),
                body: [Block(id: childID, kind: .forward(.literal(10)))]
            ),
            #"{"repeat":{"body":[{"id":"00000000-0000-0000-0000-000000000001","kind":{"forward":{"literal":10}}}],"count":{"literal":4}}}"#
        ),
        // Schema version 2 (variables + if): a bare name string for a
        // reference, name + value payloads for the set/add blocks, and a
        // condition (lhs/comparison/rhs) + body payload for the if block.
        (.forward(.variable("🌟")), #"{"forward":{"variable":"🌟"}}"#),
        (
            .ifBlock(
                condition: Condition(
                    lhs: .random(min: 1, max: 6), comparison: .greaterOrEqual, rhs: .literal(4)),
                body: [Block(id: childID, kind: .home)], elseBody: nil),
            #"{"if":{"body":[{"id":"00000000-0000-0000-0000-000000000001","kind":{"home":{}}}],"condition":{"comparison":"greaterOrEqual","lhs":{"random":{"max":6,"min":1}},"rhs":{"literal":4}}}}"#
        ),
        // The else mouth is optional presence: key absent = no mouth (the
        // fixture above), present = mouth exists — even when empty.
        (
            .ifBlock(
                condition: Condition(lhs: .variable("🌟"), comparison: .less, rhs: .literal(3)),
                body: [],
                elseBody: [Block(id: childID, kind: .penUp)]
            ),
            #"{"if":{"body":[],"condition":{"comparison":"less","lhs":{"variable":"🌟"},"rhs":{"literal":3}},"elseBody":[{"id":"00000000-0000-0000-0000-000000000001","kind":{"penUp":{}}}]}}"#
        ),
        (
            .setVariable(name: "🌟", value: .literal(10)),
            #"{"setVariable":{"name":"🌟","value":{"literal":10}}}"#
        ),
        (
            .addVariable(name: "💖", value: .random(min: 1, max: 6)),
            #"{"addVariable":{"name":"💖","value":{"random":{"max":6,"min":1}}}}"#
        ),
        (
            .subtractVariable(name: "🌟", value: .literal(5)),
            #"{"subtractVariable":{"name":"🌟","value":{"literal":5}}}"#
        ),
        (
            .multiplyVariable(name: "🌟", value: .literal(2)),
            #"{"multiplyVariable":{"name":"🌟","value":{"literal":2}}}"#
        ),
        (
            .divideVariable(name: "🌟", value: .literal(2)),
            #"{"divideVariable":{"name":"🌟","value":{"literal":2}}}"#
        ),
        // Schema version 3 (blocks the child defines): name + body for the
        // definition, and a name payload — not a bare string — for the call.
        (
            .defineBlock(name: "き", body: [Block(id: childID, kind: .forward(.literal(10)))]),
            #"{"define":{"body":[{"id":"00000000-0000-0000-0000-000000000001","kind":{"forward":{"literal":10}}}],"name":"き"}}"#
        ),
        (.callBlock(name: "き"), #"{"call":{"name":"き"}}"#),
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

    @Test("a random color block round-trips through JSON")
    func randomColorRoundTrips() throws {
        let kind = BlockKind.penColor(.random)
        let json = try Self.sortedKeysJSON(kind)
        #expect(json == #"{"penColor":{"random":{}}}"#)
        let decoded = try JSONDecoder().decode(BlockKind.self, from: Data(json.utf8))
        #expect(decoded == kind)
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

    @Test("an empty else mouth is preserved on the wire")
    func emptyElseMouthRoundTrips() throws {
        let kind = BlockKind.ifBlock(
            condition: Condition(lhs: .literal(1), comparison: .less, rhs: .literal(2)),
            body: [], elseBody: [])
        let json = try Self.sortedKeysJSON(kind)
        #expect(
            json
                == #"{"if":{"body":[],"condition":{"comparison":"less","lhs":{"literal":1},"rhs":{"literal":2}},"elseBody":[]}}"#
        )
        let decoded = try JSONDecoder().decode(BlockKind.self, from: Data(json.utf8))
        #expect(decoded == kind)
    }

    @Test("requiredSchemaVersion is 3 exactly when a defined block appears")
    func requiredSchemaVersionForFunctions() {
        let define = [
            Block(kind: .defineBlock(name: "き", body: [Block(kind: .home)]))
        ]
        #expect(BlocksProject(title: "", blocks: define).requiredSchemaVersion == 3)
        // A call on its own counts too — it is just as unreadable to an app
        // that has never heard of the key.
        let callOnly = [Block(kind: .callBlock(name: "き"))]
        #expect(BlocksProject(title: "", blocks: callOnly).requiredSchemaVersion == 3)
        // And nested, where `contains` has to descend to find it.
        let nested = [
            Block(kind: .repeatBlock(count: .literal(2), body: callOnly))
        ]
        #expect(BlocksProject(title: "", blocks: nested).requiredSchemaVersion == 3)
        // Version 2 documents are untouched by any of this.
        #expect(BlocksProject(title: "", blocks: SampleBlocks.spiral()).requiredSchemaVersion == 2)
    }

    @Test("requiredSchemaVersion is 2 exactly when variables appear")
    func requiredSchemaVersion() {
        #expect(BlocksProject(title: "", blocks: SampleBlocks.star()).requiredSchemaVersion == 1)
        #expect(BlocksProject(title: "", blocks: SampleBlocks.spiral()).requiredSchemaVersion == 2)
        // A bare reference in a slot counts, not just the set/add blocks.
        let referenceOnly = [Block(kind: .forward(.variable("🌟")))]
        #expect(BlocksProject(title: "", blocks: referenceOnly).requiredSchemaVersion == 2)
        // An if block is a version-2 feature even without variables.
        let ifOnly = [
            Block(
                kind: .ifBlock(
                    condition: Condition(lhs: .literal(1), comparison: .less, rhs: .literal(2)),
                    body: [], elseBody: nil))
        ]
        #expect(BlocksProject(title: "", blocks: ifOnly).requiredSchemaVersion == 2)
    }

    @Test("a project that has never run writes no thumbnail key")
    func thumbnailIsAbsentWhenNil() throws {
        // The whole backward-compatibility claim in one string: a document
        // without a thumbnail is byte-identical to what an app that had never
        // heard of one wrote.
        let project = BlocksProject(schemaVersion: 1, title: "ほし", blocks: [])
        #expect(
            try Self.sortedKeysJSON(project) == #"{"blocks":[],"schemaVersion":1,"title":"ほし"}"#)
    }

    @Test("a thumbnail rides schema version 1 as base64")
    func thumbnailRoundTrips() throws {
        // A PNG signature stands in for the real image; what matters here is
        // that `Data` needs no encoding of its own.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let project = BlocksProject(
            schemaVersion: 1, title: "ほし", blocks: SampleBlocks.star(), thumbnail: png)
        #expect(try Self.sortedKeysJSON(project).contains(#""thumbnail":"iVBORw0KGgo=""#))
        let decoded = try JSONDecoder().decode(
            BlocksProject.self, from: try JSONEncoder().encode(project))
        #expect(decoded == project)
        #expect(decoded.thumbnail == png)
        // A picture of the drawing is not a feature of the *tree*, so it must
        // not push the file out of reach of a version-1 app.
        #expect(project.requiredSchemaVersion == 1)
    }

    @Test("a document written before thumbnails existed still decodes")
    func thumbnailAbsentDecodes() throws {
        let json =
            #"{"schemaVersion":1,"title":"ほし","blocks":[{"kind":{"home":{}},"id":"\#(Self.childID)"}]}"#
        let decoded = try JSONDecoder().decode(BlocksProject.self, from: Data(json.utf8))
        #expect(decoded.thumbnail == nil)
        #expect(decoded.blocks.count == 1)
    }

    /// What the QuickLook extension does — and the reason it can stay free of
    /// this package: reading the picture needs neither the block format nor
    /// the schema gate, so a newer document and an unknown block kind both
    /// still produce a thumbnail.
    @Test("a bare probe lifts the thumbnail out of any document")
    func thumbnailProbeIgnoresEverythingElse() throws {
        struct ThumbnailProbe: Decodable { let thumbnail: Data? }
        let json =
            #"{"blocks":[{"kind":{"teleport":{}},"id":"x"}],"schemaVersion":99,"thumbnail":"iVBORw0KGgo=","title":"t"}"#
        let probe = try JSONDecoder().decode(ThumbnailProbe.self, from: Data(json.utf8))
        #expect(probe.thumbnail == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
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
