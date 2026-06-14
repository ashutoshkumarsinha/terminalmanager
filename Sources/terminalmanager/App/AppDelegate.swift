import AppKit

enum AppInfo {
    static let displayName = "Terminal Manager"
}

extension Notification.Name {
    static let openUserGuideRequested = Notification.Name("com.terminalmanager.openUserGuide")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var pendingOpenURLs: [String] = []
    var onTerminateFlush: (() -> Void)?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let connectionString = Self.connectionString(from: url) {
                pendingOpenURLs.append(connectionString)
            }
        }
    }

    func dequeuePendingOpenURLs() -> [String] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    static func connectionString(from url: URL) -> String? {
        if url.scheme?.lowercased() == "terminalmanager" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let uri = components?.queryItems?.first(where: { $0.name == "uri" })?.value {
                return uri.removingPercentEncoding ?? uri
            }
            return nil
        }
        return url.absoluteString
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("-smoke-test") {
            let code: Int32
            if Thread.isMainThread {
                code = MainActor.assumeIsolated { SmokeTestRunner.run() }
            } else {
                code = DispatchQueue.main.sync { SmokeTestRunner.run() }
            }
            exit(code)
        }
        if SingleInstanceManager.shouldExitAsDuplicate() {
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyDisplayName()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, openHelpAnchor helpAnchor: String?) -> Bool {
        NotificationCenter.default.post(name: .openUserGuideRequested, object: nil)
        return true
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
        onTerminateFlush?()
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
