import Foundation

/// Watches `sync_path` for external changes and triggers reload (PF-34).
final class SessionsSyncWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.terminalmanager.sessions-sync")
    private var source: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var onExternalChange: (() -> Void)?

    func start(watchURL: URL, onExternalChange: @escaping () -> Void) {
        stop()
        self.onExternalChange = onExternalChange
        watchedURL = watchURL

        let directory = watchURL.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let watchedURL = self.watchedURL else { return }
            let filename = watchedURL.lastPathComponent
            let eventPath = directory.appendingPathComponent(filename).path
            guard FileManager.default.fileExists(atPath: eventPath) else { return }
            DispatchQueue.main.async {
                self.onExternalChange?()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        watchedURL = nil
        onExternalChange = nil
    }

    deinit {
        stop()
    }
}
