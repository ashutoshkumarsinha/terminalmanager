import XCTest
@testable import terminalmanager

final class SessionRecorderTests: TempConfigTestCase {
    override func tearDown() {
        SessionRecorder.shared.configure(enabled: false)
        super.tearDown()
    }

    func testRecordingWhenEnabledPlainText() {
        SessionRecorder.shared.configure(enabled: true, format: .plain)
        let tabID = UUID()
        SessionRecorder.shared.start(tabID: tabID, sessionName: "Test")

        let url = SessionRecorder.shared.recordingURL(for: tabID)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.pathExtension, "txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))

        SessionRecorder.shared.append(tabID: tabID, direction: "OUTPUT", data: ArraySlice("hello".utf8))
        SessionRecorder.shared.stop(tabID: tabID)
    }

    func testRecordingAsciinemaCastFormat() {
        SessionRecorder.shared.configure(enabled: true, format: .asciinema)
        let tabID = UUID()
        SessionRecorder.shared.start(tabID: tabID, sessionName: "CastTest", cols: 100, rows: 30)
        SessionRecorder.shared.append(tabID: tabID, direction: "OUTPUT", data: ArraySlice("prompt$ ".utf8))
        SessionRecorder.shared.append(tabID: tabID, direction: "INPUT", data: ArraySlice("echo hi\r".utf8))
        SessionRecorder.shared.append(tabID: tabID, direction: "OUTPUT", data: ArraySlice("hi\n".utf8))

        let url = SessionRecorder.shared.recordingURL(for: tabID)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.pathExtension, "cast")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url!.path))

        SessionRecorder.shared.stop(tabID: tabID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))

        let text = try? String(contentsOf: url!, encoding: .utf8)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("\"version\":2"))
        XCTAssertTrue(text!.contains("prompt$ "))
        XCTAssertTrue(text!.contains("echo hi"))
    }

    func testRecordingDisabledDoesNotCreateFile() {
        SessionRecorder.shared.configure(enabled: false)
        let tabID = UUID()
        SessionRecorder.shared.start(tabID: tabID, sessionName: "Ignored")
        XCTAssertNil(SessionRecorder.shared.recordingURL(for: tabID))
    }
}
