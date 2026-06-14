import Foundation

enum SFTPTransferService {
    enum TransferError: Error, LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }

    static func upload(localURL: URL, to remotePath: String, profile: SessionProfile) async throws {
        let batch = "put \"\(localURL.path)\" \"\(remotePath)\"\nbye\n"
        try await runBatch(batch, profile: profile)
    }

    static func download(remotePath: String, to localURL: URL, profile: SessionProfile) async throws {
        let batch = "get \"\(remotePath)\" \"\(localURL.path)\"\nbye\n"
        try await runBatch(batch, profile: profile)
    }

    private static func runBatch(_ batch: String, profile: SessionProfile) async throws {
        guard let command = ConnectionLauncher.sftpCommand(for: profile) else {
            throw TransferError.failed("SFTP requires an SSH session.")
        }
        let tempBatch = FileManager.default.temporaryDirectory
            .appendingPathComponent("sftp-batch-\(UUID().uuidString).txt")
        try batch.write(to: tempBatch, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempBatch) }

        var args = command.arguments
        args.insert(contentsOf: ["-b", tempBatch.path], at: 0)

        let result: Int32 = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = args
            if let overrides = command.environment {
                var env = ProcessInfo.processInfo.environment
                for override in overrides {
                    let parts = override.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    env[String(parts[0])] = String(parts[1])
                }
                process.environment = env
            }
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            } catch {
                return -1
            }
        }.value

        guard result == 0 else {
            throw TransferError.failed("SFTP transfer failed (exit \(result)).")
        }
    }
}
