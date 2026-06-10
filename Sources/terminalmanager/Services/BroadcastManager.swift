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

    func hasHandler(for tabID: UUID) -> Bool {
        sendHandlers[tabID] != nil
    }

    func canSend(to tabIDs: [UUID], commandText: String? = nil) -> Bool {
        let text = commandText ?? self.commandText
        return !resolvedTabIDs(from: tabIDs).isEmpty && Self.normalizedPayload(from: text) != nil
    }

    func send(to tabIDs: [UUID]) {
        guard let payload = Self.normalizedPayload(from: commandText) else { return }

        for tabID in resolvedTabIDs(from: tabIDs) {
            sendHandlers[tabID]?(payload)
        }
        commandText = ""
    }

    /// Turns command-bar text into terminal input, preserving one line per command.
    static func normalizedPayload(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lines = trimmed.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return nil }

        return lines.map { String($0) + "\n" }.joined()
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
