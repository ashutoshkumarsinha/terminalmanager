import Foundation

/// Tab workspace state extracted from `AppState` (TE-02).
@MainActor
final class TabWorkspaceState: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var splitLayouts: [UUID: SplitLayoutNode] = [:]
    @Published var detachedTabs: [TerminalTab] = []
    @Published var tabPendingReconnect: TerminalTab?
    @Published var pendingDetachedWindowTabID: UUID?
    @Published private(set) var connectionHealth: [UUID: TabConnectionHealth] = [:]

    var stripTabs: [TerminalTab] {
        tabs.filter { !$0.isSplitPane }
    }

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedTabID }
    }

    func stripTabID(for tabID: UUID) -> UUID? {
        if tabs.contains(where: { $0.id == tabID && !$0.isSplitPane }) {
            return tabID
        }
        return splitLayoutAnchor(containing: tabID)
    }

    func isStripTabSelected(_ id: UUID) -> Bool {
        guard let selectedTabID else { return false }
        return stripTabID(for: selectedTabID) == id
    }

    func splitLayout(containing tabID: UUID) -> SplitLayoutNode? {
        for layout in splitLayouts.values where layout.isSplitTree && layout.tabIDsInLayout().contains(tabID) {
            return layout
        }
        return nil
    }

    func hasSplitLayout(for tabID: UUID) -> Bool {
        splitLayout(containing: tabID) != nil
    }

    func setConnectionHealth(_ health: TabConnectionHealth, for tabID: UUID) {
        if connectionHealth[tabID] != health {
            connectionHealth[tabID] = health
        }
    }

    func removeConnectionHealth(for tabID: UUID) {
        connectionHealth.removeValue(forKey: tabID)
    }

    func setSplitLayout(_ layout: SplitLayoutNode, anchor: UUID) {
        if layout.isSplitTree {
            splitLayouts[anchor] = layout
        } else {
            splitLayouts.removeValue(forKey: anchor)
        }
    }

    func removeTabFromSplitLayouts(_ tabID: UUID) {
        let anchors = splitLayouts.keys.filter { splitLayouts[$0]?.tabIDsInLayout().contains(tabID) == true }
        for anchor in anchors {
            guard let layout = splitLayouts[anchor],
                  let updated = removeTabFromLayout(tabID, in: layout) else {
                splitLayouts.removeValue(forKey: anchor)
                continue
            }
            setSplitLayout(updated, anchor: anchor)
        }
    }

    func replacePane(
        containing tabID: UUID,
        in node: SplitLayoutNode,
        with replacement: SplitLayoutNode
    ) -> SplitLayoutNode {
        if node.tabID == tabID {
            return replacement
        }
        guard node.children.count == 2 else { return node }
        var updated = node
        updated.children[0] = replacePane(containing: tabID, in: node.children[0], with: replacement)
        updated.children[1] = replacePane(containing: tabID, in: node.children[1], with: replacement)
        return updated
    }

    func splitLayoutEntry(containing tabID: UUID) -> (anchor: UUID, layout: SplitLayoutNode)? {
        for (anchor, layout) in splitLayouts where layout.isSplitTree && layout.tabIDsInLayout().contains(tabID) {
            return (anchor, layout)
        }
        return nil
    }

    func clearSplitLayouts() {
        splitLayouts.removeAll()
    }

    func removeSplitLayout(anchor: UUID) {
        splitLayouts.removeValue(forKey: anchor)
    }

    func splitLayout(at anchor: UUID) -> SplitLayoutNode? {
        splitLayouts[anchor]
    }

    private func splitLayoutAnchor(containing tabID: UUID) -> UUID? {
        for (anchor, layout) in splitLayouts where layout.isSplitTree && layout.tabIDsInLayout().contains(tabID) {
            return anchor
        }
        return nil
    }

    private func removeTabFromLayout(_ tabID: UUID, in node: SplitLayoutNode) -> SplitLayoutNode? {
        if node.tabID == tabID { return nil }
        guard node.children.count == 2 else { return node }
        let left = removeTabFromLayout(tabID, in: node.children[0])
        let right = removeTabFromLayout(tabID, in: node.children[1])
        switch (left, right) {
        case (nil, nil):
            return nil
        case (nil, let right?):
            return right
        case (let left?, nil):
            return left
        case (let left?, let right?):
            return SplitLayoutNode(orientation: node.orientation, children: [left, right], ratio: node.ratio)
        }
    }
}
