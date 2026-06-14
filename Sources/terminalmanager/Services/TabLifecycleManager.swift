import Foundation

/// Tracks tab visibility and hibernates inactive PTYs (Phase 3.1).
@MainActor
final class TabLifecycleManager {
    private var mainWindowVisibleTabIDs: Set<UUID> = []
    private var detachedVisibleTabIDs: Set<UUID> = []
    private var lastActiveAt: [UUID: Date] = [:]
    private var hibernationTimer: Timer?

    var onHibernate: ((UUID) -> Void)?

    func startMonitoring(intervalSeconds: TimeInterval = 60) {
        hibernationTimer?.invalidate()
        hibernationTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onHibernateTick?()
            }
        }
    }

    var onHibernateTick: (() -> Void)?

    func stopMonitoring() {
        hibernationTimer?.invalidate()
        hibernationTimer = nil
    }

    func updateMainWindowVisibleTabs(_ ids: Set<UUID>, now: Date = Date()) {
        recordVisibilityChange(from: mainWindowVisibleTabIDs, to: ids, now: now)
        mainWindowVisibleTabIDs = ids
    }

    func updateDetachedVisibleTab(_ tabID: UUID, isVisible: Bool, now: Date = Date()) {
        if isVisible {
            detachedVisibleTabIDs.insert(tabID)
            lastActiveAt[tabID] = now
        } else {
            detachedVisibleTabIDs.remove(tabID)
            lastActiveAt[tabID] = now
        }
    }

    func removeTab(_ tabID: UUID) {
        mainWindowVisibleTabIDs.remove(tabID)
        detachedVisibleTabIDs.remove(tabID)
        lastActiveAt.removeValue(forKey: tabID)
    }

    func touchTab(_ tabID: UUID, now: Date = Date()) {
        lastActiveAt[tabID] = now
    }

    func runHibernationCheck(
        tabIDs: [UUID],
        runningTabIDs: Set<UUID>,
        inactivityMinutes: Int,
        now: Date = Date()
    ) {
        guard inactivityMinutes > 0 else { return }
        let visible = TabLifecyclePolicy.mergedVisibleTabIDs(
            mainWindow: mainWindowVisibleTabIDs,
            detached: detachedVisibleTabIDs
        )
        let candidates = TabLifecyclePolicy.tabIDsToHibernate(
            tabIDs: tabIDs,
            visibleTabIDs: visible,
            runningTabIDs: runningTabIDs,
            lastActiveAt: lastActiveAt,
            now: now,
            inactivityMinutes: inactivityMinutes
        )
        for tabID in candidates {
            onHibernate?(tabID)
        }
    }

    private func recordVisibilityChange(from old: Set<UUID>, to new: Set<UUID>, now: Date) {
        for tabID in new {
            lastActiveAt[tabID] = now
        }
        for tabID in old.subtracting(new) {
            lastActiveAt[tabID] = now
        }
    }
}
