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
│ [Quick Connect — optional]                              │
│ [Command bar — optional]                                │
├─────────────────────────────────────────────────────────┤
│ ● Tab │ Tab │ Tab │ +                                   │
├──────────┬──────────────────────────────────────────────┤
│ Search   │  Terminal workspace (single or split panes)  │
│ Sessions │  [Find bar when ⌘F]                          │
│ sidebar  │                                              │
└──────────┴──────────────────────────────────────────────┘
```

| Area | Purpose |
|------|---------|
| **Quick Connect** | Connect immediately via URI or `user@host` without saving a profile |
| **Sidebar** | Saved sessions, folders, and groups; search filters the tree |
| **Tab strip** | Open sessions; colored dot shows idle / running / exited |
| **Workspace** | Embedded terminal for the selected tab (or its split panes) |
| **Command bar** | Send a command to the selected tab or all tabs; history and presets |

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

**SSH extras (optional):**

| Field | Purpose |
|-------|---------|
| **ProxyJump (-J)** | Bastion host for `ssh -J` |
| **SSH extra options** | Additional flags (e.g. `-o IdentityFile=~/.ssh/work`) |
| **Tag color** | Sidebar color dot (`#FF5500`, `green`, etc.) |

**Password auth** — passwords are stored in the **macOS Keychain**, not in `sessions.json`. Existing v1 passwords migrate automatically on first load.

### Quick Connect

Use the bar at the top of the main window to connect without saving a profile:

| Input | Example |
|-------|---------|
| URI | `ssh://admin@web01.example.com:22` |
| Shorthand | `admin@web01` (defaults to SSH port 22) |

Press **Connect** or **Return** to open a new tab.

### Search the sidebar

Type in the **Search sessions…** field above the tree. Matches name, host, protocol, and notes. Clear the field to show the full tree again.

### Test connection

Right-click a session → **Test Connection**. Runs a short non-interactive probe (SSH batch mode, etc.) and shows success or failure in an alert.

### Duplicate to folder

Right-click a session → **Duplicate to Folder** to copy the profile into another folder without leaving the original in place.

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
| Tab status | Colored dot: gray idle, green running, red exited |
| Detach tab | Right-click → **Detach Window** |
| Reattach | **Reattach** button in detached window |
| Find in scrollback | ⌘F — search bar above workspace |
| Reconnect | When a session exits unexpectedly, choose **Reconnect** in the alert (if enabled in Settings) |

Detached windows remember their size and position per tab.

---

## 4. Split Panes

Split applies only to the **currently selected tab** and does not add entries to the tab strip.

| Action | How |
|--------|-----|
| Split horizontal | Toolbar **Split Horizontal** or **Session → Split Horizontally** |
| Split vertical | Toolbar **Split Vertical** or **Session → Split Vertically** |

**What happens:**

- Your **current session stays running** in one pane
- **A second connection** to the same profile opens in the other pane (same protocol and credentials)
- Switch to another tab → that tab shows full-screen (or its own split if you split it earlier)
- Switch back → your split layout returns

Background tabs stay in memory but only the **visible** tab (and its split panes) mount a terminal view, which keeps the app responsive when many tabs are open.

Close a pane with **⌘W** while it is focused; when only one pane remains, the split ends.

---

## 5. Session Groups

Groups save a set of open tabs and their split layout so you can reopen them together.

### Create a group from open tabs

1. Open the sessions you want in tabs (arrange splits if needed)
2. Right-click the sidebar → **Save Tabs as Group…**, or **Edit → Create Group from Open Tabs…**
3. Enter a group name → **Save**

Groups are created from open tabs, or as an **empty group** via the sidebar context menu (**New Empty Group**). Drag sessions onto an empty group to add members.

### Update group layout

With a group’s tabs open and arranged (including splits), right-click the group → **Update Layout from Open Tabs** to refresh the saved split layout.

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

**Command history** — use the ▼ control or arrow keys in the command field to recall recent broadcasts.

**Presets** — choose a named preset from the menu to fill the command field with a saved snippet (configured in `config.toml` or Settings).

Disable the feature with `show_command_bar = false` or `broadcast_enabled = false` in `config.toml`.

---

## 7. SFTP

For SSH sessions, enable **Enable SFTP** in the session editor. An arrow icon appears in the sidebar.

| Action | Result |
|--------|--------|
| Click arrow icon | Opens **Session Name (SFTP)** in a new embedded tab running `sftp` |
| Right-click → **SFTP** | Same |
| Right-click → **Browse SFTP…** | Opens a sheet listing remote directories |

**Browse SFTP** supports:

| Action | Result |
|--------|--------|
| Click folder | Navigate into directory |
| **Up** / **Refresh** | Parent directory / reload listing |
| **Upload** | Pick a local file and upload to current remote path |
| **Download** (per file) | Save remote file locally |
| **Bookmarks** menu | Save current folder or jump to a saved path (stored in `sessions.json`) |

SFTP uses the same SSH credentials (agent, password, or private key) as the parent session.

---

## 7.1 Terminal appearance & behavior

### Theme (TB-11)

| Setting | Effect |
|---------|--------|
| **System** | Follows macOS light/dark appearance for foreground/background |
| **Light** | Black text on white background |
| **Dark** | White text on black background |
| **Custom ANSI palette** | Optional 8-color override in Settings or `[performance.ansi_palette]` in `config.toml` |

Custom ANSI colors affect terminal escape sequences (red, green, etc.). They do **not** change the window chrome or sidebar — only embedded terminal rendering.

### Copy, paste, and export

| Feature | Config / action |
|---------|-----------------|
| Copy on select | Settings → **Copy on select**, or `copy_on_select = true` |
| Paste on middle-click | Settings → **Paste on middle-click**, or `paste_on_middle_click = true` |
| Export scrollback | Edit → **Export Terminal Transcript…** |
| Export selection | Edit → **Export Terminal Selection…** |
| Export I/O log | Edit → **Export Tab I/O Log…** (from `terminal-io-*.log`, with redaction) |
| Session recording | Enable **Session recording** in Settings; reveal via Edit → **Reveal Session Recording** |

### Connection health

When **Stale tab indicator** is enabled (`stale_tab_minutes` in config), tabs with no terminal output for that interval show an **orange** status dot while still running.

### Session notes & secrets

In the session editor:

- **Store notes in Keychain** keeps runbook text out of `sessions.json` (like passwords).
- **Markdown preview** renders inline formatting for notes.

### Bastion profiles

Define reusable jump hosts in Settings → **Bastion Profiles** or `[[bastions]]` in `config.toml`. Pick a bastion in the session editor to set `ProxyJump` automatically.

### Per-tab remote overrides

Right-click a tab → **Remote Overrides…** to set tab-only remote working directory or `export KEY=value` lines (SSH sessions). Overrides apply on the next connection.

---

## 8. URL scheme & automation

Open sessions from Shortcuts, scripts, or links:

```
terminalmanager://open?uri=ssh://user@host:22
```

Register the app once, then macOS routes `terminalmanager://` URLs to Terminal Manager.

---

## 9. Menus

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
| Find in Terminal… | ⌘F |
| Split Horizontally / Vertically | Split focused tab |
| Focus Command Bar | ⌘⇧L |

### Edit

| Item | Action |
|------|--------|
| Export Terminal Transcript… | Save scrollback from active tab |
| Export Terminal Selection… | Save selected terminal text |
| Export Tab I/O Log… | Export filtered `terminal-io-*.log` lines for active tab |
| Reveal Session Recording | Show plain-text recording file in Finder |
| Check for Updates… | Compare against latest GitHub release |

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

## 10. Settings

Open **Terminal Manager → Settings** (⌘,):

| Setting | Purpose |
|---------|---------|
| Show Session Sidebar | Default sidebar visibility |
| Terminal font / size / theme | Embedded terminal appearance (see §7.1) |
| Copy on select / Paste on middle-click | Terminal clipboard behavior |
| Stale tab indicator | Minutes without output before orange dot |
| Session recording | Plain-text recordings in `logs/recordings/` |
| Check for updates | GitHub release check on launch |
| Bastion profiles | Shared SSH jump hosts |
| Custom ANSI palette | Optional terminal color overrides |
| Restore tabs on launch | Reopen tabs from last session |
| Auto-reconnect | Prompt when a session exits unexpectedly |
| Log terminal I/O | Write shell traffic to `terminal-io-*.log` |
| Terminal I/O max MB | Rotate I/O log when it exceeds this size |
| Sessions JSON file | Path to `sessions.json` (relative or absolute) |
| Sync path | Optional second location for `sessions.json` (e.g. iCloud) |
| Log level | App log verbosity (`debug`, `info`, `warning`, `error`) |
| Export / Import Sessions JSON | Backup or restore the session tree |
| Redact secrets on export | Omit passwords and keys from exported JSON |
| Encrypted backup | Export sessions + config as AES-GCM bundle (passphrase) |

---

## 11. Configuration Files

Default location: `~/.terminalmanager/`

| File | Purpose |
|------|---------|
| `config.toml` | App preferences (edit directly, via Settings, or View menu) |
| `sessions.json` | Sessions, folders, groups |
| `window-state.json` | Window size/position (automatic) |
| `launch-state.json` | Open tabs for restore-on-launch (automatic) |
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

[terminal]
font_name = "Menlo"
font_size = 12
theme = "system"            # system | light | dark
restore_tabs_on_launch = true
auto_reconnect = true

[ui]
show_sidebar = true
show_command_bar = true
show_tooltips = true
broadcast_enabled = true
confirm_on_exit = true      # ask before quitting

[sessions]
file = "sessions.json"
# sync_path = "~/Library/Mobile Documents/com~apple~CloudDocs/terminalmanager/sessions.json"

[logging]
level = "info"              # debug | info | warning | error
log_terminal_io = true
terminal_io_max_mb = 50

[performance]
copy_on_select = false
paste_on_middle_click = true
stale_tab_minutes = 5
session_recording_enabled = false
check_for_updates = true
```

See `config.toml.example` in the project for the full list.

---

## 12. Keyboard Shortcuts

| Action | Default |
|--------|---------|
| New tab | ⌘T |
| Close tab | ⌘W |
| Next tab | ⌘⇧] |
| Previous tab | ⌘⇧[ |
| Duplicate tab | ⌘D |
| Focus command bar | ⌘⇧L |
| Find in terminal | ⌘F |
| Open User Guide | ⌘? |

Customize tab shortcuts via `[[shortcuts]]` entries in `config.toml`.

---

## 13. Protocols & Auth

| Protocol | Notes |
|----------|-------|
| SSH | System `ssh`; agent, password, or key file |
| Telnet | System `telnet` |
| Rlogin | System `rlogin` if available |
| Raw TCP | `nc` to host:port |
| Local | Login shell in embedded PTY |

**Init script** — commands sent after connect (e.g. `cd /var/log`). Use for post-login setup.

**Startup script path** — optional file whose lines are appended to the init script.

**Password auth** — stored in Keychain; legacy askpass scripts under `~/.terminalmanager/` are removed on save.

**ProxyJump** — set a bastion host in the session editor for `ssh -J`.

---

## 14. Troubleshooting

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
