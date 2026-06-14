import XCTest
@testable import terminalmanager

final class SSHAuthHelperTests: TempConfigTestCase {
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

    func testResolvedPasswordPrefersInlineValue() {
        var profile = SessionProfile(
            id: profileID,
            name: "Inline",
            host: "host",
            protocolType: .ssh,
            sshAuthMethod: .password,
            password: "inline"
        )
        SSHAuthHelper.storePassword("keychain", for: profileID)
        XCTAssertEqual(SSHAuthHelper.resolvedPassword(for: profile), "inline")
    }

    func testResolvedPasswordFallsBackToKeychain() {
        SSHAuthHelper.storePassword("from-keychain", for: profileID)
        var profile = SessionProfile(
            id: profileID,
            name: "Keychain",
            host: "host",
            protocolType: .ssh,
            sshAuthMethod: .password,
            password: ""
        )
        XCTAssertEqual(SSHAuthHelper.resolvedPassword(for: profile), "from-keychain")
    }

    func testMigratePasswordToKeychainClearsProfileField() {
        var profile = SessionProfile(
            id: profileID,
            name: "Migrate",
            host: "host",
            protocolType: .ssh,
            sshAuthMethod: .password,
            password: "legacy-secret"
        )

        XCTAssertTrue(SSHAuthHelper.migratePasswordToKeychain(for: &profile))
        XCTAssertEqual(profile.password, "")
        XCTAssertEqual(KeychainSecretStore.load(for: profileID), "legacy-secret")
    }

    func testMigrateSkipsNonPasswordProfiles() {
        var profile = SessionProfile(
            id: profileID,
            name: "Agent",
            host: "host",
            protocolType: .ssh,
            sshAuthMethod: .agent
        )
        XCTAssertFalse(SSHAuthHelper.migratePasswordToKeychain(for: &profile))
    }
}
