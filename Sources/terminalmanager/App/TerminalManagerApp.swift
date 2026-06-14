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
                .environmentObject(appState.tabWorkspace)
                .environmentObject(appState.sessionLibrary)
                .environmentObject(appState.configStore)
                .environment(\.showTooltips, appState.settings.showTooltips)
                .onAppear {
                    appState.bootstrap()
                    appState.consumePendingConnectionRequests()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onOpenURL { url in
                    if let connectionString = AppDelegate.connectionString(from: url) {
                        appState.openConnectionString(connectionString)
                    }
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
                Button("Find in Terminal…") { appState.showFindBar = true }
                    .keyboardShortcut("f", modifiers: .command)
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

            CommandGroup(replacing: .help) {
                Button("\(AppInfo.displayName) Help") {
                    appState.openUserGuide = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Button("New Folder") {
                    appState.requestSessionTreeAction(.createFolder)
                }
                Button("Rename Folder…") {
                    appState.requestSessionTreeAction(.renameFolder)
                }
                .disabled(appState.selectedSessionTreeFolder == nil)
                Button("Delete Folder") {
                    appState.requestSessionTreeAction(.deleteFolder)
                }
                .disabled(appState.selectedSessionTreeFolder == nil)
                Divider()
                Button("New Session…") {
                    appState.requestSessionTreeAction(.addNewSession)
                }
                Button("Create Group from Open Tabs…") {
                    appState.requestSessionTreeAction(.createGroupFromOpenTabs)
                }
                .disabled(!appState.canCreateGroupFromOpenTabs)
                Divider()
                Button("Export Terminal Transcript…") {
                    appState.exportActiveTabTranscript(selectionOnly: false)
                }
                Button("Export Terminal Selection…") {
                    appState.exportActiveTabTranscript(selectionOnly: true)
                }
                Button("Export Tab I/O Log…") {
                    appState.exportActiveTabIOLog(redactSecrets: true)
                }
                Button("Export Session Recording…") {
                    appState.exportActiveTabRecording()
                }
                Button("Reveal Session Recording") {
                    appState.revealActiveTabRecording()
                }
                Divider()
                Button("Check for Updates…") {
                    Task { await appState.checkForUpdates(userInitiated: true) }
                }
            }

            CommandGroup(replacing: .sidebar) {
                Toggle("Show Session Sidebar", isOn: Binding(
                    get: { appState.settings.showSidebar },
                    set: { newValue in
                        var settings = appState.settings
                        settings.showSidebar = newValue
                        appState.settings = settings
                    }
                ))
                .appHelp("Show or hide the session list sidebar", showTooltips: appState.settings.showTooltips)
            }

            CommandGroup(after: .sidebar) {
                Toggle("Show Command Bar", isOn: Binding(
                    get: { appState.settings.showCommandBar },
                    set: { newValue in
                        var settings = appState.settings
                        settings.showCommandBar = newValue
                        appState.settings = settings
                    }
                ))
                .appHelp("Show or hide the command bar above the tab strip", showTooltips: appState.settings.showTooltips)

                Toggle("Show Tooltips", isOn: Binding(
                    get: { appState.settings.showTooltips },
                    set: { newValue in
                        var settings = appState.settings
                        settings.showTooltips = newValue
                        appState.settings = settings
                    }
                ))
                .appHelp("Show or hide hover help text on buttons and controls", showTooltips: appState.settings.showTooltips)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.tabWorkspace)
                .environmentObject(appState.sessionLibrary)
                .environmentObject(appState.configStore)
                .environment(\.showTooltips, appState.settings.showTooltips)
        }

        Window("User Guide", id: "userGuide") {
            UserGuideView()
        }
        .defaultSize(width: 720, height: 640)

        WindowGroup("Detached Session", id: "detached", for: UUID.self) { $tabID in
            if let tabID {
                DetachedWindowView(tabID: tabID)
                    .environmentObject(appState)
                    .environmentObject(appState.tabWorkspace)
                    .environmentObject(appState.sessionLibrary)
                    .environmentObject(appState.configStore)
                    .environment(\.showTooltips, appState.settings.showTooltips)
            }
        }
    }
}
