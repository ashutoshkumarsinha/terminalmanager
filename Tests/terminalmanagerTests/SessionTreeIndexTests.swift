import XCTest
@testable import terminalmanager

final class SessionTreeIndexTests: XCTestCase {
    func testIndexesNestedItemsAndParentFolders() {
        let web = SessionProfile(name: "Web", host: "web01", username: "admin", protocolType: .ssh)
        let folder = SessionFolder(
            name: "Production",
            children: [.session(web), .group(SessionGroup(name: "Stack"))]
        )
        let tree: [SessionTreeItem] = [.folder(folder)]

        var index = SessionTreeIndex()
        index.rebuild(from: tree)

        XCTAssertNotNil(index.item(withID: folder.id))
        XCTAssertNotNil(index.item(withID: web.id))
        XCTAssertEqual(index.parentFolderID(of: web.id), folder.id)
        XCTAssertNil(index.parentFolderID(of: folder.id))
        XCTAssertEqual(index.sessionProfile(withID: web.id)?.host, "web01")
    }
}

final class PersistenceCoordinatorTests: TempConfigTestCase {
    func testFlushLaunchStateWritesFile() {
        let state = LaunchState(tabProfileIDs: [UUID()], selectedTabProfileID: nil, splitLayouts: [:])
        PersistenceCoordinator.flushLaunchState(with: state)
        XCTAssertNotNil(LaunchStateStore.load())
    }

    func testClearLaunchStateRemovesFile() throws {
        let state = LaunchState(tabProfileIDs: [UUID()])
        PersistenceCoordinator.flushLaunchState(with: state)
        PersistenceCoordinator.clearLaunchState()
        XCTAssertNil(LaunchStateStore.load())
    }

    func testSessionsSaveOffMainWritesJSON() {
        let profile = makeSession(name: "Save", host: "host01")
        let tree: [SessionTreeItem] = [.session(profile)]
        let url = tempConfigDirectory.appendingPathComponent("sessions-off-main.json")

        PersistenceCoordinator.flushSessionsSave(tree: tree, to: url, offMain: true)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
