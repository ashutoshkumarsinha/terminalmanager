import Foundation

enum SSHAuthHelper {
    static func askpassScriptURL(for profileID: UUID) -> URL {
        FileLocations.configDirectory.appendingPathComponent("askpass-\(profileID.uuidString).sh")
    }

    /// Returns the password from the profile or Keychain.
    static func resolvedPassword(for profile: SessionProfile) -> String? {
        if !profile.password.isEmpty {
            return profile.password
        }
        return KeychainSecretStore.load(for: profile.id)
    }

    /// Stores password in Keychain and clears any legacy askpass script.
    static func storePassword(_ password: String, for profileID: UUID) {
        do {
            try KeychainSecretStore.store(password: password, for: profileID)
            removeLegacyAskpassScript(for: profileID)
        } catch {
            AppLogger.shared.error("Failed to store password in Keychain: \(error)")
        }
    }

    /// Migrates a plain-text password from sessions JSON into Keychain.
    @discardableResult
    static func migratePasswordToKeychain(for profile: inout SessionProfile) -> Bool {
        guard profile.sshAuthMethod == .password, !profile.password.isEmpty else {
            return false
        }
        storePassword(profile.password, for: profile.id)
        profile.password = ""
        return true
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

    private static func removeLegacyAskpassScript(for profileID: UUID) {
        let url = askpassScriptURL(for: profileID)
        try? FileManager.default.removeItem(at: url)
    }
}
