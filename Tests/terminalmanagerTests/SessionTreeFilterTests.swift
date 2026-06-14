import XCTest
@testable import terminalmanager

final class SessionTreeFilterTests: XCTestCase {
    private let web = SessionProfile(name: "Web Server", host: "web01.example.com", username: "admin", protocolType: .ssh)
    private let db = SessionProfile(name: "Database", host: "db01.example.com", username: "dba", protocolType: .ssh)
    private lazy var tree: [SessionTreeItem] = [
        .session(web),
        .session(db),
        .group(SessionGroup(name: "Production Stack"))
    ]

    func testFiltersByHost() {
        let filtered = SessionTreeFilter.filter(tree, query: "web01")
        XCTAssertEqual(filtered.count, 1)
        if case .session(let profile) = filtered[0] {
            XCTAssertEqual(profile.host, "web01.example.com")
        } else {
            XCTFail("Expected session")
        }
    }

    func testFiltersByNameProtocolAndUsername() {
        XCTAssertEqual(SessionTreeFilter.filter(tree, query: "database").count, 1)
        XCTAssertEqual(SessionTreeFilter.filter(tree, query: "ssh").count, 2)
        XCTAssertEqual(SessionTreeFilter.filter(tree, query: "dba").count, 1)
    }

    func testFiltersGroupsByName() {
        let filtered = SessionTreeFilter.filter(tree, query: "production")
        XCTAssertEqual(filtered.count, 1)
        guard case .group(let group) = filtered[0] else {
            return XCTFail("Expected group")
        }
        XCTAssertEqual(group.name, "Production Stack")
    }

    func testEmptyQueryReturnsOriginalTree() {
        XCTAssertEqual(SessionTreeFilter.filter(tree, query: ""), tree)
        XCTAssertEqual(SessionTreeFilter.filter(tree, query: "   "), tree)
    }

    func testFolderRetainedWhenChildMatches() {
        let folder = SessionFolder(
            name: "Cloud",
            children: [.session(web), .session(db)]
        )
        let filtered = SessionTreeFilter.filter([.folder(folder)], query: "web01")
        XCTAssertEqual(filtered.count, 1)
        guard case .folder(let kept) = filtered[0] else {
            return XCTFail("Expected folder")
        }
        XCTAssertEqual(kept.name, "Cloud")
        XCTAssertEqual(kept.children.count, 1)
    }

    func testMatchesHelperIsCaseInsensitive() {
        XCTAssertTrue(SessionTreeFilter.matches(web, needle: "web server"))
        XCTAssertTrue(SessionTreeFilter.matches(web, needle: "ssh"))
        XCTAssertFalse(SessionTreeFilter.matches(web, needle: "postgres"))
    }
}
