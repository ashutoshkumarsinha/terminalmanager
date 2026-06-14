import Foundation

/// Pure logic for deciding which tabs should hibernate (PF-10, PF-12).
enum TabLifecyclePolicy {
    static func tabIDsToHibernate(
        tabIDs: [UUID],
        visibleTabIDs: Set<UUID>,
        runningTabIDs: Set<UUID>,
        lastActiveAt: [UUID: Date],
        now: Date,
        inactivityMinutes: Int
    ) -> [UUID] {
        guard inactivityMinutes > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(inactivityMinutes * 60))
        return tabIDs.filter { tabID in
            !visibleTabIDs.contains(tabID)
                && runningTabIDs.contains(tabID)
                && (lastActiveAt[tabID] ?? .distantPast) <= cutoff
        }
    }

    static func mergedVisibleTabIDs(mainWindow: Set<UUID>, detached: Set<UUID>) -> Set<UUID> {
        mainWindow.union(detached)
    }
}
