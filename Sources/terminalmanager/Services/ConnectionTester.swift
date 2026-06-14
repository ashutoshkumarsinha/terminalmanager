import Foundation

enum ConnectionTester {
    enum TestResult: Equatable {
        case success
        case failure(String)
    }

    static func testConnection(
        for profile: SessionProfile,
        timeout: TimeInterval = 5
    ) async -> TestResult {
        switch profile.protocolType {
        case .ssh:
            return await testSSH(profile: profile, timeout: timeout)
        case .raw:
            return await testRawTCP(profile: profile, timeout: timeout)
        case .local:
            return .success
        case .telnet, .rlogin:
            return await testRawTCP(profile: profile, timeout: timeout)
        }
    }

    private static func testSSH(profile: SessionProfile, timeout: TimeInterval) async -> TestResult {
        let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return .failure("Host is empty")
        }

        var args = ["-G"]
        if let port = profile.port, port != 22 {
            args += ["-p", String(port)]
        }
        if let jump = profile.proxyJump?.trimmingCharacters(in: .whitespacesAndNewlines), !jump.isEmpty {
            args += ["-J", jump]
        }
        ConnectionLauncher.appendSSHExtraOptions(profile.sshExtraOptions, to: &args)
        args.append(host)

        return await runProcess(
            executable: "/usr/bin/ssh",
            arguments: args,
            timeout: timeout
        )
    }

    private static func testRawTCP(profile: SessionProfile, timeout: TimeInterval) async -> TestResult {
        let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return .failure("Host is empty")
        }
        let port = profile.port ?? profile.protocolType.defaultPort ?? 23

        return await runProcess(
            executable: "/usr/bin/nc",
            arguments: ["-z", "-G", String(Int(timeout)), host, String(port)],
            timeout: timeout + 1
        )
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> TestResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stderrPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                    return
                }

                let timeoutWork = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                process.waitUntilExit()
                timeoutWork.cancel()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success)
                } else {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: .failure(message?.isEmpty == false ? message! : "Connection test failed"))
                }
            }
        }
    }
}
