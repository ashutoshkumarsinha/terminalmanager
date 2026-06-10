import Foundation

enum CommandTarget: String, CaseIterable, Identifiable {
    case selectedTab
    case allTabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selectedTab: "Selected Tab"
        case .allTabs: "All Tabs"
        }
    }
}

@MainActor
final class BroadcastManager: ObservableObject {
    @Published var commandText: String = ""
    @Published var target: CommandTarget = .selectedTab

    private var sendHandlers: [UUID: (String) -> Void] = [:]

    func register(tabID: UUID, handler: @escaping (String) -> Void) {
        sendHandlers[tabID] = handler
    }

    func unregister(tabID: UUID) {
        sendHandlers.removeValue(forKey: tabID)
    }

    func canSend(to tabIDs: [UUID]) -> Bool {
        !resolvedTabIDs(from: tabIDs).isEmpty && !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(to tabIDs: [UUID]) {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        let payload = command.hasSuffix("\n") ? command : command + "\n"
        for tabID in resolvedTabIDs(from: tabIDs) {
            sendHandlers[tabID]?(payload)
        }
        commandText = ""
    }

    func send(using tabIDs: [UUID], selectedTabID: UUID?) {
        let targets: [UUID]
        switch target {
        case .selectedTab:
            guard let selectedTabID else { return }
            targets = [selectedTabID]
        case .allTabs:
            targets = tabIDs
        }
        send(to: targets)
    }

    private func resolvedTabIDs(from tabIDs: [UUID]) -> [UUID] {
        tabIDs.filter { sendHandlers[$0] != nil }
    }
}
