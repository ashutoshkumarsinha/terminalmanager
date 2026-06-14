import AppKit
import SwiftUI

struct SFTPBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let profile: SessionProfile
    @State private var path: String = "."
    @State private var bookmarks: [String] = []
    @State private var entries: [SFTPEntry] = []
    @State private var isLoading = false
    @State private var isTransferring = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Could Not List Directory",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "Empty Directory",
                        systemImage: "folder",
                        description: Text("No files found at \(path)")
                    )
                } else {
                    List(entries) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundStyle(entry.isDirectory ? .secondary : .primary)
                            Text(entry.name)
                            Spacer()
                            if !entry.isDirectory {
                                Button("Download") {
                                    downloadEntry(entry)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard entry.isDirectory else { return }
                            path = joinedPath(path, entry.name)
                            loadDirectory()
                        }
                    }
                }
            }
            .navigationTitle("\(profile.name) — SFTP")
            .safeAreaInset(edge: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem {
                    Menu {
                        if bookmarks.isEmpty {
                            Text("No bookmarks")
                        } else {
                            ForEach(bookmarks, id: \.self) { bookmark in
                                Button(bookmark) {
                                    path = bookmark
                                    loadDirectory()
                                }
                            }
                            Divider()
                        }
                        Button("Bookmark Current Folder") {
                            saveBookmark()
                        }
                    } label: {
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                }
                ToolbarItem {
                    Button {
                        uploadFile()
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isTransferring)
                }
                ToolbarItem {
                    Button {
                        navigateUp()
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .disabled(path == "." || path == "/")
                }
                ToolbarItem {
                    Button {
                        loadDirectory()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            bookmarks = profile.sftpBookmarks
            loadDirectory()
        }
    }

    private func saveBookmark() {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !bookmarks.contains(trimmed) else { return }
        bookmarks.append(trimmed)
        var updated = profile
        updated.sftpBookmarks = bookmarks
        _ = appState.updateSessionProfile(updated)
        statusMessage = "Bookmarked \(trimmed)"
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let localURL = panel.url else { return }
        let remotePath = joinedPath(path, localURL.lastPathComponent)
        isTransferring = true
        statusMessage = "Uploading \(localURL.lastPathComponent)…"
        Task {
            do {
                try await SFTPTransferService.upload(localURL: localURL, to: remotePath, profile: profile)
                statusMessage = "Uploaded \(localURL.lastPathComponent)"
                loadDirectory()
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isTransferring = false
        }
    }

    private func downloadEntry(_ entry: SFTPEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let localURL = panel.url else { return }
        let remotePath = joinedPath(path, entry.name)
        isTransferring = true
        statusMessage = "Downloading \(entry.name)…"
        Task {
            do {
                try await SFTPTransferService.download(remotePath: remotePath, to: localURL, profile: profile)
                statusMessage = "Downloaded \(entry.name)"
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isTransferring = false
        }
    }

    private func navigateUp() {
        if path == "." || path == "/" { return }
        if path.contains("/") {
            path = String(path.split(separator: "/").dropLast().joined(separator: "/"))
            if path.isEmpty { path = "/" }
        } else {
            path = "."
        }
        loadDirectory()
    }

    private func joinedPath(_ base: String, _ name: String) -> String {
        if base == "." { return name }
        if base.hasSuffix("/") { return base + name }
        return base + "/" + name
    }

    private func loadDirectory() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let listed = try await SFTPDirectoryLister.list(profile: profile, path: path)
                entries = listed
            } catch {
                entries = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct SFTPEntry: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool

    var id: String { name + (isDirectory ? "/" : "") }
}

enum SFTPDirectoryLister {
    enum ListError: Error, LocalizedError {
        case unavailable
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "SFTP is only available for SSH sessions"
            case .commandFailed(let message): message
            }
        }
    }

    static func list(profile: SessionProfile, path: String) async throws -> [SFTPEntry] {
        guard let command = ConnectionLauncher.sftpCommand(for: profile) else {
            throw ListError.unavailable
        }

        let batch = "ls -la \(shellQuote(path))\n"
        let batchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sftp-batch-\(UUID().uuidString).txt")
        try batch.write(to: batchURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: batchURL) }

        var args = command.arguments
        args.insert(contentsOf: ["-b", batchURL.path], at: 0)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executable)
                process.arguments = args
                let envStrings = TerminalEnvironment.processEnvironment(overrides: command.environment)
                var env = ProcessInfo.processInfo.environment
                for entry in envStrings {
                    let parts = entry.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    env[String(parts[0])] = String(parts[1])
                }
                process.environment = env

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ListError.commandFailed(error.localizedDescription))
                    return
                }

                process.waitUntilExit()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ListError.commandFailed(
                        message?.isEmpty == false ? message! : "SFTP listing failed"
                    ))
                    return
                }

                let output = String(data: outData, encoding: .utf8) ?? ""
                continuation.resume(returning: parseListing(output))
            }
        }
    }

    private static func parseListing(_ output: String) -> [SFTPEntry] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> SFTPEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                if trimmed.hasPrefix("sftp>") || trimmed.hasPrefix("Connected to") { return nil }
                if trimmed.hasPrefix("total ") { return nil }
                let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 9 else { return nil }
                let name = parts.dropFirst(8).joined(separator: " ")
                guard name != "." && name != ".." else { return nil }
                let isDirectory = parts[0].hasPrefix("d")
                return SFTPEntry(name: name, isDirectory: isDirectory)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
