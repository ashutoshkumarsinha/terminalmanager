import AppKit
import SwiftUI

@main
struct TerminalManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(AppInfo.displayName) {
            MainWindowView()
                .environmentObject(appState)
                .onAppear {
                    appState.bootstrap()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { appState.openLocalTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") {
                    if let id = appState.selectedTabID { appState.closeTab(id) }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Session") {
                Button("Duplicate Tab") { appState.duplicateSelectedTab() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Next Tab") { appState.selectNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { appState.selectPreviousTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                Button("Split Horizontally") { appState.splitSelectedTab(orientation: .horizontal) }
                Button("Split Vertically") { appState.splitSelectedTab(orientation: .vertical) }
                Divider()
                Button("Focus Command Bar") {
                    if !appState.settings.showCommandBar {
                        var settings = appState.settings
                        settings.showCommandBar = true
                        appState.settings = settings
                    }
                    appState.focusCommandBar = true
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Toggle("Show Session Sidebar", isOn: Binding(
                    get: { appState.settings.showSidebar },
                    set: { newValue in
                        var settings = appState.settings
                        settings.showSidebar = newValue
                        appState.settings = settings
                    }
                ))
                .help("Show or hide the session list sidebar")

                Toggle("Show Command Toolbar", isOn: Binding(
                    get: { appState.settings.showCommandBar },
                    set: { newValue in
                        var settings = appState.settings
                        settings.showCommandBar = newValue
                        appState.settings = settings
                    }
                ))
                .help("Show or hide the send-command bar above the tab strip")
                .disabled(!appState.settings.broadcastEnabled)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        WindowGroup("Detached Session", id: "detached", for: UUID.self) { $tabID in
            if let tabID {
                DetachedWindowView(tabID: tabID)
                    .environmentObject(appState)
            }
        }
    }
}
