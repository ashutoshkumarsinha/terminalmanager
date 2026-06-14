import XCTest
@testable import terminalmanager

@MainActor
final class SessionLibraryStateTests: XCTestCase {
    func testSelectionAndPendingAction() {
        let library = SessionLibraryState()
        let folderID = UUID()

        library.selectionID = folderID
        XCTAssertEqual(library.selectionID, folderID)

        library.requestAction(.createFolder)
        XCTAssertEqual(library.pendingAction, .createFolder)
        library.consumeAction()
        XCTAssertNil(library.pendingAction)
    }

    func testFolderIDForNewSessionFromFolderSelection() {
        let configStore = ConfigStore()
        let folder = configStore.addFolder("Ops")
        let library = SessionLibraryState()
        library.selectionID = folder.id

        XCTAssertEqual(library.folderIDForNewSession(using: configStore), folder.id)
        XCTAssertEqual(library.selectedFolder(using: configStore)?.id, folder.id)
    }

    func testSearchDebounceUpdatesDebouncedText() async {
        let library = SessionLibraryState()
        library.scheduleSearchDebounce(to: "web", debounceMs: 0)
        XCTAssertEqual(library.debouncedSearchText, "web")
        XCTAssertTrue(library.isSearching)
    }

    func testExpandFolderPath() {
        let configStore = ConfigStore()
        let parent = configStore.addFolder("Parent")
        let nested = configStore.addFolder("Nested")
        _ = configStore.moveItem(withID: nested.id, toParentFolderID: parent.id, beforeItemID: nil)

        let library = SessionLibraryState()
        library.expandFolderPath(to: nested.id, using: configStore)
        XCTAssertTrue(library.expandedFolderIDs.contains(nested.id))
        XCTAssertTrue(library.expandedFolderIDs.contains(parent.id))
    }
}
