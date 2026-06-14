import XCTest
@testable import terminalmanager

final class SessionNotesHelperTests: XCTestCase {
    private var profileID: UUID!
    private var account: String!

    override func setUp() {
        super.setUp()
        profileID = UUID()
        account = "notes-\(profileID.uuidString)"
        try? KeychainSecretStore.delete(account: account)
    }

    override func tearDown() {
        try? KeychainSecretStore.delete(account: account)
        super.tearDown()
    }

    func testStoreLoadDeleteRoundTrip() throws {
        try SessionNotesHelper.storeNotes("deploy steps", for: profileID)
        var profile = SessionProfile(name: "Web", host: "web01", protocolType: .ssh, notesInKeychain: true)
        profile.id = profileID
        XCTAssertEqual(SessionNotesHelper.resolvedNotes(for: profile), "deploy steps")

        try SessionNotesHelper.deleteNotes(for: profileID)
        XCTAssertEqual(SessionNotesHelper.resolvedNotes(for: profile), "")
    }

    func testResolvedNotesUsesPlainTextWhenNotInKeychain() {
        let profile = SessionProfile(
            name: "Web",
            host: "web01",
            protocolType: .ssh,
            notes: "inline notes",
            notesInKeychain: false
        )
        XCTAssertEqual(SessionNotesHelper.resolvedNotes(for: profile), "inline notes")
    }

    func testMigrateNotesToKeychain() throws {
        var profile = SessionProfile(
            name: "Web",
            host: "web01",
            protocolType: .ssh,
            notes: "secret runbook",
            notesInKeychain: false
        )
        profile.id = profileID

        XCTAssertTrue(SessionNotesHelper.migrateNotesToKeychain(for: &profile))
        XCTAssertTrue(profile.notesInKeychain)
        XCTAssertEqual(profile.notes, "")
        XCTAssertEqual(SessionNotesHelper.resolvedNotes(for: profile), "secret runbook")

        try SessionNotesHelper.deleteNotes(for: profileID)
    }

    func testMigrateSkipsWhenAlreadyInKeychain() {
        var profile = SessionProfile(
            name: "Web",
            host: "web01",
            protocolType: .ssh,
            notes: "",
            notesInKeychain: true
        )
        XCTAssertFalse(SessionNotesHelper.migrateNotesToKeychain(for: &profile))
    }
}
