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
- **SFTP** — Launch SFTP in an embedded tab from saved SSH profiles
- **Portable config** — `config.toml` + `sessions.json`; `TERMINALMANAGER_CONFIG` env var
- **Single instance** — Optional one-instance-per-config-directory mode

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/USER_GUIDE.md) | Day-to-day usage; also available in-app via **Help → Terminal Manager Help** (⌘?) |
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
make run
```

This bootstraps `~/.terminalmanager/` (if needed), builds `Terminal Manager.app`, and opens it.

### Makefile

Run `make` or `make help` for all targets.

| Target | Purpose |
|--------|---------|
| `make build` | Build debug binary |
| `make build-release` | Build release binary |
| `make package` | Assemble `Terminal Manager.app` (debug) |
| `make package-release` | Assemble release app bundle |
| `make run` | Bootstrap config, package, and open app |
| `make bootstrap` | Create `~/.terminalmanager` from example config |
| `make dmg` | Build release app and create `dist/Terminal Manager-<version>.dmg` |
| `make test` | Run Swift tests |
| `make clean` | Remove `.build`, app bundle, and `dist/` |

Use `make run CONFIG=release` for a release build when developing.

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/run-app.sh [debug\|release]` | Bootstrap config, package app, open |
| `scripts/package-app.sh [debug\|release]` | Build and assemble `Terminal Manager.app` |
| `scripts/create-dmg.sh` | Release build + distributable DMG in `dist/` |
| `scripts/bootstrap-config.sh` | Create default config dir from `config.toml.example` |

Manual build:

```bash
make build
make package
open "Terminal Manager.app"
```

Release app bundle:

```bash
make package-release
```

### Distribution

Build a compressed DMG for sharing:

```bash
make dmg
```

Output: `dist/Terminal Manager-1.0.0.dmg` (version from `Resources/Info.plist`). The disk image contains the app and an Applications folder shortcut for drag-and-drop install.

Release builds strip debug symbols from the binary (~3 MB on disk vs ~9 MB for unstripped debug). Use `make package-release` or `make dmg`, not `make package`, for distribution.

The distributed build is not code-signed or notarized; recipients may need to allow the app in **System Settings → Privacy & Security** on first launch.

With [devbox](https://www.jetify.com/devbox):

```bash
devbox shell
devbox run run      # scripts/run-app.sh
devbox run package  # release .app bundle
# or: make dmg
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
| `logs/terminalmanager-*.log` | App events and errors |
| `logs/terminal-io-*.log` | Terminal commands and shell output |

Default: `~/.terminalmanager/`

Copy `config.toml.example` as a starting point. Full schema: [docs/SPEC.md](docs/SPEC.md).

## Terminal Backends

All sessions render in-window via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

## License

MIT — see [LICENSE](LICENSE).
