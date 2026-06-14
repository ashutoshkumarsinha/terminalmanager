import XCTest
@testable import terminalmanager

@MainActor
final class ConfigStoreTests: TempConfigTestCase {
    func testCreateEmptyGroup() {
        let store = ConfigStore()
        let group = store.createEmptyGroup(name: "Fleet")
        XCTAssertEqual(group.name, "Fleet")
        XCTAssertTrue(group.members.isEmpty)
        XCTAssertNil(group.layout)

        guard case .group(let saved) = store.sessionTree.first else {
            return XCTFail("Expected group in tree")
        }
        XCTAssertEqual(saved.id, group.id)
    }

    func testDuplicateSessionToFolder() {
        let store = ConfigStore()
        let folder = store.addFolder("Ops")
        let profile = store.addSession(makeSession(name: "Web", host: "web01"), to: folder.id)

        guard let copy = store.duplicateSessionToFolder(sessionID: profile.id, folderID: folder.id) else {
            return XCTFail("Expected duplicate")
        }
        XCTAssertNotEqual(copy.id, profile.id)
        XCTAssertEqual(copy.host, profile.host)

        guard case .folder(let savedFolder) = store.item(withID: folder.id) else {
            return XCTFail("Expected folder")
        }
        let sessionIDs = savedFolder.children.compactMap { item -> UUID? in
            if case .session(let session) = item { return session.id }
            return nil
        }
        XCTAssertTrue(sessionIDs.contains(profile.id))
        XCTAssertTrue(sessionIDs.contains(copy.id))
    }

    func testExportSessionsRedactsPasswords() throws {
        let store = ConfigStore()
        var profile = makeSession(name: "Secret", host: "host01")
        profile.sshAuthMethod = .password
        profile.password = "plain-text"
        _ = store.addSession(profile)

        let exportURL = tempConfigDirectory.appendingPathComponent("export.json")
        try store.exportSessions(to: exportURL, redactSecrets: true)

        let data = try Data(contentsOf: exportURL)
        let config = try JSONDecoder().decode(SessionConfiguration.self, from: data)
        guard case .session(let exported) = config.sessionTree[0] else {
            return XCTFail("Expected session")
        }
        XCTAssertEqual(exported.password, "")
    }

    func testUpdateGroupLayoutFromTabs() {
        let store = ConfigStore()
        let profileA = store.addSession(makeSession(name: "A", host: "a01"))
        let profileB = store.addSession(makeSession(name: "B", host: "b01"))
        let group = store.createEmptyGroup(name: "Pair")

        let tabA = TerminalTab(id: UUID(), title: "A", profile: profileA)
        let tabB = TerminalTab(id: UUID(), title: "B", profile: profileB)
        let split = SplitLayoutNode.split(.horizontal, .leaf(tabID: tabA.id), .leaf(tabID: tabB.id))

        XCTAssertTrue(
            store.updateGroupLayout(
                groupID: group.id,
                from: [tabA, tabB],
                splitLayouts: [tabA.id: split],
                selectedTabID: tabA.id
            )
        )

        guard let updated = store.group(withID: group.id) else {
            return XCTFail("Expected updated group")
        }
        XCTAssertEqual(updated.members.count, 2)
        XCTAssertNotNil(updated.layout)
        XCTAssertEqual(updated.layout?.children.count, 2)
    }

    func testDuplicateSessionCopiesPasswordToKeychain() {
        let store = ConfigStore()
        var profile = makeSession(name: "Secret", host: "host01")
        profile.sshAuthMethod = .password
        profile.password = "copy-me"
        let saved = store.addSession(profile)

        guard let duplicate = store.duplicateSession(id: saved.id) else {
            return XCTFail("Expected duplicate session")
        }
        XCTAssertNotEqual(duplicate.id, saved.id)
        XCTAssertEqual(SSHAuthHelper.resolvedPassword(for: duplicate), "copy-me")
        XCTAssertEqual(duplicate.password, "")
    }

    func testExportSessionsRedactsKeychainNotes() throws {
        let store = ConfigStore()
        var profile = makeSession(name: "Notes", host: "host01")
        profile.notes = "secret runbook"
        profile.notesInKeychain = true
        _ = store.addSession(profile)

        let exportURL = tempConfigDirectory.appendingPathComponent("export-notes.json")
        try store.exportSessions(to: exportURL, redactSecrets: true)

        let data = try Data(contentsOf: exportURL)
        let config = try JSONDecoder().decode(SessionConfiguration.self, from: data)
        guard case .session(let exported) = config.sessionTree[0] else {
            return XCTFail("Expected session")
        }
        XCTAssertEqual(exported.notes, "")
        XCTAssertFalse(exported.notesInKeychain)

        try SessionNotesHelper.deleteNotes(for: profile.id)
    }
}
