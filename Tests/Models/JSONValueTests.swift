@testable import Checkpoint
import Foundation
import Testing

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Decode string")
    func decodeString() throws {
        let json = Data("\"hello\"".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value == .string("hello"))
        #expect(value.stringValue == "hello")
    }

    @Test("Decode number")
    func decodeNumber() throws {
        let json = Data("42.5".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value == .number(42.5))
        #expect(value.stringValue == nil)
    }

    @Test("Decode integer number")
    func decodeIntegerNumber() throws {
        let json = Data("42".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value == .number(42))
        #expect(value.description == "42")
    }

    @Test("Decode bool")
    func decodeBool() throws {
        let json = Data("true".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value == .bool(true))
    }

    @Test("Decode null")
    func decodeNull() throws {
        let json = Data("null".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value == .null)
    }

    @Test("Decode object")
    func decodeObject() throws {
        let json = Data("{\"key\":\"value\",\"num\":1}".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .object(let dict) = value {
            #expect(dict["key"] == .string("value"))
            #expect(dict["num"] == .number(1))
        } else {
            Issue.record("Expected object")
        }
    }

    @Test("Decode array")
    func decodeArray() throws {
        let json = Data("[1,\"two\",true]".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .array(let arr) = value {
            #expect(arr.count == 3)
            #expect(arr[0] == .number(1))
            #expect(arr[1] == .string("two"))
            #expect(arr[2] == .bool(true))
        } else {
            Issue.record("Expected array")
        }
    }

    @Test("Encode roundtrip")
    func encodeRoundtrip() throws {
        let original: JSONValue = .object([
            "name": .string("test"),
            "count": .number(5),
            "active": .bool(true),
            "tags": .array([.string("a"), .string("b")]),
            "meta": .null
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("Description formatting")
    func descriptionFormatting() {
        #expect(JSONValue.string("hello").description == "hello")
        #expect(JSONValue.number(42).description == "42")
        #expect(JSONValue.number(3.14).description == "3.14")
        #expect(JSONValue.bool(true).description == "true")
        #expect(JSONValue.null.description == "null")
    }
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)): return a == b
        default: return false
        }
    }
}
