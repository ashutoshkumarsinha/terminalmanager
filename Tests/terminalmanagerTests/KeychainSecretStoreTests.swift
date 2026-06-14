import XCTest
@testable import terminalmanager

final class KeychainSecretStoreTests: XCTestCase {
    private var profileID: UUID!

    override func setUp() {
        super.setUp()
        profileID = UUID()
        try? KeychainSecretStore.delete(for: profileID)
    }

    override func tearDown() {
        try? KeychainSecretStore.delete(for: profileID)
        super.tearDown()
    }

    func testStoreLoadDeleteRoundTrip() throws {
        try KeychainSecretStore.store(password: "hunter2", for: profileID)
        XCTAssertEqual(KeychainSecretStore.load(for: profileID), "hunter2")

        try KeychainSecretStore.store(password: "updated", for: profileID)
        XCTAssertEqual(KeychainSecretStore.load(for: profileID), "updated")

        try KeychainSecretStore.delete(for: profileID)
        XCTAssertNil(KeychainSecretStore.load(for: profileID))
    }

    func testStoreEmptyPasswordDeletesEntry() throws {
        try KeychainSecretStore.store(password: "temp", for: profileID)
        try KeychainSecretStore.store(password: "", for: profileID)
        XCTAssertNil(KeychainSecretStore.load(for: profileID))
    }

    func testLoadMissingReturnsNil() {
        XCTAssertNil(KeychainSecretStore.load(for: profileID))
    }
}
