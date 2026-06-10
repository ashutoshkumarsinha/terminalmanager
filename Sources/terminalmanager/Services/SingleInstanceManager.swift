import AppKit
import Darwin
import Foundation

enum SingleInstanceManager {
    private static let activationNotification = Notification.Name("com.terminalmanager.app.activate")
    private static var lockFileDescriptor: Int32 = -1
    private static var observerToken: NSObjectProtocol?

    /// Returns `true` when another instance is already running and this process should exit.
    static func shouldExitAsDuplicate() -> Bool {
        guard isEnabled() else { return false }

        let lockURL = lockFileURL()
        try? FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }

        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        lock.l_start = 0
        lock.l_len = 0

        if fcntl(fd, F_SETLK, &lock) == -1 {
            close(fd)
            notifyExistingInstance()
            return true
        }

        lockFileDescriptor = fd
        installActivationHandler()
        return false
    }

    static func activateApplication() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: \.isMainWindow) {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func isEnabled() -> Bool {
        let url = FileLocations.configTomlURL
        guard FileManager.default.fileExists(atPath: url.path),
              let settings = try? TomlConfigCodec.decode(from: url) else {
            return AppSettings.defaults.singleInstance
        }
        return settings.singleInstance
    }

    private static func lockFileURL() -> URL {
        FileLocations.configDirectory.appendingPathComponent("instance.lock")
    }

    private static func notifyExistingInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            activationNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func installActivationHandler() {
        guard observerToken == nil else { return }
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: activationNotification,
            object: nil,
            queue: .main
        ) { _ in
            activateApplication()
        }
    }
}
