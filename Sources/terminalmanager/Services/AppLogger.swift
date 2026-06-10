import Foundation

enum LogLevel: String, Codable, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    var label: String {
        rawValue.uppercased()
    }

    private var priority: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.terminalmanager.logger", qos: .utility)
    private var minimumLevel: LogLevel = .info
    private var logFileURL: URL?
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {}

    func configure(level: LogLevel) {
        queue.sync {
            minimumLevel = level
            let logsDir = FileLocations.logsDirectory
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let day = fileNameFormatter.string(from: Date())
            let url = logsDir.appendingPathComponent("terminalmanager-\(day).log")
            if logFileURL != url {
                try? fileHandle?.close()
                fileHandle = nil
                logFileURL = url
            }
        }
    }

    func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    private func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
        queue.async {
            guard level >= self.minimumLevel else { return }
            guard let handle = self.openLogHandle() else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let source = (file as NSString).lastPathComponent
            let entry = "[\(timestamp)] [\(level.label)] [\(source):\(line) \(function)] \(message)\n"

            if let data = entry.data(using: .utf8) {
                handle.seekToEndOfFile()
                handle.write(data)
            }

            #if DEBUG
            fputs(entry, stderr)
            #endif
        }
    }

    private func openLogHandle() -> FileHandle? {
        if let fileHandle, let logFileURL {
            let day = fileNameFormatter.string(from: Date())
            if logFileURL.lastPathComponent == "terminalmanager-\(day).log" {
                return fileHandle
            }
        }

        let logsDir = FileLocations.logsDirectory
        let day = fileNameFormatter.string(from: Date())
        let url = logsDir.appendingPathComponent("terminalmanager-\(day).log")
        logFileURL = url

        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            try fileHandle?.close()
            let handle = try FileHandle(forWritingTo: url)
            fileHandle = handle
            return handle
        } catch {
            fileHandle = nil
            return nil
        }
    }
}
