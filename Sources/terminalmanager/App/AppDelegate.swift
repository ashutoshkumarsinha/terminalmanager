import AppKit

enum AppInfo {
    static let displayName = "Terminal Manager"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if SingleInstanceManager.shouldExitAsDuplicate() {
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyDisplayName()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard shouldConfirmOnExit() else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit \(AppInfo.displayName)?"
        alert.informativeText = "Any running terminal sessions will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowStateManager.saveMainWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            SingleInstanceManager.activateApplication()
        } else {
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func applyDisplayName() {
        if let appMenu = NSApp.mainMenu?.item(at: 0) {
            appMenu.title = AppInfo.displayName
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func shouldConfirmOnExit() -> Bool {
        let url = FileLocations.configTomlURL
        guard FileManager.default.fileExists(atPath: url.path),
              let settings = try? TomlConfigCodec.decode(from: url) else {
            return AppSettings.defaults.confirmOnExit
        }
        return settings.confirmOnExit
    }
}
