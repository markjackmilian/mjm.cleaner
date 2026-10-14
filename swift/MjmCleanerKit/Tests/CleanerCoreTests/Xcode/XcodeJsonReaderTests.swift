import Testing
@testable import CleanerCore

/// Test solo Swift: il lettore JSON che sostituisce `JsonDocument`. I casi non validi sono quelli
/// che .NET 10 rifiuta (misurati), più il surrogato isolato che Swift rifiuta per costruzione.
struct XcodeJsonReaderTests {
    @Test func objectsKeepMemberOrderAndTheLastDuplicateWins() throws {
        let value = try XcodeJsonReader.parse(#"{"b":1,"a":"x","b":2}"#)

        guard case .object(let members) = value else {
            Issue.record("atteso un oggetto")
            return
        }
        #expect(members.map(\.name) == ["b", "a", "b"])
        #expect(value.optionalInt64("b").value == 2)
        #expect(value.string("a") == "x")
        #expect(value.string("b") == nil)
    }

    @Test(arguments: [
        "", " ", "{", "{}x", "\u{FEFF}{}", "{'a':1}", #"{"a":01}"#, #"{"a":1,}"#, "/*c*/{}",
        #"{"a":"\ud800"}"#, #"{"a":"\udc00x"}"#, "[\"\u{01}\"]", "[1.]", "[-]", "[1e]", "tru", "[\"\\x\"]",
    ])
    func invalidDocumentsAreRejectedLikeJsonDocument(text: String) {
        #expect(throws: XcodeJsonSyntaxError.self) { try XcodeJsonReader.parse(text) }
    }

    @Test func validDocumentsDecodeEscapesAndNumbers() throws {
        let value = try XcodeJsonReader.parse(#" {"s":"a\"\\\/\b\f\n\r\t\u00e9\ud83d\ude00","n":-0,"f":1.5e3,"t":true,"z":null,"l":[]} "#)

        #expect(value.string("s") == "a\"\\/\u{08}\u{0C}\n\r\t\u{E9}\u{1F600}")
        #expect(value.optionalInt64("n").value == 0)
        #expect(value.optionalInt64("f").malformed)
        #expect(value.bool("t") == true)
        guard case .null? = value.property("z"), case .array(let list)? = value.property("l") else {
            Issue.record("null e array attesi")
            return
        }
        #expect(list.isEmpty)
    }

    @Test func optionalInt64FollowsTryGetInt64() throws {
        let value = try XcodeJsonReader.parse(
            #"{"a":100,"b":100.0,"c":1e2,"d":9223372036854775807,"e":9223372036854775808,"f":"100","g":[]}"#)

        #expect(value.optionalInt64("a").value == 100)
        #expect(value.optionalInt64("b").malformed)
        #expect(value.optionalInt64("c").malformed)
        #expect(value.optionalInt64("d").value == Int64.max)
        #expect(value.optionalInt64("e").malformed)
        #expect(value.optionalInt64("f").malformed)
        #expect(value.optionalInt64("g").malformed)
        #expect(value.optionalInt64("assente").value == nil)
        #expect(!value.optionalInt64("assente").malformed)
    }

    @Test func nestingDeeperThanSixtyFourLevelsIsRejected() throws {
        let deepest = String(repeating: "[", count: 64) + String(repeating: "]", count: 64)
        let tooDeep = String(repeating: "[", count: 65) + String(repeating: "]", count: 65)

        _ = try XcodeJsonReader.parse(deepest)
        #expect(throws: XcodeJsonSyntaxError.self) { try XcodeJsonReader.parse(tooDeep) }
    }
}
