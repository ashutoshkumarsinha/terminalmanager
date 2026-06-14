import Foundation

/// Marks tabs stale when no terminal output received for a configured interval (EN-10).
@MainActor
final class ConnectionHealthMonitor {
    private var lastOutputAt: [UUID: Date] = [:]
    private var timer: Timer?
    private var staleAfterSeconds: TimeInterval = 300
    var onEvaluate: (() -> Void)?

    func configure(staleAfterMinutes: Int) {
        staleAfterSeconds = TimeInterval(max(1, staleAfterMinutes) * 60)
    }

    func start(intervalSeconds: TimeInterval = 30) {
        timer?.invalidate()
        guard staleAfterSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onEvaluate?() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func recordOutput(tabID: UUID, at date: Date = Date()) {
        lastOutputAt[tabID] = date
    }

    func removeTab(_ tabID: UUID) {
        lastOutputAt.removeValue(forKey: tabID)
    }

    func touchTab(_ tabID: UUID, at date: Date = Date()) {
        lastOutputAt[tabID] = date
    }

    func health(for tabID: UUID, isRunning: Bool, now: Date = Date()) -> TabConnectionHealth {
        let last = lastOutputAt[tabID] ?? .distantPast
        let cutoff = now.addingTimeInterval(-staleAfterSeconds)
        if last >= cutoff {
            return .healthy
        }
        guard isRunning else { return .unknown }
        return .stale
    }
}
