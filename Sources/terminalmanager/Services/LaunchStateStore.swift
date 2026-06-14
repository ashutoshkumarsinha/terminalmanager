import Foundation

/// Persists open-tab snapshot for optional restore on launch (`restoreTabsOnLaunch`).
struct LaunchState: Codable, Equatable {
    /// Strip-tab profile IDs in tab-strip order.
    var tabProfileIDs: [UUID]
    var selectedTabProfileID: UUID?
    /// Split layouts keyed by anchor tab profile ID; leaf `tabID` values are profile IDs.
    var splitLayouts: [UUID: SplitLayoutNode]

    init(
        tabProfileIDs: [UUID] = [],
        selectedTabProfileID: UUID? = nil,
        splitLayouts: [UUID: SplitLayoutNode] = [:]
    ) {
        self.tabProfileIDs = tabProfileIDs
        self.selectedTabProfileID = selectedTabProfileID
        self.splitLayouts = splitLayouts
    }
}

enum LaunchStateStore {
    private static var launchStateURL: URL {
        FileLocations.configDirectory.appendingPathComponent("launch-state.json")
    }

    static func save(_ state: LaunchState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: FileLocations.configDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: launchStateURL, options: .atomic)
    }

    static func load() -> LaunchState? {
        let url = launchStateURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(LaunchState.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: launchStateURL)
    }
}
