# Terminal Manager — User Guide

Terminal Manager runs SSH, Telnet, Rlogin, raw TCP, and local shell sessions in a single window. Saved connections live in the sidebar; you can split panes, tear off tabs, broadcast commands, and reopen multi-tab layouts with one double-click.

All sessions render **inside the app** using an embedded terminal (SwiftTerm). There is no external terminal backend.

---

## 1. Getting Started

### Install from DMG

If you received `Terminal Manager-<version>.dmg`:

1. Open the disk image.
2. Drag **Terminal Manager** into **Applications**.
3. Eject the disk image.
4. Launch from Applications. On first open, macOS may warn that the app is from an unidentified developer — use **System Settings → Privacy & Security → Open Anyway** if needed.

The first run creates `~/.terminalmanager/` with default `config.toml` and an empty `sessions.json`.

### Build from source

```bash
cd terminalmanager
make run
```

Equivalent: `bash scripts/run-app.sh`. For release builds and DMG packaging, run `make help`.

### Open this guide

- **Help → Terminal Manager Help** (⌘?)
- Opens this document in a window inside the app

### Main window layout

```
┌─────────────────────────────────────────────────────────┐
│ [Command bar — optional]                                │
├─────────────────────────────────────────────────────────┤
│ Tab │ Tab │ Tab │ +                                      │
├──────────┬──────────────────────────────────────────────┤
│ Sessions │  Terminal workspace (single or split panes)  │
│ sidebar  │                                              │
│          │                                              │
└──────────┴──────────────────────────────────────────────┘
```

| Area | Purpose |
|------|---------|
| **Sidebar** | Saved sessions, folders, and groups |
| **Tab strip** | Open sessions; click to switch |
| **Workspace** | Embedded terminal for the selected tab (or its split panes) |
| **Command bar** | Send a command to the selected tab or all tabs |

---

## 2. Sessions

### Connect to a saved session

1. Single-click a session in the sidebar to select it
2. Click **Connect** in the sidebar toolbar, or **double-click** the session

### Create a session

| Method | Steps |
|--------|-------|
| Sidebar | Right-click → **New Session** |
| Edit menu | **Edit → New Session…** |
| Inside a folder | Right-click the folder → **New Session** — the folder expands so the new session is visible |

Fill in name, host, protocol, credentials, and optional init script, then click **Save**.

### Connection URIs

Paste a URI into the **Host** field in the session editor (or open via CLI / URL handler):

| Scheme | Example |
|--------|---------|
| `ssh://` | `ssh://user@host:22` |
| `ssh2://` | Treated as SSH |
| `telnet://` | `telnet://host:23` |
| `rlogin://` | `rlogin://user@host` |

The editor parses the URI and fills protocol, host, port, and username.

### Organize with folders

| Action | How |
|--------|-----|
| New folder | Right-click sidebar → **New Folder**, or **Edit → New Folder** |
| Rename folder | Select folder → **Edit → Rename Folder…** |
| Delete folder | Select folder → **Edit → Delete Folder** |
| Move items | Drag sessions or folders onto folders, or drag to reorder |

### Duplicate or delete

- Right-click a session → **Duplicate** or **Delete**
- **Delete** removes the profile from the sidebar; open tabs using it will close

---

## 3. Tabs

| Action | How |
|--------|-----|
| New tab | ⌘T or **+** on tab strip |
| Close tab | ⌘W or **×** on tab chip |
| Switch tab | Click chip, or ⌘⇧] / ⌘⇧[ |
| Duplicate tab | ⌘D or **Session → Duplicate Tab** |
| Rename tab | Double-click title, or right-click → **Rename…** |
| Reorder tabs | Drag tab chips |
| Detach tab | Right-click → **Detach Window** |
| Reattach | **Reattach** button in detached window |

Background tabs stay in memory but only the **visible** tab (and its split panes) mount a terminal view, which keeps the app responsive when many tabs are open.

---

## 4. Split Panes

Split applies only to the **currently selected tab** and does not add entries to the tab strip.

| Action | How |
|--------|-----|
| Split horizontal | Toolbar **Split Horizontal** or **Session → Split Horizontally** |
| Split vertical | Toolbar **Split Vertical** or **Session → Split Vertically** |

**What happens:**

- Your **current session stays running** in one pane
- **One new local shell** opens in the other pane
- Switch to another tab → that tab shows full-screen (or its own split if you split it earlier)
- Switch back → your split layout returns

Close a pane with **⌘W** while it is focused; when only one pane remains, the split ends.

---

## 5. Session Groups

Groups save a set of open tabs and their split layout so you can reopen them together.

### Create a group from open tabs

1. Open the sessions you want in tabs (arrange splits if needed)
2. Right-click the sidebar → **Save Tabs as Group…**, or **Edit → Create Group from Open Tabs…**
3. Enter a group name → **Save**

Groups are created from open tabs only (there is no empty group).

### Open a group

- **Double-click** the group in the sidebar, or select it and click **Open Group**

All referenced sessions open as tabs with the saved split layout restored.

### Manage a group

Right-click the group:

| Action | Description |
|--------|-------------|
| Open Group | Open all members with layout |
| Rename… | Change group name |
| Duplicate Group | Copy group with a new name |
| Delete | Remove group (sessions and open tabs unaffected) |

### Add or remove members

- **Add** — drag a session from the sidebar onto a group
- **Remove** — expand the group, right-click a member → **Delete** (removes reference only; the session profile remains)

---

## 6. Command Bar (Broadcast)

Send the same command to one or all embedded tabs.

1. Type in the **Send command to shell…** field
2. Choose **Selected Tab** or **All Tabs**
3. Press **Send** or **⌘Return**

| Input | Behavior |
|-------|----------|
| **Return** | New line in the command field (multiline commands) |
| **⌘Return** | Send to the chosen target(s) |
| **⌘⇧L** | Focus command bar (shows bar if hidden) |

Each non-empty line is sent as a separate command followed by Enter.

Disable the feature with `show_command_bar = false` or `broadcast_enabled = false` in `config.toml`.

---

## 7. SFTP

For SSH sessions, enable **Enable SFTP** in the session editor. An arrow icon appears in the sidebar.

| Action | Result |
|--------|--------|
| Click arrow icon | Opens **Session Name (SFTP)** in a new embedded tab running `sftp` |
| Right-click → **SFTP** | Same |

SFTP uses the same SSH credentials (agent, password, or private key) as the parent session.

---

## 8. Menus

### File

| Item | Action |
|------|--------|
| New Tab | Open a local shell tab (⌘T) |
| Close Tab | Close selected tab (⌘W) |

### Edit

| Item | Action |
|------|--------|
| New Folder | Create a folder in the sidebar |
| Rename Folder… | Rename selected folder |
| Delete Folder | Delete selected folder |
| New Session… | Open session editor for a new profile |
| Create Group from Open Tabs… | Save current tabs as a group |

### Session

| Item | Action |
|------|--------|
| Duplicate Tab | ⌘D |
| Next / Previous Tab | ⌘⇧] / ⌘⇧[ |
| Split Horizontally / Vertically | Split focused tab |
| Focus Command Bar | ⌘⇧L |

### View

| Item | Action |
|------|--------|
| Show Session Sidebar | Toggle sidebar (saved to `config.toml`) |
| Show Command Bar | Toggle broadcast bar |
| Show Tooltips | Toggle hover help on buttons and controls |

### Help

| Item | Action |
|------|--------|
| Terminal Manager Help | Open this guide (⌘?) |

---

## 9. Settings

Open **Terminal Manager → Settings** (⌘,):

| Setting | Purpose |
|---------|---------|
| Show Session Sidebar | Default sidebar visibility |
| Sessions JSON file | Path to `sessions.json` (relative or absolute) |
| Log level | App log verbosity (`debug`, `info`, `warning`, `error`) |
| Export / Import Sessions JSON | Backup or restore the session tree |

---

## 10. Configuration Files

Default location: `~/.terminalmanager/`

| File | Purpose |
|------|---------|
| `config.toml` | App preferences (edit directly, via Settings, or View menu) |
| `sessions.json` | Sessions, folders, groups |
| `window-state.json` | Window size/position (automatic) |
| `logs/terminalmanager-YYYY-MM-DD.log` | App events (tabs opened, errors, config) |
| `logs/terminal-io-YYYY-MM-DD.log` | Terminal input and shell output per session |

### Portable setup

```bash
export TERMINALMANAGER_CONFIG=/path/to/my-config
make run
```

### Useful `config.toml` options

```toml
[app]
single_instance = true      # one app instance per config dir

[window]
start_maximized = true
restore_position = true

[ui]
show_sidebar = true
show_command_bar = true
show_tooltips = true
broadcast_enabled = true
confirm_on_exit = true      # ask before quitting

[logging]
level = "info"              # debug | info | warning | error
```

See `config.toml.example` in the project for the full list.

---

## 11. Keyboard Shortcuts

| Action | Default |
|--------|---------|
| New tab | ⌘T |
| Close tab | ⌘W |
| Next tab | ⌘⇧] |
| Previous tab | ⌘⇧[ |
| Duplicate tab | ⌘D |
| Focus command bar | ⌘⇧L |
| Open User Guide | ⌘? |

Customize tab shortcuts via `[[shortcuts]]` entries in `config.toml`.

---

## 12. Protocols & Auth

| Protocol | Notes |
|----------|-------|
| SSH | System `ssh`; agent, password, or key file |
| Telnet | System `telnet` |
| Rlogin | System `rlogin` if available |
| Raw TCP | `nc` to host:port |
| Local | Login shell in embedded PTY |

**Init script** — commands sent after connect (e.g. `cd /var/log`). Use for post-login setup.

**Startup script path** — optional file whose lines are appended to the init script.

**Password auth** — Terminal Manager writes a temporary askpass helper under `~/.terminalmanager/` when you save a password-based SSH session.

---

## 13. Troubleshooting

| Problem | Suggestion |
|---------|------------|
| App not in Dock | Use `make run` or `bash scripts/run-app.sh`, not bare `swift run` |
| “App is damaged” or won’t open | Unsigned DMG — allow in **Privacy & Security**, or build from source |
| Second launch does nothing | `single_instance = true` — existing window is focused |
| SSH password auth fails | Re-save session; check `~/.terminalmanager/askpass-*.sh` exists |
| SFTP tab fails to connect | Confirm SSH session settings; test SSH in a normal tab first |
| Split shows wrong layout | Split is per-tab; select the tab you split before expecting panes |
| Group member “Missing session” | Referenced session was deleted; remove member from group |
| Help guide empty | Rebuild app bundle so `USER_GUIDE.md` is copied into the bundle |

### Logs

| File | Contents |
|------|----------|
| `terminalmanager-*.log` | App lifecycle, tab open/close, config errors |
| `terminal-io-*.log` | `[INPUT]` keystrokes/commands and `[OUTPUT]` shell text (ANSI stripped) |

Both are under `~/.terminalmanager/logs/`. Set `[logging] level = "debug"` for more app detail; terminal I/O is always logged.

---

## 14. For Developers

Source and build docs live in the project repository:

- `README.md` — build, Makefile, DMG distribution
- `docs/SPEC.md` — requirements and config schema
- `docs/HLD.md` — architecture
