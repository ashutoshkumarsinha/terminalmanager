import Foundation

enum TerminalEnvironment {
    static let termName = "xterm-256color"
    static let programName = "TerminalManager"

    /// Full process environment for a PTY session, with terminal-specific overrides.
    static func processEnvironment(overrides: [String]? = nil) -> [String] {
        var env = ProcessInfo.processInfo.environment

        env["TERM"] = termName
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = programName
        env["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        if env["LANG"] == nil && env["LC_ALL"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }
        if env["SHELL"] == nil {
            env["SHELL"] = ConnectionLauncher.userLoginShellPath()
        }

        applyOverrides(overrides, to: &env)

        return env.map { key, value in
            "\(key)=\(value)"
        }
    }

    private static func applyOverrides(_ overrides: [String]?, to env: inout [String: String]) {
        guard let overrides else { return }
        for override in overrides {
            let parts = override.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            env[String(parts[0])] = String(parts[1])
        }
    }
}
