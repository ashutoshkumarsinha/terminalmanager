# Functional Specification: Terminal Manager

**Product:** Terminal Manager (`terminalmanager`)  
**Platform:** macOS 14+  
**Status:** Implemented (v1)

---

## 1. Product Overview

Terminal Manager is a native macOS application that consolidates multiple terminal sessions—SSH, Telnet, Rlogin, raw TCP, and local shells—into a single tabbed window with a session sidebar, split panes, session groups, and portable configuration.

### 1.1 Goals

- Reduce desktop clutter from many terminal windows
- Provide saved connection profiles organized in folders and groups
- Support repeatable multi-session workflows (groups with split layouts)
- Keep configuration human-editable and portable (`config.toml` + `sessions.json`)

### 1.2 Non-Goals (v1)

- Windows/Linux ports
- Built-in SFTP file browser (SFTP launches external Ghostty)
- Session recording / playback
- Multi-user or cloud sync

---

## 2. Functional Requirements

### 2.1 Session Management

| ID | Requirement | Status |
|----|-------------|--------|
| SM-01 | Create, edit, duplicate, delete session profiles | ✅ |
| SM-02 | Organize sessions in folders (nested tree) | ✅ |
| SM-03 | Drag-and-drop reorder and move sessions between folders | ✅ |
| SM-04 | Double-click session to open in new tab | ✅ |
| SM-05 | Export / import session tree as JSON | ✅ |
| SM-06 | Protocols: SSH, Telnet, Rlogin, Raw TCP, Local shell | ✅ |
| SM-07 | SSH auth: agent, password, private key | ✅ |
| SM-08 | Per-session init script after connect | ✅ |
| SM-09 | Optional SFTP launch via Ghostty | ✅ |

### 2.2 Session Groups

| ID | Requirement | Status |
|----|-------------|--------|
| SG-01 | Save open tabs (+ split layout) as a named group | ✅ |
| SG-02 | Groups hold references to existing sessions, not copies | ✅ |
| SG-03 | Double-click group opens all members with saved layout | ✅ |
| SG-04 | Drag session onto group to add reference | ✅ |
| SG-05 | Duplicate, rename, delete group via context menu | ✅ |
| SG-06 | Remove group member via context menu Delete | ✅ |
| SG-07 | Groups created only from open tabs (no empty “new group”) | ✅ |

### 2.3 Tabs & Workspace

| ID | Requirement | Status |
|----|-------------|--------|
| TW-01 | Multi-tab strip with reorder via drag-and-drop | ✅ |
| TW-02 | Rename tab (double-click or context menu) | ✅ |
| TW-03 | Detach tab to separate window; reattach | ✅ |
| TW-04 | Horizontal / vertical split on focused tab only | ✅ |
| TW-05 | Split preserves existing session; adds one new local pane | ✅ |
| TW-06 | Per-tab split layouts (switching tabs restores each layout) | ✅ |
| TW-07 | Close tab removes it from that tab’s split only | ✅ |

### 2.4 Command Broadcast

| ID | Requirement | Status |
|----|-------------|--------|
| BC-01 | Command toolbar sends input to selected or all tabs | ✅ |
| BC-02 | Toggle toolbar visibility (View menu + config) | ✅ |
| BC-03 | Focus command bar (⌘⇧L); shows bar if hidden | ✅ |

### 2.5 Application Behavior

| ID | Requirement | Status |
|----|-------------|--------|
| AB-01 | Single-instance mode (config.toml) | ✅ |
| AB-02 | Restore window position / zoom between launches | ✅ |
| AB-03 | Optional confirm-on-exit dialog | ✅ |
| AB-04 | Portable config via `TERMINALMANAGER_CONFIG` | ✅ |
| AB-05 | File logging with configurable level | ✅ |

### 2.6 Terminal Backends

| ID | Requirement | Status |
|----|-------------|--------|
| TB-01 | Embedded terminal (SwiftTerm) — default | ✅ |
| TB-02 | External Ghostty via AppleScript | ✅ |

---

## 3. User Interface

### 3.1 Main Window

- **Navigation split:** Session sidebar (optional) + detail workspace
- **Command toolbar:** Broadcast target picker + command field (optional)
- **Tab strip:** Tab chips with close, detach, rename, reorder
- **Workspace:** Single terminal or split panes for the selected tab’s layout

### 3.2 Sidebar

- Tree: folders, sessions, groups
- Single-click select; double-click open (session/group) or expand (folder)
- Context menus on items and empty sidebar area
- Toolbar actions when item selected (Connect, Open Group, Save as Group, Edit, Duplicate)

### 3.3 Menus

| Menu | Key actions |
|------|-------------|
| File | New Tab (⌘T), Close Tab (⌘W) |
| Session | Duplicate, next/prev tab, split H/V, focus command bar |
| View | Show sidebar, show command toolbar |

---

## 4. Configuration Files

### 4.1 Layout

| File | Purpose |
|------|---------|
| `config.toml` | Application settings |
| `sessions.json` | Session / folder / group tree |
| `window-state.json` | Saved window frame and zoom (auto) |
| `instance.lock` | Single-instance lock file (auto) |
| `logs/*.log` | Daily log files |

Default directory: `~/.terminalmanager/`

Override: environment variable `TERMINALMANAGER_CONFIG` (directory or path to `config.toml`).

### 4.2 `config.toml` Schema

```toml
[app]
version = 1
single_instance = false

[window]
start_maximized = false
restore_position = true

[terminal]
app_path = "/Applications/Ghostty.app"
backend = "embedded"   # embedded | ghostty

[ui]
show_sidebar = true
show_command_bar = true
broadcast_enabled = true
confirm_on_exit = false

[sessions]
file = "sessions.json"

[logging]
level = "info"         # debug | info | warning | error

[[shortcuts]]
id = "newTab"            # newTab | closeTab | nextTab | prevTab | duplicateSession | commandBar
key = "t"
modifiers = ["command"]
```

See `config.toml.example` for a complete template.

### 4.3 `sessions.json` Schema

Root object:

| Field | Type | Description |
|-------|------|-------------|
| `version` | int | Schema version (currently `1`) |
| `sessionTree` | array | Top-level tree items |

Tree items encode as tagged objects (Swift `Codable`):

**Folder**

```json
{
  "folder": {
    "id": "UUID",
    "name": "Production",
    "children": [ /* SessionTreeItem[] */ ]
  }
}
```

**Session**

```json
{
  "session": {
    "id": "UUID",
    "name": "WebServer",
    "host": "web01.example.com",
    "port": 22,
    "username": "admin",
    "protocolType": "ssh",
    "sshAuthMethod": "agent",
    "password": "",
    "sshKeyPath": null,
    "initScript": "cd /var/log",
    "startupScriptPath": null,
    "sftpEnabled": true,
    "notes": "",
    "initialDirectory": null
  }
}
```

**Group**

```json
{
  "group": {
    "id": "UUID",
    "name": "Web Stack",
    "members": [
      { "id": "UUID", "sessionID": "UUID" }
    ],
    "layout": {
      "id": "UUID",
      "orientation": "horizontal",
      "memberID": null,
      "children": [
        { "id": "UUID", "memberID": "UUID", "children": [], "ratio": 0.5 },
        { "id": "UUID", "memberID": "UUID", "children": [], "ratio": 0.5 }
      ],
      "ratio": 0.5
    }
  }
}
```

`layout` uses `memberID` on leaf nodes (maps to `SessionGroupMember.id`). Omitted or `null` when the group has no saved split.

---

## 5. Keyboard Shortcuts (Default)

| Action | Shortcut |
|--------|----------|
| New tab | ⌘T |
| Close tab | ⌘W |
| Next tab | ⌘⇧] |
| Previous tab | ⌘⇧[ |
| Duplicate tab | ⌘D |
| Focus command bar | ⌘⇧L |

Shortcuts are configurable in `config.toml` under `[[shortcuts]]`.

---

## 6. Build & Deploy

### Makefile

| Target | Purpose |
|--------|---------|
| `make build` | Debug Swift build |
| `make build-release` | Release Swift build |
| `make package` | Assemble `Terminal Manager.app` (debug) |
| `make package-release` | Assemble release app bundle |
| `make run` | Bootstrap config, package, open (`CONFIG=release` optional) |
| `make bootstrap` | Seed config directory from `config.toml.example` |
| `make dmg` | Release build + `dist/Terminal Manager-<version>.dmg` |
| `make test` | Run Swift tests |
| `make clean` | Remove `.build`, app bundle, and `dist/` |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-config.sh` | Create `~/.terminalmanager` from example if missing |
| `scripts/package-app.sh [debug\|release]` | Build binary and assemble `Terminal Manager.app` |
| `scripts/create-dmg.sh` | Release build, stage app + Applications link, write DMG to `dist/` |
| `scripts/run-app.sh [debug\|release]` | Bootstrap config, package, and open app |

### Distribution

- DMG filename version comes from `CFBundleShortVersionString` in `Resources/Info.plist`.
- DMG contents: `Terminal Manager.app`, symlink to `/Applications`.
- Builds are unsigned; Gatekeeper may block until the user allows the app manually.
- For public distribution, sign with an Apple Developer ID and notarize via `notarytool`.

---

## 7. Related Documents

- [High-Level Design (HLD)](HLD.md)
- [User Guide](USER_GUIDE.md)
- [README](../README.md)
