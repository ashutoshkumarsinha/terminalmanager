import XCTest
@testable import terminalmanager

final class SessionExportRedactorTests: XCTestCase {
    func testRedactProfileClearsPassword() {
        var profile = SessionProfile(
            name: "Web",
            host: "web01",
            username: "admin",
            protocolType: .ssh,
            sshAuthMethod: .password,
            password: "secret123"
        )
        let redacted = SessionExportRedactor.redactProfile(profile)
        XCTAssertEqual(redacted.password, "")
        XCTAssertEqual(redacted.name, profile.name)
        XCTAssertEqual(redacted.host, profile.host)
    }

    func testRedactTreeClearsNestedSessionPasswords() {
        var profile = SessionProfile(
            name: "DB",
            host: "db01",
            username: "dba",
            protocolType: .ssh,
            sshAuthMethod: .password,
            password: "db-pass"
        )
        let folder = SessionFolder(
            name: "Production",
            children: [.session(profile)]
        )
        let tree: [SessionTreeItem] = [.folder(folder), .group(SessionGroup(name: "Stack"))]

        let redacted = SessionExportRedactor.redact(tree)
        XCTAssertEqual(redacted.count, 2)

        guard case .folder(let redactedFolder) = redacted[0],
              case .session(let redactedProfile) = redactedFolder.children[0] else {
            return XCTFail("Expected folder with session")
        }
        XCTAssertEqual(redactedProfile.password, "")

        guard case .group(let group) = redacted[1] else {
            return XCTFail("Expected group unchanged")
        }
        XCTAssertEqual(group.name, "Stack")
    }

    func testRedactProfileClearsNotesWhenKeychainBacked() {
        var profile = SessionProfile(
            name: "Web",
            host: "web01",
            protocolType: .ssh,
            notes: "",
            notesInKeychain: true
        )
        let redacted = SessionExportRedactor.redactProfile(profile)
        XCTAssertFalse(redacted.notesInKeychain)
        XCTAssertEqual(redacted.notes, "")
    }

    func testRedactProfileClearsInlineNotes() {
        var profile = SessionProfile(
            name: "Web",
            host: "web01",
            protocolType: .ssh,
            notes: "visible note"
        )
        let redacted = SessionExportRedactor.redactProfile(profile)
        XCTAssertEqual(redacted.notes, "")
    }
}
