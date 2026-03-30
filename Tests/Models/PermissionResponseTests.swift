@testable import Checkpoint
import Foundation
import Testing

@Suite("PermissionResponse")
struct PermissionResponseTests {
    @Test("Encode allow decision", arguments: [
        PermissionResponse.Decision.allow,
        PermissionResponse.Decision.deny,
        PermissionResponse.Decision.ask
    ])
    func encodeDecision(decision: PermissionResponse.Decision) throws {
        let response = PermissionResponse(decision: decision)
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast

        let output = json["hookSpecificOutput"] as? [String: Any]
        #expect(output?["hookEventName"] as? String == "PreToolUse")
        #expect(output?["permissionDecision"] as? String == decision.rawValue)
        #expect(output?["permissionDecisionReason"] is String)
    }

    @Test("Decode roundtrip")
    func decodeRoundtrip() throws {
        let original = PermissionResponse(decision: .allow)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PermissionResponse.self, from: data)

        #expect(decoded.hookSpecificOutput.hookEventName == "PreToolUse")
        #expect(decoded.hookSpecificOutput.permissionDecision == "allow")
        #expect(decoded.hookSpecificOutput.permissionDecisionReason == "User approved")
    }

    @Test("Custom reason")
    func customReason() throws {
        let response = PermissionResponse(decision: .allow, reason: "Matched session allow rule")
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast
        let output = json["hookSpecificOutput"] as! [String: Any] // swiftlint:disable:this force_cast
        #expect(output["permissionDecisionReason"] as? String == "Matched session allow rule")
    }

    @Test("JSON structure matches Claude hook format — no optional fields when nil")
    func jsonStructure() throws {
        let response = PermissionResponse(decision: .deny)
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast

        #expect(json.keys.count == 1)
        #expect(json.keys.first == "hookSpecificOutput")

        let output = json["hookSpecificOutput"] as! [String: Any] // swiftlint:disable:this force_cast
        #expect(output.keys.count == 3)
        #expect(output["hookEventName"] as? String == "PreToolUse")
        #expect(output["permissionDecision"] as? String == "deny")
        #expect(output["permissionDecisionReason"] as? String == "User denied")
        // updatedInput and updatedPermissions should be absent when nil
        #expect(output["updatedInput"] == nil)
        #expect(output["updatedPermissions"] == nil)
    }

    // MARK: - updatedInput

    @Test("updatedInput is included when provided")
    func updatedInputIncluded() throws {
        let modified: [String: JSONValue] = ["command": .string("npm test --safe")]
        let response = PermissionResponse(decision: .allow, updatedInput: modified)
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast
        let output = json["hookSpecificOutput"] as! [String: Any] // swiftlint:disable:this force_cast

        let input = output["updatedInput"] as? [String: String]
        #expect(input?["command"] == "npm test --safe")
    }

    @Test("updatedInput roundtrips through encode/decode")
    func updatedInputRoundtrip() throws {
        let modified: [String: JSONValue] = ["file_path": .string("/safe/path.txt")]
        let original = PermissionResponse(decision: .allow, updatedInput: modified)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PermissionResponse.self, from: data)

        #expect(decoded.hookSpecificOutput.updatedInput?["file_path"]?.stringValue == "/safe/path.txt")
    }

    // MARK: - updatedPermissions

    @Test("updatedPermissions is included when provided")
    func updatedPermissionsIncluded() throws {
        let perms = PermissionResponse.UpdatedPermissions(allow: ["Bash(npm *)"], deny: nil)
        let response = PermissionResponse(decision: .allow, updatedPermissions: perms)
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast
        let output = json["hookSpecificOutput"] as! [String: Any] // swiftlint:disable:this force_cast

        let permissions = output["updatedPermissions"] as? [String: Any]
        let allow = permissions?["allow"] as? [String]
        #expect(allow == ["Bash(npm *)"])
    }

    @Test("updatedPermissions roundtrips through encode/decode")
    func updatedPermissionsRoundtrip() throws {
        let perms = PermissionResponse.UpdatedPermissions(
            allow: ["Edit(**/*.tsx)"],
            deny: ["Bash(rm *)"]
        )
        let original = PermissionResponse(decision: .allow, updatedPermissions: perms)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PermissionResponse.self, from: data)

        #expect(decoded.hookSpecificOutput.updatedPermissions?.allow == ["Edit(**/*.tsx)"])
        #expect(decoded.hookSpecificOutput.updatedPermissions?.deny == ["Bash(rm *)"])
    }
}
