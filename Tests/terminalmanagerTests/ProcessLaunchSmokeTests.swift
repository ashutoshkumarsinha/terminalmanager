import XCTest

final class ProcessLaunchSmokeTests: XCTestCase {
    func testSmokeTestCLIExitsZero() throws {
        let binary = try locateSmokeTestBinary()
        let configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-smoke-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: configDir) }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["-smoke-test"]
        var env = ProcessInfo.processInfo.environment
        env["TERMINALMANAGER_CONFIG"] = configDir.path
        process.environment = env

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            XCTFail("smoke-test exited \(process.terminationStatus): \(errText)")
        }
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func locateSmokeTestBinary() throws -> URL {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/debug/terminalmanager"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/arm64-apple-macosx/debug/terminalmanager")
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }
        throw NSError(
            domain: "ProcessLaunchSmokeTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Build the app first: swift build"]
        )
    }
}
