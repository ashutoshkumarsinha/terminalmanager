import XCTest
@testable import terminalmanager

final class TerminalIOLogExporterTests: XCTestCase {
    func testRedactSecrets() {
        let input = "password=secret123 token=abc123"
        let redacted = TerminalIOLogExporter.redact(input)
        XCTAssertTrue(redacted.contains("[REDACTED]"))
        XCTAssertFalse(redacted.contains("secret123"))
    }

    func testCollectLinesFiltersByTabID() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("io-export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tabID = UUID()
        let otherTab = UUID()
        let logURL = tempDir.appendingPathComponent("terminal-io-2026-06-10.log")
        let content = """
        [2026-06-10 12:00:00.000] [OUTPUT] [tab=\(tabID.uuidString)] [web] hello
        [2026-06-10 12:00:01.000] [OUTPUT] [tab=\(otherTab.uuidString)] [db] ignored
        """
        try content.write(to: logURL, atomically: true, encoding: .utf8)

        let lines = try TerminalIOLogExporter.collectLines(tabID: tabID, logsDirectory: tempDir)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("hello"))
        XCTAssertFalse(lines[0].contains("ignored"))
    }
}
