import Foundation

/// Headless integration checks for CI and `swift test` (EN-09).
enum SmokeTestRunner {
    enum SmokeFailure: Error, CustomStringConvertible {
        case message(String)

        var description: String {
            switch self {
            case .message(let text): text
            }
        }
    }

    @MainActor
    static func runAll() throws {
        try testConfigMigrationAndCodec()
        try testSessionNotesKeychain()
        try testConnectionLauncherPhase4()
        try testTerminalIOLogExport()
        try testSessionRecorder()
        try testAppStateTabLifecycle()
        try testTabWorkspaceHealth()
        try testSessionLibraryState()
        try testSessionExportRedaction()
        try testANSIPaletteParsing()
    }

    @MainActor
    static func run() -> Int32 {
        do {
            try runAll()
            return 0
        } catch {
            fputs("Smoke test failed: \(error)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func testConfigMigrationAndCodec() throws {
        var settings = AppSettings.defaults
        settings.configSchemaVersion = 1
        ConfigMigration.migrate(&settings)
        guard settings.configSchemaVersion == ConfigMigration.currentSchemaVersion else {
            throw SmokeFailure.message("Config migration did not bump schema version")
        }

        let toml = """
        [app]
        version = 1

        [ui]
        show_sidebar = true
        broadcast_enabled = true

        [sessions]
        file = "sessions.json"

        [performance]
        copy_on_select = true
        paste_on_middle_click = false
        stale_tab_minutes = 10
        session_recording_enabled = true
        session_recording_format = "asciinema"
        check_for_updates = false
        update_repository = "org/app"

        [[bastions]]
        id = "00000000-0000-0000-0000-000000000001"
        name = "Jump"
        host = "jump.example.com"
        username = "ops"
        port = 22

        [[shortcuts]]
        id = "newTab"
        key = "t"
        modifiers = ["command"]
        """

        let decoded = try TomlConfigCodec.decode(fromString: toml)
        guard decoded.copyOnSelect, decoded.staleTabMinutes == 10 else {
            throw SmokeFailure.message("Phase 4 config fields not decoded")
        }
        guard decoded.bastionProfiles.count == 1, decoded.bastionProfiles[0].host == "jump.example.com" else {
            throw SmokeFailure.message("Bastion profiles not decoded")
        }
    }

    @MainActor
    private static func testSessionNotesKeychain() throws {
        let profileID = UUID()
        let account = "notes-\(profileID.uuidString)"
        defer { try? KeychainSecretStore.delete(account: account) }

        try SessionNotesHelper.storeNotes("runbook secret", for: profileID)
        var profile = SessionProfile(name: "Web", host: "web01", protocolType: .ssh, notes: "plain")
        profile.id = profileID
        profile.notesInKeychain = true

        let resolved = SessionNotesHelper.resolvedNotes(for: profile)
        guard resolved == "runbook secret" else {
            throw SmokeFailure.message("Keychain-backed notes not resolved")
        }

        profile.notesInKeychain = false
        profile.notes = "migrate me"
        guard SessionNotesHelper.migrateNotesToKeychain(for: &profile) else {
            throw SmokeFailure.message("Notes Keychain migration failed")
        }
        guard profile.notes.isEmpty, profile.notesInKeychain else {
            throw SmokeFailure.message("Notes not cleared after Keychain migration")
        }
    }

    @MainActor
    private static func testConnectionLauncherPhase4() throws {
        let bastionID = UUID()
        let bastion = BastionProfile(id: bastionID, name: "Jump", host: "jump.example.com", username: "ops")
        var profile = SessionProfile(name: "Internal", host: "internal", username: "root", protocolType: .ssh)
        profile.bastionProfileID = bastionID
        profile.remoteEnvironment = "FOO=bar"
        profile.remoteWorkingDirectory = "/var/www"

        let command = ConnectionLauncher.command(for: profile, bastions: [bastion])
        guard command.arguments.contains("-J"), command.arguments.contains("ops@jump.example.com") else {
            throw SmokeFailure.message("Bastion ProxyJump not applied")
        }

        let startup = ConnectionLauncher.resolvedStartupCommands(for: profile)
        guard startup.commands.contains(where: { $0.contains("export FOO=bar") }),
              startup.commands.contains(where: { $0.contains("cd '/var/www'") }) else {
            throw SmokeFailure.message("Remote env/cwd startup commands missing")
        }

        let tabCommand = ConnectionLauncher.command(
            for: profile,
            bastions: [bastion],
            tabOverrides: (remoteEnvironment: "TAB=1", remoteWorkingDirectory: "/tmp")
        )
        var overridden = profile
        overridden.remoteEnvironment = "TAB=1"
        overridden.remoteWorkingDirectory = "/tmp"
        let tabStartup = ConnectionLauncher.resolvedStartupCommands(for: overridden)
        guard tabStartup.commands.contains(where: { $0.contains("export TAB=1") }),
              tabStartup.commands.contains(where: { $0.contains("cd '/tmp'") }) else {
            throw SmokeFailure.message("Tab override startup commands missing")
        }
        guard tabCommand.executable == "/usr/bin/ssh" else {
            throw SmokeFailure.message("Tab override SSH command not built")
        }
    }

    @MainActor
    private static func testTerminalIOLogExport() throws {
        let tabID = UUID()
        let logsDir = FileLocations.logsDirectory
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logURL = logsDir.appendingPathComponent("terminal-io-smoke-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let line = "[2026-06-10 12:00:00.000] [OUTPUT] [tab=\(tabID.uuidString)] [local] hello"
        try line.write(to: logURL, atomically: true, encoding: .utf8)

        let lines = try TerminalIOLogExporter.collectLines(tabID: tabID, logsDirectory: logsDir)
        guard lines.count == 1, lines[0].contains("hello") else {
            throw SmokeFailure.message("I/O log export filter failed")
        }

        let redacted = TerminalIOLogExporter.redact("password=hunter2")
        guard redacted.contains("[REDACTED]"), !redacted.contains("hunter2") else {
            throw SmokeFailure.message("I/O log redaction failed")
        }
    }

    @MainActor
    private static func testSessionRecorder() throws {
        SessionRecorder.shared.configure(enabled: true, format: .asciinema)
        let tabID = UUID()
        SessionRecorder.shared.start(tabID: tabID, sessionName: "Smoke")
        SessionRecorder.shared.append(tabID: tabID, direction: "OUTPUT", data: ArraySlice("ok".utf8))
        guard let url = SessionRecorder.shared.recordingURL(for: tabID) else {
            throw SmokeFailure.message("Session recording URL missing")
        }
        SessionRecorder.shared.stop(tabID: tabID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SmokeFailure.message("Asciinema cast file not written")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.contains("\"version\":2"), text.contains("ok") else {
            throw SmokeFailure.message("Asciinema cast content invalid")
        }
        SessionRecorder.shared.configure(enabled: false)
    }

    @MainActor
    private static func testAppStateTabLifecycle() throws {
        let store = ConfigStore()
        let appState = AppState(configStore: store)
        appState.bootstrap()

        let tabID = appState.openLocalTab()
        guard appState.tabs.contains(where: { $0.id == tabID }) else {
            throw SmokeFailure.message("openLocalTab did not append tab")
        }

        appState.updateTabRemoteOverrides(
            tabID: tabID,
            remoteEnvironment: "SMOKE=1",
            remoteWorkingDirectory: "/tmp"
        )
        guard appState.tabs.first(where: { $0.id == tabID })?.remoteEnvironmentOverride == "SMOKE=1" else {
            throw SmokeFailure.message("Tab remote overrides not persisted")
        }

        appState.recordTerminalOutput(tabID: tabID)
        let health = appState.connectionHealth[tabID]
        guard health == .healthy || health == .unknown else {
            throw SmokeFailure.message("Unexpected tab health after output: \(String(describing: health))")
        }

        appState.closeTab(tabID)
        guard !appState.tabs.contains(where: { $0.id == tabID }) else {
            throw SmokeFailure.message("closeTab did not remove tab")
        }
    }

    @MainActor
    private static func testTabWorkspaceHealth() throws {
        let workspace = TabWorkspaceState()
        let tabID = UUID()
        workspace.setConnectionHealth(.stale, for: tabID)
        guard workspace.connectionHealth[tabID] == .stale else {
            throw SmokeFailure.message("TabWorkspaceState health not set")
        }
        workspace.removeConnectionHealth(for: tabID)
        guard workspace.connectionHealth[tabID] == nil else {
            throw SmokeFailure.message("TabWorkspaceState health not removed")
        }
    }

    @MainActor
    private static func testSessionLibraryState() throws {
        let library = SessionLibraryState()
        library.requestAction(.addNewSession)
        guard library.pendingAction == .addNewSession else {
            throw SmokeFailure.message("SessionLibraryState pending action not set")
        }
        library.consumeAction()
        guard library.pendingAction == nil else {
            throw SmokeFailure.message("SessionLibraryState pending action not cleared")
        }
    }

    @MainActor
    private static func testSessionExportRedaction() throws {
        var profile = SessionProfile(
            name: "Secret",
            host: "host",
            protocolType: .ssh,
            sshAuthMethod: .password,
            password: "pw",
            notes: "note text",
            notesInKeychain: true
        )
        let redacted = SessionExportRedactor.redactProfile(profile)
        guard redacted.password.isEmpty, redacted.notes.isEmpty, !redacted.notesInKeychain else {
            throw SmokeFailure.message("Export redaction incomplete")
        }
    }

    @MainActor
    private static func testANSIPaletteParsing() throws {
        guard ANSIPaletteCodec.parseColor(from: "#FF0000") != nil else {
            throw SmokeFailure.message("ANSI palette color parse failed")
        }
        guard ANSIPaletteCodec.parseColor(from: "not-a-color") == nil else {
            throw SmokeFailure.message("ANSI palette should reject invalid hex")
        }
    }
}
