import AppKit
import Foundation

enum GhosttyBridge {
    static let defaultAppPath = "/Applications/Ghostty.app"

    static func launch(profile: SessionProfile, ghosttyAppPath: String) throws {
        let appName = appleScriptApplicationName(for: ghosttyAppPath)
        let shellCommand = ConnectionLauncher.externalShellCommand(for: profile)
        let workingDirectory = resolvedWorkingDirectory(for: profile)
        let initInput = ConnectionLauncher.initialInput(for: profile)
        let script = buildLaunchScript(
            appName: appName,
            command: shellCommand,
            workingDirectory: workingDirectory,
            initialInput: initInput,
            tabTitle: profile.name
        )
        try runAppleScript(script)
    }

    static func launchSFTP(profile: SessionProfile, ghosttyAppPath: String) throws {
        guard let command = ConnectionLauncher.sftpCommand(for: profile) else { return }
        let appName = appleScriptApplicationName(for: ghosttyAppPath)
        let workingDirectory = resolvedWorkingDirectory(for: profile)
        let script = buildLaunchScript(
            appName: appName,
            command: command.displayCommand,
            workingDirectory: workingDirectory,
            initialInput: nil,
            tabTitle: profile.name
        )
        try runAppleScript(script)
    }

    static func openAutomationSettings() {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ]
        for urlString in urlStrings {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private static func buildLaunchScript(
        appName: String,
        command: String?,
        workingDirectory: String,
        initialInput: String?,
        tabTitle: String
    ) -> String {
        let escapedTitle = escapeForAppleScript(tabTitle)
        var configLines: [String] = [
            "    set cfg to new surface configuration",
            "    set initial working directory of cfg to \"\(escapeForAppleScript(workingDirectory))\""
        ]

        if let command, !command.isEmpty {
            configLines.append("    set command of cfg to \"\(escapeForAppleScript(command))\"")
            configLines.append("    set wait after command of cfg to true")
        }

        if let initialInput, !initialInput.isEmpty {
            configLines.append("    set initial input of cfg to \"\(escapeForAppleScript(initialInput))\"")
        }

        let configBlock = configLines.joined(separator: "\n")

        return """
        tell application "\(appName)"
            activate
        \(configBlock)
            try
                set targetWindow to front window
                set newTab to new tab in targetWindow with configuration cfg
            on error
                set targetWindow to new window with configuration cfg
                set newTab to selected tab of targetWindow
            end try
            try
                set name of newTab to "\(escapedTitle)"
            end try
        end tell
        """
    }

    private static func resolvedWorkingDirectory(for profile: SessionProfile) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let path = profile.initialDirectory, !path.isEmpty else { return home }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return expanded
        }
        return home
    }

    private static func appleScriptApplicationName(for appPath: String) -> String {
        let last = (appPath as NSString).lastPathComponent
        if last.hasSuffix(".app") {
            return (last as NSString).deletingPathExtension
        }
        return last.isEmpty ? "Ghostty" : last
    }

    private static func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: source)
        appleScript?.executeAndReturnError(&error)
        if let error {
            throw parseAppleScriptError(error)
        }
    }

    private static func parseAppleScriptError(_ error: NSDictionary) -> GhosttyBridgeError {
        let numberString = error["ErrorNumber"] as? String ?? error["NSAppleScriptErrorNumber"] as? String
        if numberString == "-1743" {
            return .automationNotAuthorized
        }
        if let number = error["ErrorNumber"] as? Int, number == -1743 {
            return .automationNotAuthorized
        }
        let message = error["Message"] as? String
            ?? error["NSAppleScriptErrorMessage"] as? String
            ?? error.description
        return .appleScriptFailed(message)
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

enum GhosttyBridgeError: LocalizedError {
    case automationNotAuthorized
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationNotAuthorized:
            """
            Terminal Manager is not allowed to control Ghostty.

            Grant access in System Settings → Privacy & Security → Automation:
            enable “Ghostty” for Terminal Manager, then try again.

            Rebuild and reopen the app (bash scripts/run-app.sh) if Ghostty is not listed.
            """
        case .appleScriptFailed(let detail):
            "Ghostty automation failed: \(detail)"
        }
    }

    var offersAutomationSettings: Bool {
        if case .automationNotAuthorized = self { return true }
        return false
    }
}
