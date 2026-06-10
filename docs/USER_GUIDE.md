# Terminal Manager — User Guide

Terminal Manager helps you run many terminal sessions in one window, organize saved connections in the sidebar, and reopen multi-tab layouts with a single double-click.

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

Developers can run the app without installing a DMG:

```bash
cd terminalmanager
make run
```

Equivalent: `bash scripts/run-app.sh`. See [README](../README.md) for `make dmg`, release builds, and other targets.

### Main window layout

```
┌─────────────────────────────────────────────────────────┐
│ [Command toolbar — optional]                            │
├─────────────────────────────────────────────────────────┤
│ Tab │ Tab │ Tab │ +                                      │
├──────────┬──────────────────────────────────────────────┤
│ Sessions │  Terminal workspace (single or split panes)  │
│ sidebar  │                                              │
│          │                                              │
└──────────┴──────────────────────────────────────────────┘
```

- **Sidebar** — saved sessions, folders, and groups
- **Tab strip** — open sessions; click to switch
- **Workspace** — the active terminal (or split panes for the selected tab)

---

## 2. Sessions

### Connect to a saved session

1. Single-click a session in the sidebar to select it
2. Click **Connect** in the sidebar toolbar, or **double-click** the session

### Create a session

- Right-click the sidebar → **New Session**
- Fill in name, host, protocol, credentials, and optional init script
- Click **Save**

### Organize with folders

- Right-click sidebar → **New Folder**
- Drag sessions onto folders to move them
- Drag sessions or folders to reorder

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
| Rename tab | Double-click title, or right-click → **Rename…** |
| Reorder tabs | Drag tab chips |
| Detach tab | Right-click → **Detach Window** |
| Reattach | **Reattach** button in detached window |

---

## 4. Split Panes

Split applies only to the **currently selected tab** and does not affect other tabs.

| Action | How |
|--------|-----|
| Split horizontal | Toolbar **Split Horizontal** or Session menu |
| Split vertical | Toolbar **Split Vertical** or Session menu |

**What happens:**

- Your **current session stays running** in one pane
- **One new local shell** opens in the other pane
- Switch to another tab → that tab shows full-screen (or its own split if you split it earlier)
- Switch back → your split layout returns

Close a pane with **⌘W** on that tab; when only one pane remains, the split ends.

---

## 5. Session Groups

Groups save a set of open tabs and their split layout so you can reopen them together.

### Create a group from open tabs

1. Open the sessions you want in tabs (arrange splits if needed)
2. Right-click the sidebar → **Save Tabs as Group…**
   - Or use toolbar **Save as Group**
3. Enter a group name → **Save**

Groups are created from open tabs only (there is no “empty group”).

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

### Add sessions to a group

Drag a session from the sidebar onto a group.

### Remove a member

Expand the group, right-click a member → **Delete**.

This removes the reference only; the session profile remains in the sidebar.

---

## 6. Command Toolbar (Broadcast)

Send the same command to one or all embedded tabs.

1. Type a command in the **Send command to shell…** field
2. Choose **Selected Tab** or **All Tabs**
3. Press **Send** or ⌘Return

| Shortcut / menu | Action |
|-----------------|--------|
| ⌘⇧L | Focus command bar (shows bar if hidden) |
| View → Show Command Toolbar | Toggle visibility |

Disable the feature entirely with `broadcast_enabled = false` in `config.toml`.

---

## 7. View Menu

| Option | Effect |
|--------|--------|
| Show Session Sidebar | Show or hide the session list |
| Show Command Toolbar | Show or hide the broadcast bar |

Changes are saved to `config.toml`.

---

## 8. Settings

Open **Terminal Manager → Settings** (⌘,):

- Terminal backend (Embedded vs Ghostty)
- Ghostty.app path
- Show sidebar default
- Sessions JSON file path
- Log level
- Export / import sessions JSON

---

## 9. Configuration Files

Default location: `~/.terminalmanager/`

| File | Purpose |
|------|---------|
| `config.toml` | App preferences (edit directly or via Settings / View menu) |
| `sessions.json` | Sessions, folders, groups |
| `window-state.json` | Window size/position (automatic) |
| `logs/` | Daily log files |

### Portable setup

Copy the whole directory to a USB drive or sync folder:

```bash
export TERMINALMANAGER_CONFIG=/path/to/my-config
make run
```

### Useful `config.toml` options

```toml
[app]
single_instance = true      # only one app instance per config dir

[window]
start_maximized = true
restore_position = true

[ui]
show_command_bar = false    # maximize terminal area
confirm_on_exit = true      # ask before quitting
```

See `config.toml.example` for the full list.

---

## 10. Keyboard Shortcuts

| Action | Default |
|--------|---------|
| New tab | ⌘T |
| Close tab | ⌘W |
| Next tab | ⌘⇧] |
| Previous tab | ⌘⇧[ |
| Duplicate tab | ⌘D |
| Focus command bar | ⌘⇧L |

Customize via `[[shortcuts]]` entries in `config.toml`.

---

## 11. Protocols & Auth

| Protocol | Notes |
|----------|-------|
| SSH | Uses system `ssh`; agent, password, or key file |
| Telnet | System `telnet` |
| Rlogin | System `rlogin` if available |
| Raw TCP | `nc` to host:port |
| Local | Login shell in PTY |

**Init script** — commands sent after the session connects (e.g. `cd /var/log`).

**SFTP** — click the arrow icon on SFTP-enabled SSH sessions (opens Ghostty).

---

## 12. Troubleshooting

| Problem | Suggestion |
|---------|------------|
| App not in Dock | Use `make run` or `bash scripts/run-app.sh`, not bare `swift run` |
| “App is damaged” or won’t open | Unsigned DMG build — allow in **Privacy & Security** or build from source |
| Second launch does nothing | `single_instance = true` — existing window is focused |
| Ghostty sessions fail | Grant Automation permission; check Ghostty path in Settings |
| SSH password auth fails | Re-save session; check `~/.terminalmanager/askpass-*.sh` exists |
| Split shows wrong tabs | Split is per-tab; select the tab you split before expecting layout |
| Group member “Missing session” | Referenced session was deleted; remove member from group |

Logs: `~/.terminalmanager/logs/terminalmanager-YYYY-MM-DD.log`

---

## 13. Further Reading

- [Functional Specification](SPEC.md) — requirements and schemas
- [High-Level Design](HLD.md) — architecture for developers
- [README](../README.md) — build instructions
