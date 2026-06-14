import Foundation

/// Debounced and off-main persistence for launch state and sessions JSON.
enum PersistenceCoordinator {
    private static let sessionsWriteQueue = DispatchQueue(
        label: "com.terminalmanager.sessions-write",
        qos: .utility
    )

    private static var launchStateWorkItem: DispatchWorkItem?
    private static var pendingLaunchState: LaunchState?
    private static var sessionsSaveWorkItem: DispatchWorkItem?

    // MARK: - Launch state

    static func scheduleLaunchStateSave(_ state: LaunchState, debounceMs: Int) {
        pendingLaunchState = state
        launchStateWorkItem?.cancel()

        let interval = max(0, debounceMs)
        if interval == 0 {
            flushLaunchState(with: state)
            return
        }

        let item = DispatchWorkItem {
            flushLaunchState()
        }
        launchStateWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(interval), execute: item)
    }

    static func flushLaunchState(with state: LaunchState? = nil) {
        launchStateWorkItem?.cancel()
        launchStateWorkItem = nil
        if let state {
            pendingLaunchState = nil
            try? LaunchStateStore.save(state)
            return
        }
        guard let pending = pendingLaunchState else { return }
        pendingLaunchState = nil
        try? LaunchStateStore.save(pending)
    }

    static func clearLaunchState() {
        launchStateWorkItem?.cancel()
        launchStateWorkItem = nil
        pendingLaunchState = nil
        LaunchStateStore.clear()
    }

    // MARK: - Sessions JSON

    static func scheduleSessionsSave(
        tree: [SessionTreeItem],
        to url: URL,
        debounceMs: Int = 250,
        offMain: Bool = true
    ) {
        sessionsSaveWorkItem?.cancel()

        let item = DispatchWorkItem {
            writeSessions(tree: tree, to: url, offMain: offMain)
            sessionsSaveWorkItem = nil
        }
        sessionsSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, debounceMs)), execute: item)
    }

    static func flushSessionsSave(
        tree: [SessionTreeItem],
        to url: URL,
        offMain: Bool = true
    ) {
        sessionsSaveWorkItem?.cancel()
        sessionsSaveWorkItem = nil
        writeSessions(tree: tree, to: url, offMain: offMain)
    }

    private static func writeSessions(tree: [SessionTreeItem], to url: URL, offMain: Bool) {
        let config = SessionConfiguration(version: 1, sessionTree: tree)
        if offMain {
            sessionsWriteQueue.async {
                performSessionsWrite(config: config, to: url)
            }
        } else {
            performSessionsWrite(config: config, to: url)
        }
    }

    private static func performSessionsWrite(config: SessionConfiguration, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            DispatchQueue.main.async {
                AppLogger.shared.error("Failed to save sessions: \(error)")
            }
        }
    }
}
