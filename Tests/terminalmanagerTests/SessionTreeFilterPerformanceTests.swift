import XCTest
@testable import terminalmanager

final class SessionTreeFilterPerformanceTests: XCTestCase {
    func testFilter500SessionsUnder100ms() {
        let tree = Self.makeSyntheticTree(sessionCount: 500)
        var index = SessionTreeSearchIndex()
        index.rebuild(from: tree)

        let start = CFAbsoluteTimeGetCurrent()
        let filtered = SessionTreeFilter.filter(tree, query: "host-42", searchIndex: index)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertFalse(filtered.isEmpty)
        XCTAssertLessThan(elapsedMs, 100, "Filter took \(elapsedMs) ms")
    }

    private static func makeSyntheticTree(sessionCount: Int) -> [SessionTreeItem] {
        let folderCount = max(1, sessionCount / 25)
        var sessionsPerFolder = sessionCount / folderCount
        var remainder = sessionCount % folderCount
        var folders: [SessionTreeItem] = []

        for folderIndex in 0 ..< folderCount {
            let extra = remainder > 0 ? 1 : 0
            if remainder > 0 { remainder -= 1 }
            let count = sessionsPerFolder + extra
            var children: [SessionTreeItem] = []
            for sessionIndex in 0 ..< count {
                let id = folderIndex * 100 + sessionIndex
                let profile = SessionProfile(
                    name: "Session \(id)",
                    host: "host-\(id).example.com",
                    protocolType: .ssh,
                    notes: "note-\(id)"
                )
                children.append(.session(profile))
            }
            folders.append(.folder(SessionFolder(name: "Folder \(folderIndex)", children: children)))
        }
        return folders
    }
}
