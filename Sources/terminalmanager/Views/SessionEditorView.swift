import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var profile: SessionProfile
    @State private var portText: String
    @State private var initialDirectoryText: String
    @State private var sshKeyPathText: String
    @State private var startupScriptPathText: String

    let isNameAvailable: (String) -> Bool
    let onSave: (SessionProfile) -> Void

    init(
        profile: SessionProfile,
        isNameAvailable: @escaping (String) -> Bool = { _ in true },
        onSave: @escaping (SessionProfile) -> Void
    ) {
        _profile = State(initialValue: profile)
        _portText = State(initialValue: profile.port.map(String.init) ?? "")
        _initialDirectoryText = State(initialValue: profile.initialDirectory ?? "")
        _sshKeyPathText = State(initialValue: profile.sshKeyPath ?? "")
        _startupScriptPathText = State(initialValue: profile.startupScriptPath ?? "")
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
    }

    private var trimmedName: String {
        profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsDuplicate: Bool {
        !trimmedName.isEmpty && !isNameAvailable(trimmedName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $profile.name)
                    if nameIsDuplicate {
                        Text("A session with this name already exists in this folder.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Picker("Protocol", selection: $profile.protocolType) {
                        ForEach(ConnectionProtocol.allCases) { proto in
                            Text(proto.displayName).tag(proto)
                        }
                    }
                    .onChange(of: profile.protocolType) { _, newValue in
                        portText = newValue.defaultPort.map(String.init) ?? ""
                        if newValue != .ssh {
                            profile.sshAuthMethod = .agent
                        }
                    }
                }

                if profile.protocolType == .local {
                    Section("Local Shell") {
                        TextField("Initial Directory", text: $initialDirectoryText, prompt: Text("~/"))
                            .appHelp("Working directory when the shell starts, e.g. ~/projects")
                    }
                } else {
                    Section("Connection") {
                        TextField("Host, IP, or URI", text: $profile.host, prompt: Text("host.example.com or ssh2://user@host:22"))
                            .onChange(of: profile.host) { _, newValue in
                                applyConnectionURIIfPresent(in: newValue)
                            }
                        TextField("Port", text: $portText)
                        TextField("Username", text: $profile.username)
                    }

                    if profile.protocolType == .ssh {
                        Section("SSH Authentication") {
                            Picker("Method", selection: $profile.sshAuthMethod) {
                                ForEach(SSHAuthMethod.allCases) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }

                            if profile.sshAuthMethod == .password {
                                SecureField("Password", text: $profile.password)
                                Text("Stored in sessions.json. Prefer SSH keys when possible.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if profile.sshAuthMethod == .privateKey {
                                HStack {
                                    TextField("Private key path", text: $sshKeyPathText, prompt: Text("~/.ssh/id_ed25519"))
                                    Button("Browse…") { browseForSSHKey() }
                                        .appHelp("Choose an SSH private key file")
                                }
                            }
                        }
                    }
                }

                Section("Options") {
                    if profile.protocolType == .ssh {
                        Toggle("Enable SFTP", isOn: $profile.sftpEnabled)
                            .appHelp("Show an SFTP shortcut for this session in the sidebar")
                    }
                    TextField("Notes", text: $profile.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Startup Commands") {
                    TextEditor(text: $profile.initScript)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 90)
                    Text("Commands sent to the shell after the session opens. Lines starting with # are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Startup script file", text: $startupScriptPathText, prompt: Text("~/scripts/post-connect.sh"))
                        Button("Browse…") { browseForStartupScript() }
                            .appHelp("Choose a shell script to run after connecting")
                    }
                    Text("Optional script file whose commands are also run after connecting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appHelp("Discard changes and close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .appHelp("Save session settings")
                }
            }
        }
        .frame(width: 520, height: 640)
    }

    private var canSave: Bool {
        let nameOK = !trimmedName.isEmpty && !nameIsDuplicate
        if profile.protocolType == .local { return nameOK }
        let hostOK = !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if profile.protocolType == .ssh && profile.sshAuthMethod == .privateKey {
            return nameOK && hostOK && !sshKeyPathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return nameOK && hostOK
    }

    private func save() {
        var saved = profile
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.host = saved.host.trimmingCharacters(in: .whitespacesAndNewlines)

        if saved.protocolType == .local {
            let directory = initialDirectoryText.trimmingCharacters(in: .whitespacesAndNewlines)
            saved.initialDirectory = directory.isEmpty ? nil : directory
            saved.password = ""
            saved.sshKeyPath = nil
            saved.sshAuthMethod = .agent
        } else {
            let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPort.isEmpty {
                saved.port = saved.protocolType.defaultPort
            } else {
                saved.port = Int(trimmedPort) ?? saved.protocolType.defaultPort
            }

            if saved.protocolType == .ssh {
                let keyPath = sshKeyPathText.trimmingCharacters(in: .whitespacesAndNewlines)
                saved.sshKeyPath = keyPath.isEmpty ? nil : keyPath
                if saved.sshAuthMethod != .password {
                    saved.password = ""
                }
                if saved.sshAuthMethod != .privateKey {
                    saved.sshKeyPath = nil
                }
            } else {
                saved.sshAuthMethod = .agent
                saved.password = ""
                saved.sshKeyPath = nil
            }
        }

        let scriptPath = startupScriptPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.startupScriptPath = scriptPath.isEmpty ? nil : scriptPath

        if saved.sshAuthMethod == .password, !saved.password.isEmpty {
            _ = SSHAuthHelper.writeAskpassScript(password: saved.password, profileID: saved.id)
        }

        onSave(saved)
        dismiss()
    }

    private func browseForSSHKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select SSH Private Key"
        panel.message = "Choose a private key file (e.g. id_ed25519, id_rsa)."
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPathText = url.path
        }
    }

    private func browseForStartupScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Startup Script"
        panel.message = "Choose a shell script to run after the session opens."
        panel.allowedContentTypes = [.shellScript, .unixExecutable, .text]
        if panel.runModal() == .OK, let url = panel.url {
            startupScriptPathText = url.path
        }
    }

    private func applyConnectionURIIfPresent(in value: String) {
        guard ConnectionURIParser.looksLikeURI(value),
              let parsed = ConnectionURIParser.parse(value) else {
            return
        }
        profile.apply(parsedURI: parsed)
        portText = parsed.port.map(String.init) ?? (parsed.protocolType.defaultPort.map(String.init) ?? "")
    }
}

struct FolderNameEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    let fieldLabel: String
    let navigationTitleText: String
    let duplicateMessage: String
    let isNameAvailable: (String) -> Bool
    let onSave: (String) -> Void

    init(
        name: String,
        fieldLabel: String = "Folder Name",
        navigationTitle: String = "Rename Folder",
        duplicateMessage: String = "A folder with this name already exists.",
        isNameAvailable: @escaping (String) -> Bool,
        onSave: @escaping (String) -> Void
    ) {
        _name = State(initialValue: name)
        self.fieldLabel = fieldLabel
        self.navigationTitleText = navigationTitle
        self.duplicateMessage = duplicateMessage
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsDuplicate: Bool {
        !trimmedName.isEmpty && !isNameAvailable(trimmedName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(fieldLabel, text: $name)
                if nameIsDuplicate {
                    Text(duplicateMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appHelp("Discard changes and close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty || nameIsDuplicate)
                        .appHelp("Save folder name")
                }
            }
        }
        .frame(width: 360, height: 160)
    }

    private func save() {
        guard !nameIsDuplicate else { return }
        onSave(trimmedName)
        dismiss()
    }
}
