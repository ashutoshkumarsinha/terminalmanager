import XCTest
@testable import terminalmanager

final class EncryptedBackupTests: TempConfigTestCase {
    func testExportImportRoundTrip() throws {
        var settings = AppSettings.defaults
        settings.terminalFontName = "Courier"
        settings.terminalFontSize = 14
        settings.restoreTabsOnLaunch = true
        settings.syncSessionsPath = "/tmp/sync/sessions.json"

        let profile = makeSession(name: "App", host: "app01.example.com")
        let tree: [SessionTreeItem] = [.session(profile)]
        let backupURL = tempConfigDirectory.appendingPathComponent("backup.tmbk")

        try EncryptedBackup.exportEncrypted(
            settings: settings,
            sessionTree: tree,
            passphrase: "test-passphrase",
            to: backupURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        let imported = try EncryptedBackup.importEncrypted(from: backupURL, passphrase: "test-passphrase")
        XCTAssertEqual(imported.settings.terminalFontName, "Courier")
        XCTAssertEqual(imported.settings.terminalFontSize, 14)
        XCTAssertTrue(imported.settings.restoreTabsOnLaunch)
        XCTAssertEqual(imported.settings.syncSessionsPath, "/tmp/sync/sessions.json")
        XCTAssertEqual(imported.sessionTree.count, 1)
        if case .session(let restored) = imported.sessionTree[0] {
            XCTAssertEqual(restored.host, "app01.example.com")
        } else {
            XCTFail("Expected session in imported tree")
        }
    }

    func testWrongPassphraseFails() throws {
        let backupURL = tempConfigDirectory.appendingPathComponent("bad-pass.tmbk")
        try EncryptedBackup.exportEncrypted(
            settings: .defaults,
            sessionTree: [],
            passphrase: "correct",
            to: backupURL
        )

        XCTAssertThrowsError(try EncryptedBackup.importEncrypted(from: backupURL, passphrase: "wrong")) { error in
            guard case EncryptedBackup.BackupError.decryptionFailed = error else {
                return XCTFail("Expected decryptionFailed")
            }
        }
    }

    func testEmptyPassphraseRejected() {
        let backupURL = tempConfigDirectory.appendingPathComponent("empty-pass.tmbk")
        XCTAssertThrowsError(
            try EncryptedBackup.exportEncrypted(
                settings: .defaults,
                sessionTree: [],
                passphrase: "",
                to: backupURL
            )
        ) { error in
            guard case EncryptedBackup.BackupError.invalidPassphrase = error else {
                return XCTFail("Expected invalidPassphrase")
            }
        }
    }

    func testInvalidFileFormatRejected() throws {
        let badURL = tempConfigDirectory.appendingPathComponent("not-a-backup.bin")
        try Data("not backup".utf8).write(to: badURL)
        XCTAssertThrowsError(try EncryptedBackup.importEncrypted(from: badURL, passphrase: "x")) { error in
            guard case EncryptedBackup.BackupError.invalidFormat = error else {
                return XCTFail("Expected invalidFormat")
            }
        }
    }
}
