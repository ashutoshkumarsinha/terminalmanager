import XCTest
@testable import terminalmanager

final class SessionTreeSearchIndexTests: XCTestCase {
    func testIndexMatchesNotesField() {
        var index = SessionTreeSearchIndex()
        let profile = SessionProfile(
            name: "Prod",
            host: "10.0.0.1",
            protocolType: .ssh,
            notes: "Primary database bastion"
        )
        index.rebuild(from: [.session(profile)])

        XCTAssertTrue(index.profileMatches(profile, needle: "bastion"))
        XCTAssertFalse(index.profileMatches(profile, needle: "staging"))
    }
}

final class SessionSidebarFlatRowBuilderTests: XCTestCase {
    func testBuildsFlatRowsForExpandedFolder() {
        let session = SessionProfile(name: "Web", host: "web01", protocolType: .ssh)
        let folder = SessionFolder(name: "Servers", children: [.session(session)])
        let rows = SessionSidebarFlatRowBuilder.build(
            from: [.folder(folder)],
            expandedFolderIDs: [folder.id],
            expandedGroupIDs: []
        )
        XCTAssertEqual(rows.count, 2)
        if case .session(let profile, let depth, _) = rows[1] {
            XCTAssertEqual(profile.name, "Web")
            XCTAssertEqual(depth, 1)
        } else {
            XCTFail("Expected session row")
        }
    }
}
