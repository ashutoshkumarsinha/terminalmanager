import AppKit
import Foundation

struct SavedWindowState: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isZoomed: Bool

    init(frame: NSRect, isZoomed: Bool) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.size.width
        height = frame.size.height
        self.isZoomed = isZoomed
    }

    var frame: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

enum WindowStateManager {
    private static var stateURL: URL {
        FileLocations.configDirectory.appendingPathComponent("window-state.json")
    }

    static func applyLaunchSettings(to window: NSWindow, settings: AppSettings) {
        if settings.restoreWindowPosition, let saved = load() {
            window.setFrame(clampedFrame(saved.frame, for: window), display: false)
            if settings.startMaximized || saved.isZoomed {
                window.zoom(nil)
            }
        } else if settings.startMaximized {
            window.zoom(nil)
        }
    }

    static func save(from window: NSWindow) {
        guard currentSettings().restoreWindowPosition else { return }
        let state = SavedWindowState(frame: window.frame, isZoomed: window.isZoomed)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            AppLogger.shared.error("Failed to save window state: \(error)")
        }
    }

    static func saveMainWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { $0.isMainWindow || $0.title == AppInfo.displayName }) else {
            return
        }
        save(from: window)
    }

    private static var detachedStateURL: URL {
        FileLocations.configDirectory.appendingPathComponent("detached-window-state.json")
    }

    static func applyDetachedLaunchSettings(to window: NSWindow, tabID: UUID) {
        guard currentSettings().restoreWindowPosition,
              let states = loadDetachedStates(),
              let saved = states[tabID.uuidString] else {
            return
        }
        window.setFrame(clampedFrame(saved.frame, for: window), display: false)
        if saved.isZoomed {
            window.zoom(nil)
        }
    }

    static func saveDetached(from window: NSWindow, tabID: UUID) {
        guard currentSettings().restoreWindowPosition else { return }
        var states = loadDetachedStates() ?? [:]
        states[tabID.uuidString] = SavedWindowState(frame: window.frame, isZoomed: window.isZoomed)
        do {
            let data = try JSONEncoder().encode(states)
            try data.write(to: detachedStateURL, options: .atomic)
        } catch {
            AppLogger.shared.error("Failed to save detached window state: \(error)")
        }
    }

    private static func loadDetachedStates() -> [String: SavedWindowState]? {
        guard FileManager.default.fileExists(atPath: detachedStateURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: detachedStateURL)
            return try JSONDecoder().decode([String: SavedWindowState].self, from: data)
        } catch {
            AppLogger.shared.error("Failed to load detached window state: \(error)")
            return nil
        }
    }

    private static func load() -> SavedWindowState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: stateURL)
            return try JSONDecoder().decode(SavedWindowState.self, from: data)
        } catch {
            AppLogger.shared.error("Failed to load window state: \(error)")
            return nil
        }
    }

    private static func clampedFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        var adjusted = frame

        if adjusted.width > visible.width {
            adjusted.size.width = visible.width
        }
        if adjusted.height > visible.height {
            adjusted.size.height = visible.height
        }
        if adjusted.width < 640 {
            adjusted.size.width = 640
        }
        if adjusted.height < 480 {
            adjusted.size.height = 480
        }

        if adjusted.maxX > visible.maxX {
            adjusted.origin.x = visible.maxX - adjusted.width
        }
        if adjusted.minX < visible.minX {
            adjusted.origin.x = visible.minX
        }
        if adjusted.maxY > visible.maxY {
            adjusted.origin.y = visible.maxY - adjusted.height
        }
        if adjusted.minY < visible.minY {
            adjusted.origin.y = visible.minY
        }

        return adjusted
    }

    private static func currentSettings() -> AppSettings {
        let url = FileLocations.configTomlURL
        guard FileManager.default.fileExists(atPath: url.path),
              let settings = try? TomlConfigCodec.decode(from: url) else {
            return AppSettings.defaults
        }
        return settings
    }
}

final class MainWindowObserver: NSObject {
    private var observers: [NSObjectProtocol] = []
    private weak var window: NSWindow?
    private(set) var didApplyLaunchSettings = false
    var didAttachWindow = false
    private var persistWorkItem: DispatchWorkItem?

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.persistWindowState()
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                self?.persistWindowState()
            }
        ]
    }

    func markLaunchSettingsApplied() {
        didApplyLaunchSettings = true
    }

    func detach() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        window = nil
    }

    private func persistWindowState() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let window = self?.window else { return }
            WindowStateManager.save(from: window)
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    deinit {
        detach()
    }
}
