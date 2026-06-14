import Foundation

/// Session recording per tab — plain text or asciinema v2 cast (EN-03).
final class SessionRecorder: @unchecked Sendable {
    static let shared = SessionRecorder()

    private let queue = DispatchQueue(label: "com.terminalmanager.session-recorder", qos: .utility)
    private var enabled = false
    private var format: SessionRecordingFormat = .plain
    private var states: [UUID: TabRecordingState] = [:]

    private struct TabRecordingState {
        let startDate: Date
        let sessionName: String
        var cols: Int
        var rows: Int
        var events: [AsciinemaCastEvent]
        var plainHandle: FileHandle?
        let url: URL
    }

    private init() {}

    func configure(enabled: Bool, format: SessionRecordingFormat = .plain) {
        queue.async { [weak self] in
            self?.enabled = enabled
            self?.format = format
            if !enabled {
                self?.closeAllHandles()
            }
        }
    }

    func start(tabID: UUID, sessionName: String, cols: Int = 80, rows: Int = 24) {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            self.close(tabID: tabID)
            let url = self.makeRecordingURL(tabID: tabID, sessionName: sessionName)
            var plainHandle: FileHandle?
            if self.format == .plain {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                plainHandle = try? FileHandle(forWritingTo: url)
                let header = "# Terminal Manager session recording\n# tab=\(tabID.uuidString)\n# session=\(sessionName)\n# started=\(ISO8601DateFormatter().string(from: Date()))\n\n"
                plainHandle?.write(Data(header.utf8))
            }
            self.states[tabID] = TabRecordingState(
                startDate: Date(),
                sessionName: sessionName,
                cols: max(1, cols),
                rows: max(1, rows),
                events: [],
                plainHandle: plainHandle,
                url: url
            )
        }
    }

    func updateTerminalSize(tabID: UUID, cols: Int, rows: Int) {
        queue.async { [weak self] in
            guard var state = self?.states[tabID] else { return }
            state.cols = max(1, cols)
            state.rows = max(1, rows)
            self?.states[tabID] = state
        }
    }

    func append(tabID: UUID, direction: String, data: ArraySlice<UInt8>) {
        queue.async { [weak self] in
            guard let self, self.enabled, var state = self.states[tabID] else { return }
            let chunk = AsciinemaCastWriter.encodeData(data)
            guard !chunk.isEmpty else { return }

            if self.format == .plain, let handle = state.plainHandle {
                let line = "[\(direction)] \(chunk)"
                handle.write(Data(line.utf8))
            }

            if self.format == .asciinema {
                let stream = direction == "INPUT" ? "i" : "o"
                let offset = Date().timeIntervalSince(state.startDate)
                state.events.append(AsciinemaCastEvent(offset: offset, stream: stream, data: chunk))
                self.states[tabID] = state
            }
        }
    }

    func stop(tabID: UUID) {
        queue.sync {
            close(tabID: tabID)
        }
    }

    func recordingURL(for tabID: UUID) -> URL? {
        queue.sync { states[tabID]?.url }
    }

    func recordingFormat(for tabID: UUID) -> SessionRecordingFormat? {
        queue.sync {
            guard states[tabID] != nil else { return nil }
            return format
        }
    }

    private func close(tabID: UUID) {
        guard var state = states[tabID] else { return }

        if format == .plain {
            try? state.plainHandle?.close()
        } else if format == .asciinema {
            let timestamp = Int(state.startDate.timeIntervalSince1970)
            try? AsciinemaCastWriter.write(
                to: state.url,
                width: state.cols,
                height: state.rows,
                timestamp: timestamp,
                title: state.sessionName,
                events: state.events
            )
        }

        states.removeValue(forKey: tabID)
    }

    private func closeAllHandles() {
        for tabID in states.keys {
            close(tabID: tabID)
        }
    }

    private func makeRecordingURL(tabID: UUID, sessionName: String) -> URL {
        let dir = FileLocations.logsDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = sessionName.replacingOccurrences(of: "/", with: "-")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let ext = format.fileExtension
        return dir.appendingPathComponent("\(safeName)-\(tabID.uuidString.prefix(8))-\(stamp).\(ext)")
    }
}
