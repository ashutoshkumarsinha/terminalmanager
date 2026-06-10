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
            logFileURL = logsDir.appendingPathComponent("terminalmanager-\(day).log")
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
            guard let logFileURL = self.currentLogFileURL() else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let source = (file as NSString).lastPathComponent
            let entry = "[\(timestamp)] [\(level.label)] [\(source):\(line) \(function)] \(message)\n"

            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: logFileURL, options: .atomic)
                }
            }

            #if DEBUG
            fputs(entry, stderr)
            #endif
        }
    }

    private func currentLogFileURL() -> URL? {
        if let logFileURL {
            let day = fileNameFormatter.string(from: Date())
            if logFileURL.lastPathComponent == "terminalmanager-\(day).log" {
                return logFileURL
            }
        }
        let logsDir = FileLocations.logsDirectory
        let day = fileNameFormatter.string(from: Date())
        let url = logsDir.appendingPathComponent("terminalmanager-\(day).log")
        logFileURL = url
        return url
    }
}
