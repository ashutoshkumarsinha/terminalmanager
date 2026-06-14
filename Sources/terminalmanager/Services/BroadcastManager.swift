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
    @Published private(set) var commandHistory: [String] = []
    @Published var presets: [String: String] = [:]

    private static let maxHistoryCount = 20
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

    func canSend(to tabIDs: [UUID], eligibleTabIDs: [UUID]? = nil, commandText: String? = nil) -> Bool {
        let text = commandText ?? self.commandText
        let resolved = resolvedTabIDs(from: tabIDs, eligibleTabIDs: eligibleTabIDs)
        return !resolved.isEmpty && Self.normalizedPayload(from: text) != nil
    }

    func send(to tabIDs: [UUID], eligibleTabIDs: [UUID]? = nil, batchDelayMs: Int = 0) {
        guard let payload = Self.normalizedPayload(from: commandText) else { return }

        let targets = resolvedTabIDs(from: tabIDs, eligibleTabIDs: eligibleTabIDs)
        guard !targets.isEmpty else { return }

        if batchDelayMs > 0 && targets.count > 1 {
            Task { @MainActor in
                for tabID in targets {
                    sendHandlers[tabID]?(payload)
                    try? await Task.sleep(nanoseconds: UInt64(batchDelayMs) * 1_000_000)
                }
            }
        } else {
            for tabID in targets {
                sendHandlers[tabID]?(payload)
            }
        }
        recordCommand(commandText)
        commandText = ""
    }

    func recordCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commandHistory.removeAll { $0 == trimmed }
        commandHistory.insert(trimmed, at: 0)
        if commandHistory.count > Self.maxHistoryCount {
            commandHistory = Array(commandHistory.prefix(Self.maxHistoryCount))
        }
    }

    func applyPreset(_ name: String) {
        guard let preset = presets[name] else { return }
        commandText = preset
    }

    func setPreset(_ name: String, command: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        presets[trimmedName] = command
    }

    func removePreset(_ name: String) {
        presets.removeValue(forKey: name)
    }

    /// Turns command-bar text into terminal input, preserving one line per command.
    static func normalizedPayload(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lines = trimmed.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return nil }

        return lines.map { String($0) + "\n" }.joined()
    }

    func send(
        using tabIDs: [UUID],
        selectedTabID: UUID?,
        eligibleTabIDs: [UUID]? = nil,
        batchDelayMs: Int = 0
    ) {
        let targets: [UUID]
        switch target {
        case .selectedTab:
            guard let selectedTabID else { return }
            targets = [selectedTabID]
        case .allTabs:
            targets = tabIDs
        }
        send(to: targets, eligibleTabIDs: eligibleTabIDs, batchDelayMs: batchDelayMs)
    }

    private func resolvedTabIDs(from tabIDs: [UUID], eligibleTabIDs: [UUID]?) -> [UUID] {
        let withHandlers = tabIDs.filter { sendHandlers[$0] != nil }
        guard let eligibleTabIDs else { return withHandlers }
        let eligible = Set(eligibleTabIDs)
        return withHandlers.filter { eligible.contains($0) }
    }
}
