import XCTest
@testable import terminalmanager

final class TerminalIOLoggerTests: XCTestCase {
    func testMetadataEntryFormat() {
        let tabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = Date(timeIntervalSince1970: 0)

        let entry = TerminalIOLogger.metadataEntry(
            direction: "OUTPUT",
            tabID: tabID,
            session: "prod",
            byteCount: 4096,
            timestamp: timestamp,
            timestampFormatter: formatter
        )

        XCTAssertTrue(entry.contains("[OUTPUT]"))
        XCTAssertTrue(entry.contains("[prod]"))
        XCTAssertTrue(entry.contains("4096 bytes"))
        XCTAssertFalse(entry.contains("password"))
    }
}
