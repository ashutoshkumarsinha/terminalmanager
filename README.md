# Terminal Manager

Lightweight macOS tabbed terminal session manager written in Swift. Terminal Manager wraps SSH, Telnet, Rlogin, raw TCP, and local shell sessions in a single window with a session sidebar, per-tab split panes, session groups, and portable configuration (`config.toml` + `sessions.json`).

## Features

- **Multi-tab interface** — Many sessions in one window with keyboard shortcuts
- **Per-tab split panes** — Horizontal/vertical split on the focused tab; existing session preserved + one new local pane
- **Session groups** — Save open tabs and split layouts; reopen with double-click
- **Session directory** — Sidebar with folders, sessions, drag-and-drop reorder
- **Detached windows** — Tear off a tab and reattach later
- **Command broadcast** — Send a command to selected or all embedded tabs
- **Protocol support** — SSH, Telnet, Rlogin, Raw TCP, local shell
- **SFTP** — Launch SFTP in Ghostty from saved SSH profiles
- **Portable config** — `config.toml` + `sessions.json`; `TERMINALMANAGER_CONFIG` env var
- **Single instance** — Optional one-instance-per-config-directory mode

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/USER_GUIDE.md) | Day-to-day usage: sessions, tabs, splits, groups |
| [Functional Spec](docs/SPEC.md) | Requirements, config schemas, shortcuts |
| [High-Level Design](docs/HLD.md) | Architecture, data models, component diagram |

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+
- System `ssh`, `telnet`, `nc`, and optionally `rlogin`

## Build & Run

`swift run` builds a bare executable that may not appear in the Dock. Use the app bundle:

```bash
cd terminalmanager
bash scripts/run-app.sh
```

This bootstraps `~/.terminalmanager/` (if needed), builds `Terminal Manager.app`, and opens it.

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/run-app.sh [debug\|release]` | Bootstrap config, package app, open |
| `scripts/package-app.sh [debug\|release]` | Build and assemble `Terminal Manager.app` |
| `scripts/bootstrap-config.sh` | Create default config dir from `config.toml.example` |

Manual build:

```bash
swift build
bash scripts/package-app.sh debug
open "Terminal Manager.app"
```

Release:

```bash
bash scripts/package-app.sh release
```

With [devbox](https://www.jetify.com/devbox):

```bash
devbox shell
devbox run run      # scripts/run-app.sh
devbox run package  # release .app bundle
```

Portable config:

```bash
export TERMINALMANAGER_CONFIG=/path/to/config-dir
bash scripts/run-app.sh
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New tab | ⌘T |
| Close tab | ⌘W |
| Next tab | ⌘⇧] |
| Previous tab | ⌘⇧[ |
| Duplicate tab | ⌘D |
| Focus command bar | ⌘⇧L |

## Configuration

| File | Purpose |
|------|---------|
| `config.toml` | App settings, UI, window, shortcuts |
| `sessions.json` | Session profiles, folders, groups |
| `window-state.json` | Saved window frame (automatic) |

Default: `~/.terminalmanager/`

Copy `config.toml.example` as a starting point. Full schema: [docs/SPEC.md](docs/SPEC.md).

## Terminal Backends

| Mode | Behavior |
|------|----------|
| **Embedded** (default) | In-window rendering via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) |
| **Ghostty** | External windows via AppleScript (Automation permission required) |

Configure in Settings or `config.toml` → `[terminal]`.

## License

MIT — see [LICENSE](LICENSE).
