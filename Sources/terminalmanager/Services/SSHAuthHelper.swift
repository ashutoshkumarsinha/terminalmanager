import Foundation

enum SSHAuthHelper {
    static func askpassScriptURL(for profileID: UUID) -> URL {
        FileLocations.configDirectory.appendingPathComponent("askpass-\(profileID.uuidString).sh")
    }

    @discardableResult
    static func writeAskpassScript(password: String, profileID: UUID) -> URL? {
        guard !password.isEmpty else { return nil }

        let url = askpassScriptURL(for: profileID)
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nprintf '%s' '\(escaped)'\n"

        do {
            try FileManager.default.createDirectory(
                at: FileLocations.configDirectory,
                withIntermediateDirectories: true
            )
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            AppLogger.shared.error("Failed to write SSH askpass script: \(error)")
            return nil
        }
    }

    static func askpassEnvironment(password: String, profileID: UUID) -> [String]? {
        guard let scriptURL = writeAskpassScript(password: password, profileID: profileID) else {
            return nil
        }
        return [
            "SSH_ASKPASS=\(scriptURL.path)",
            "SSH_ASKPASS_REQUIRE=force",
            "DISPLAY=:0"
        ]
    }

    static func expandedKeyPath(_ path: String?) -> String? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (path as NSString).expandingTildeInPath
    }
}
