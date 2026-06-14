import XCTest
@testable import terminalmanager

final class AsciinemaCastWriterTests: XCTestCase {
    func testWriteCastV2Format() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).cast")
        defer { try? FileManager.default.removeItem(at: url) }

        let events = [
            AsciinemaCastEvent(offset: 0.0, stream: "o", data: "Hello"),
            AsciinemaCastEvent(offset: 0.5, stream: "i", data: "ls\r"),
            AsciinemaCastEvent(offset: 1.0, stream: "o", data: "file.txt\n")
        ]

        try AsciinemaCastWriter.write(
            to: url,
            width: 120,
            height: 40,
            timestamp: 1_700_000_000,
            title: "Demo",
            events: events
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertGreaterThanOrEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("\"version\":2"))
        XCTAssertTrue(lines[0].contains("\"width\":120"))
        XCTAssertTrue(lines[1].contains("\"Hello\""))
        XCTAssertTrue(lines[2].contains("\"i\""))
    }

    func testEncodeDataFromUTF8Bytes() {
        let encoded = AsciinemaCastWriter.encodeData(ArraySlice("café".utf8))
        XCTAssertEqual(encoded, "café")
    }
}
