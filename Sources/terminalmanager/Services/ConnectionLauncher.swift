import Foundation
import Darwin

struct ConnectionCommand: Hashable {
    let executable: String
    let arguments: [String]
    let displayCommand: String
    let execName: String?
    let workingDirectory: String?
    let environment: [String]?
    let startupCommands: [String]
    let startupDelay: TimeInterval

    init(
        executable: String,
        arguments: [String],
        displayCommand: String,
        execName: String? = nil,
        workingDirectory: String? = nil,
        environment: [String]? = nil,
        startupCommands: [String] = [],
        startupDelay: TimeInterval = 1.0
    ) {
        self.executable = executable
        self.arguments = arguments
        self.displayCommand = displayCommand
        self.execName = execName
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.startupCommands = startupCommands
        self.startupDelay = startupDelay
    }
}

enum ConnectionLauncher {
    static func command(for profile: SessionProfile) -> ConnectionCommand {
        switch profile.protocolType {
        case .local:
            return localShellCommand(profile: profile)

        case .ssh:
            return sshCommand(for: profile)

        case .telnet:
            let port = profile.port ?? 23
            let host = profile.host
            let startup = resolvedStartupCommands(for: profile)
            return ConnectionCommand(
                executable: "/usr/bin/telnet",
                arguments: [host, String(port)],
                displayCommand: "telnet \(host) \(port)",
                startupCommands: startup.commands,
                startupDelay: startup.delay
            )

        case .rlogin:
            var args: [String] = []
            if let port = profile.port, port != 513 {
                args += ["-p", String(port)]
            }
            let target = profile.username.isEmpty ? profile.host : "\(profile.username)@\(profile.host)"
            args.append(target)
            let startup = resolvedStartupCommands(for: profile)
            return ConnectionCommand(
                executable: "/usr/bin/rlogin",
                arguments: args,
                displayCommand: (["rlogin"] + args).joined(separator: " "),
                startupCommands: startup.commands,
                startupDelay: startup.delay
            )

        case .raw:
            let port = profile.port ?? 23
            let startup = resolvedStartupCommands(for: profile)
            return ConnectionCommand(
                executable: "/usr/bin/nc",
                arguments: [profile.host, String(port)],
                displayCommand: "nc \(profile.host) \(port)",
                startupCommands: startup.commands,
                startupDelay: startup.delay
            )
        }
    }

    static func sftpCommand(for profile: SessionProfile) -> ConnectionCommand? {
        guard profile.protocolType == .ssh else { return nil }
        var args: [String] = ["-o", "StrictHostKeyChecking=accept-new"]
        if let port = profile.port, port != 22 {
            args += ["-P", String(port)]
        }
        if profile.sshAuthMethod == .privateKey,
           let keyPath = SSHAuthHelper.expandedKeyPath(profile.sshKeyPath) {
            args += ["-i", keyPath, "-o", "IdentitiesOnly=yes"]
        }
        let target = profile.username.isEmpty ? profile.host : "\(profile.username)@\(profile.host)"
        args.append(target)
        var environment: [String]?
        if profile.sshAuthMethod == .password, !profile.password.isEmpty {
            environment = SSHAuthHelper.askpassEnvironment(password: profile.password, profileID: profile.id)
        }
        return ConnectionCommand(
            executable: "/usr/bin/sftp",
            arguments: args,
            displayCommand: (["sftp"] + args).joined(separator: " "),
            environment: environment
        )
    }

    static func initScriptLines(from script: String) -> [String] {
        script
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func resolvedStartupCommands(for profile: SessionProfile) -> (commands: [String], delay: TimeInterval) {
        var lines = initScriptLines(from: profile.initScript)
        if let scriptPath = profile.startupScriptPath,
           let fileLines = loadScriptLines(from: scriptPath) {
            lines.append(contentsOf: fileLines)
        }
        let delay: TimeInterval = profile.protocolType == .local ? 1.5 : 2.0
        return (lines, lines.isEmpty ? 1.0 : delay)
    }

    static func initialInput(for profile: SessionProfile) -> String? {
        let lines = resolvedStartupCommands(for: profile).commands
        guard !lines.isEmpty else { return nil }
        return lines.map { $0 + "\n" }.joined()
    }

    private static func sshCommand(for profile: SessionProfile) -> ConnectionCommand {
        var args = sshArguments(for: profile, includeBatchMode: true)
        let target = profile.username.isEmpty ? profile.host : "\(profile.username)@\(profile.host)"
        args.append(target)
        let startup = resolvedStartupCommands(for: profile)
        var environment: [String]?
        if profile.sshAuthMethod == .password, !profile.password.isEmpty {
            environment = SSHAuthHelper.askpassEnvironment(password: profile.password, profileID: profile.id)
        }
        return ConnectionCommand(
            executable: "/usr/bin/ssh",
            arguments: args,
            displayCommand: (["ssh"] + args).joined(separator: " "),
            environment: environment,
            startupCommands: startup.commands,
            startupDelay: startup.delay
        )
    }

    private static func sshArguments(for profile: SessionProfile, includeBatchMode: Bool) -> [String] {
        var args = ["-o", "StrictHostKeyChecking=accept-new"]
        if let port = profile.port, port != 22 {
            args += ["-p", String(port)]
        }
        switch profile.sshAuthMethod {
        case .agent:
            break
        case .password:
            if includeBatchMode {
                args += ["-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no"]
            }
        case .privateKey:
            if let keyPath = SSHAuthHelper.expandedKeyPath(profile.sshKeyPath) {
                args += ["-i", keyPath, "-o", "IdentitiesOnly=yes"]
            }
        }
        return args
    }

    private static func loadScriptLines(from path: String) -> [String]? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return nil
        }
        return initScriptLines(from: content)
    }

    static func userLoginShellPath() -> String {
        userLoginShell()
    }

    private static func localShellCommand(profile: SessionProfile) -> ConnectionCommand {
        let shell = userLoginShell()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let desiredDirectory = resolvedDirectory(profile.initialDirectory, fallback: home)
        let startup = resolvedStartupCommands(for: profile)
        var lines = startup.commands
        if desiredDirectory != home {
            lines.insert("cd \(shellQuote(desiredDirectory))", at: 0)
        }

        // argv[0] of "-zsh" / "-bash" starts a login shell so ~/.zprofile and ~/.zshrc load (oh-my-posh, etc.)
        let execName = "-\(shellName)"
        var args: [String] = []
        if shellName == "zsh" {
            args = ["-il"]
        } else if shellName == "bash" {
            args = ["-il"]
        }

        return ConnectionCommand(
            executable: shell,
            arguments: args,
            displayCommand: "\(shellName) (login)",
            execName: execName,
            workingDirectory: home,
            environment: nil,
            startupCommands: lines,
            startupDelay: startup.delay
        )
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func resolvedDirectory(_ path: String?, fallback: String) -> String {
        guard let path, !path.isEmpty else { return fallback }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return expanded
        }
        return fallback
    }

    private static func userLoginShell() -> String {
        if let passwd = getpwuid(getuid()) {
            let shell = String(cString: passwd.pointee.pw_shell)
            if !shell.isEmpty {
                return shell
            }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

}
