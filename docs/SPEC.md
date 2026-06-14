# Functional Specification: Terminal Manager

**Product:** Terminal Manager (`terminalmanager`)  
**Platform:** macOS 14+  
**Status:** v1 baseline shipped · v1.1–v2.x roadmap implemented · **v3 performance plan** (see [§9](#9-phase-3--performance--scale))

---

## 1. Product Overview

Terminal Manager is a native macOS application that consolidates multiple terminal sessions—SSH, Telnet, Rlogin, raw TCP, and local shells—into a single tabbed window with a session sidebar, split panes, session groups, and portable configuration.

### 1.1 Goals

- Reduce desktop clutter from many terminal windows
- Provide saved connection profiles organized in folders and groups
- Support repeatable multi-session workflows (groups with split layouts)
- Keep configuration human-editable and portable (`config.toml` + `sessions.json`)

### 1.2 Non-Goals (v1)

These remain **out of scope** for v1. Items marked *roadmap* are planned in later phases (§8).

| Item | Notes |
|------|-------|
| Windows/Linux ports | macOS-only for foreseeable releases |
| Built-in SFTP file browser | SFTP opens embedded `sftp` CLI (*roadmap:* optional file panel in §8) |
| Session recording / playback | *roadmap:* optional capture in §8 |
| Multi-user or cloud sync | *roadmap:* optional encrypted sync in §8 |
| External terminal backends | Removed; embedded SwiftTerm only |

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
| SM-09 | Optional SFTP launch in embedded tab | ✅ |
| SM-10 | SSH ProxyJump / bastion field | ✅ |
| SM-11 | Per-session SSH extra options | ✅ |
| SM-12 | Duplicate session to folder | ✅ |
| SM-13 | Test connection (non-interactive probe) | ✅ |
| SM-20 | Session templates in config | ✅ |
| SM-21 | `terminalmanager://` URL scheme | ✅ |

### 2.2 Session Groups

| ID | Requirement | Status |
|----|-------------|--------|
| SG-01 | Save open tabs (+ split layout) as a named group | ✅ |
| SG-02 | Groups hold references to existing sessions, not copies | ✅ |
| SG-03 | Double-click group opens all members with saved layout | ✅ |
| SG-04 | Drag session onto group to add reference | ✅ |
| SG-05 | Duplicate, rename, delete group via context menu | ✅ |
| SG-06 | Remove group member via context menu Delete | ✅ |
| SG-07 | Save group from open tabs (empty groups also supported via context menu) | ✅ |
| SG-10 | Create empty group | ✅ |
| SG-11 | Update group layout from open tabs | ✅ |

### 2.3 Tabs & Workspace

| ID | Requirement | Status |
|----|-------------|--------|
| TW-01 | Multi-tab strip with reorder via drag-and-drop | ✅ |
| TW-02 | Rename tab (double-click or context menu) | ✅ |
| TW-03 | Detach tab to separate window; reattach | ✅ |
| TW-04 | Horizontal / vertical split on focused tab only | ✅ |
| TW-05 | Split preserves existing session; adds duplicate of same profile in new pane | ✅ |
| TW-06 | Per-tab split layouts (switching tabs restores each layout) | ✅ |
| TW-07 | Close tab removes it from that tab’s split only | ✅ |
| TW-10 | Tab status indicator (idle / running / exited) | ✅ |
| TW-11 | Restore last open tabs on launch (optional) | ✅ |
| TW-12 | Auto-reconnect prompt on unexpected exit | ✅ |
| TW-13 | Split pane duplicates session protocol | ✅ |

### 2.4 Command Broadcast

| ID | Requirement | Status |
|----|-------------|--------|
| BC-01 | Command toolbar sends input to selected or all tabs | ✅ |
| BC-02 | Toggle toolbar visibility (View menu + config) | ✅ |
| BC-03 | Focus command bar (⌘⇧L); shows bar if hidden | ✅ |
| BC-10 | Command bar history | ✅ |
| BC-11 | Named broadcast presets | ✅ |

### 2.5 Application Behavior

| ID | Requirement | Status |
|----|-------------|--------|
| AB-01 | Single-instance mode (config.toml) | ✅ |
| AB-02 | Restore window position / zoom between launches | ✅ |
| AB-03 | Optional confirm-on-exit dialog | ✅ |
| AB-04 | Portable config via `TERMINALMANAGER_CONFIG` | ✅ |
| AB-05 | File logging with configurable level | ✅ |
| AB-06 | Terminal I/O log with rotation and toggle | ✅ |
| AB-07 | Restore open tabs on launch (optional) | ✅ |
| AB-08 | Encrypted session backup (passphrase) | ✅ |
| AB-12 | Export sessions with secrets redacted | ✅ |
| AB-20 | Optional sync path for sessions file | ✅ |
| AB-21 | Encrypted backup bundle | ✅ |
| DP-02 | CI workflow (build, test, package) | ✅ |

### 2.6 Terminal

| ID | Requirement | Status |
|----|-------------|--------|
| TB-01 | Embedded terminal (SwiftTerm) for all sessions | ✅ |
| TB-10 | Configurable terminal font and size | ✅ |
| TB-11 | Terminal theme (system / light / dark) | ✅ |
| TB-20 | Find in terminal scrollback (⌘F) | ✅ |
| TB-30 | SFTP directory browser (basic) | ✅ |

### 2.7 UX & Editor (v1 baseline)

| ID | Requirement | Status |
|----|-------------|--------|
| UX-01 | Connection URI parsing (`ssh://`, `ssh2://`, `telnet://`, `rlogin://`) | ✅ |
| UX-02 | Edit menu actions for sidebar tree (folder, session, group) | ✅ |
| UX-03 | In-app User Guide (Help → Terminal Manager Help, ⌘?) | ✅ |
| UX-04 | Optional tooltips on controls (`show_tooltips`) | ✅ |
| UX-05 | Separate terminal I/O log (`terminal-io-*.log`) | ✅ |
| UX-10 | Sidebar search / filter | ✅ |
| UX-11 | Quick Connect bar in main window | ✅ |
| UX-12 | Session tag color in sidebar | ✅ |
| UX-20 | Detached window remembers size/position per tab | ✅ |

### 2.8 Security

| ID | Requirement | Status |
|----|-------------|--------|
| SEC-01 | SSH passwords in Keychain (migrate from JSON) | ✅ |

### 2.9 Quality

| ID | Requirement | Status |
|----|-------------|--------|
| QA-01 | Unit tests (URI, launcher, filter) | ✅ |

---

## 3. User Interface

### 3.1 Main Window

- **Navigation split:** Session sidebar (optional) + detail workspace
- **Quick Connect bar:** URI or `user@host` field above tabs (optional)
- **Command toolbar:** Broadcast target picker + command field with history and presets (optional)
- **Tab strip:** Tab chips with status dot, close, detach, rename, reorder
- **Find bar:** In-terminal search (⌘F) when a tab is focused
- **Workspace:** Single terminal or split panes for the selected tab’s layout

### 3.2 Sidebar

- Tree: folders, sessions, groups
- Search field filters by name, host, protocol, notes
- Tag color dot beside session names (optional per profile)
- Single-click select; double-click open (session/group) or expand (folder)
- Context menus: Test Connection, Duplicate to Folder, empty group, update group layout
- Toolbar actions when item selected (Connect, Open Group, Save as Group, Edit, Duplicate)

### 3.3 Menus

| Menu | Key actions |
|------|-------------|
| File | New Tab (⌘T), Close Tab (⌘W) |
| Edit | New Folder, Rename/Delete Folder, New Session, Create Group from Open Tabs |
| Session | Duplicate, next/prev tab, split H/V, focus command bar |
| View | Show sidebar, show command bar, show tooltips |
| Help | Terminal Manager Help (⌘?) — in-app User Guide |

In-app help renders `docs/USER_GUIDE.md` from the app bundle.

---

## 4. Configuration Files

### 4.1 Layout

| File | Purpose |
|------|---------|
| `config.toml` | Application settings |
| `sessions.json` | Session / folder / group tree |
| `window-state.json` | Saved window frame and zoom (auto) |
| `launch-state.json` | Open tabs for restore-on-launch (auto) |
| `instance.lock` | Single-instance lock file (auto) |
| `logs/terminalmanager-*.log` | App events and errors |
| `logs/terminal-io-*.log` | Terminal input and shell output |

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
font_name = "Menlo"
font_size = 12
theme = "system"                 # system | light | dark
restore_tabs_on_launch = false
auto_reconnect = true

[ui]
show_sidebar = true
show_command_bar = true
show_tooltips = true
broadcast_enabled = true
confirm_on_exit = false

[sessions]
file = "sessions.json"
# sync_path = "~/path/to/synced/sessions.json"

[logging]
level = "info"                   # debug | info | warning | error
log_terminal_io = true
terminal_io_max_mb = 50

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
| Find in terminal | ⌘F |

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
| `make notarize` | Sign and notarize DMG (requires Apple Developer credentials) |
| `make test` | Run Swift tests |
| `make clean` | Remove `.build`, app bundle, and `dist/` |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-config.sh` | Create `~/.terminalmanager` from example if missing |
| `scripts/package-app.sh [debug\|release]` | Build binary and assemble `Terminal Manager.app` |
| `scripts/create-dmg.sh` | Release build, stage app + Applications link, write DMG to `dist/` |
| `scripts/notarize-dmg.sh` | Sign app/DMG and submit to Apple notarization |
| `scripts/run-app.sh [debug\|release]` | Bootstrap config, package, and open app |

### Distribution

- DMG filename version comes from `CFBundleShortVersionString` in `Resources/Info.plist`.
- DMG contents: `Terminal Manager.app`, symlink to `/Applications`.
- Builds are unsigned; Gatekeeper may block until the user allows the app manually.
- For public distribution, sign with an Apple Developer ID and notarize via `notarytool`.

---

## 8. Roadmap & Enhancement Status

Phases **1.1–2.x** are largely **shipped** (see §2). Status key: ✅ Done · ⚠️ Partial · 📋 Deferred.

Priorities: **P0** — high impact or blocker · **P1** — significant UX/value · **P2** — nice-to-have.

### 8.1 Phase overview

| Phase | Target | Theme | Status |
|-------|--------|-------|--------|
| **1.1** | v1.1 | Distribution, discoverability, terminal polish | ✅ Shipped |
| **1.2** | v1.2 | Security, SSH depth, session lifecycle | ✅ Shipped |
| **2.0** | v2.0 | Productivity, search, recording | ⚠️ Mostly shipped |
| **2.x** | v2.x+ | Sync, automation, optional SFTP UI | ⚠️ Mostly shipped |

```mermaid
flowchart LR
    v1[v1 shipped] --> v11[v1.1 polish]
    v11 --> v12[v1.2 security]
    v12 --> v20[v2.0 productivity]
    v20 --> v2x[v2.x sync]
```

---

### 8.2 Phase 1.1 — Polish & distribution (v1.1)

| ID | Priority | Requirement | Status |
|----|----------|-------------|--------|
| DP-01 | P0 | Apple Developer ID signing + `notarytool` notarization for release DMG | ⚠️ Script (`scripts/notarize-dmg.sh`); requires Apple credentials |
| DP-02 | P1 | CI workflow: build, test, release artifact on tag | ✅ `.github/workflows/ci.yml` |
| UX-10 | P1 | Sidebar search / filter by name, host, protocol | ✅ |
| UX-11 | P1 | Quick Connect field (URI or `user@host`) in main window | ✅ |
| UX-12 | P2 | Session color tag or icon override in sidebar | ✅ |
| TW-10 | P1 | Tab status indicator (running / exited / disconnected) | ✅ |
| TW-11 | P2 | Restore last open tabs on launch (optional `config.toml`) | ✅ |
| TB-10 | P1 | Configurable terminal font and size in Settings | ✅ |
| TB-11 | P2 | Configurable color theme (light/dark/custom ANSI palette) | ⚠️ system / light / dark only |
| AB-10 | P2 | Log rotation / max size for `terminal-io-*.log` | ✅ |
| AB-11 | P2 | Toggle terminal I/O logging in Settings | ✅ |

---

### 8.3 Phase 1.2 — Security & connections (v1.2)

| ID | Priority | Requirement | Status |
|----|----------|-------------|--------|
| SEC-01 | P0 | Store SSH passwords in macOS Keychain, not plain text in `sessions.json` | ✅ |
| SEC-02 | P1 | Optional Keychain storage for session notes containing secrets | 📋 Deferred |
| SM-10 | P1 | SSH `ProxyJump` / bastion host field | ✅ |
| SM-11 | P1 | Per-session SSH config extras (e.g. `IdentityFile`, `UserKnownHostsFile`) | ✅ |
| SM-12 | P2 | Session duplicate to different folder from context menu | ✅ |
| SM-13 | P2 | “Test connection” action (non-interactive probe) | ✅ |
| TW-12 | P1 | Auto-reconnect prompt when embedded session exits unexpectedly | ✅ |
| TW-13 | P2 | Split pane opens chosen protocol (not local-only) | ✅ |
| AB-12 | P1 | Export sessions JSON with secrets redacted | ✅ |

---

### 8.4 Phase 2.0 — Terminal UX & productivity (v2.0)

| ID | Priority | Requirement | Status |
|----|----------|-------------|--------|
| TB-20 | P1 | Find in terminal scrollback (⌘F) | ✅ |
| TB-21 | P1 | Copy-on-select and configurable paste behavior | 📋 Deferred (SwiftTerm API) |
| TB-22 | P2 | Optional session transcript export (selection or tab lifetime) | 📋 Deferred |
| BC-10 | P1 | Command bar history (recent broadcasts) | ✅ |
| BC-11 | P2 | Named broadcast presets (“deploy”, “status”) | ✅ |
| SG-10 | P2 | Create empty group and add members via drag | ✅ |
| SG-11 | P2 | “Update group layout from open tabs” on existing group | ✅ |
| UX-20 | P1 | Detached window remembers size/position per tab | ✅ |
| UX-21 | P2 | Session notes panel (markdown) in editor | 📋 Deferred |
| QA-01 | P1 | Automated tests for `ConnectionLauncher`, URI parser, layout mapper | ✅ |
| QA-02 | P2 | UI smoke tests for tab open/close/split | 📋 Deferred |

---

### 8.5 Phase 2.x — Sync, automation, SFTP (v2.x+)

| ID | Priority | Requirement | Status |
|----|----------|-------------|--------|
| AB-20 | P2 | Optional sync of `sessions.json` via iCloud Drive or user-chosen folder | ✅ watch + mirror + conflict backup |
| AB-21 | P2 | Encrypted backup bundle (sessions + config) | ✅ |
| SM-20 | P2 | Session templates (defaults for new SSH profiles) | ✅ |
| SM-21 | P2 | Open session from Apple Shortcuts / `terminalmanager://` URL scheme | ✅ |
| TB-30 | P2 | Optional SFTP side panel (file list + transfer) | ⚠️ Basic directory browser |
| TB-31 | P3 | Session recording to asciinema or plain transcript | 📋 Deferred |
| DP-03 | P2 | Sparkle or in-app update check | 📋 Deferred |

---

### 8.6 Technical enablers (cross-cutting)

| ID | Priority | Enabler | Status |
|----|----------|---------|--------|
| TE-01 | P0 | Keychain-backed secret store abstraction | ✅ `KeychainSecretStore` |
| TE-02 | P1 | Split `AppState` into focused observable models | 📋 Deferred |
| TE-03 | P1 | Tab/session lifecycle state machine (idle → running → exited) | ✅ |
| TE-04 | P2 | Pluggable `ConnectionBackend` tests without UI | ⚠️ Partial (`ConnectionTester`) |
| TE-05 | P2 | Settings schema version + migration in `config.toml` | ⚠️ Partial (Keychain migration) |

---

### 8.7 Long-term out of scope

Unless product direction changes, the following are **not** planned:

- Native Windows/Linux clients (consider separate project)
- Built-in VPN or tunnel management
- Multi-user concurrent editing of one config directory
- Replacing system `ssh` with a bundled SSH implementation
- Full IDE / editor integration beyond terminal sessions

---

## 9. Phase 3 — Performance & scale

Phases **3.0–3.3** focus on responsiveness, memory, and large session libraries. Status key: 📋 Planned · 🔄 In progress · ✅ Done.

Priorities: **P0** — user-visible lag or memory leak · **P1** — scale to power users · **P2** — polish.

### 9.1 Current baseline (v2.x)

| Area | Already shipped |
|------|-----------------|
| Terminal mounting | Only visible tab/split panes mount `EmbeddedTerminalView` |
| Session saves | Debounced `sessions.json` writes (250 ms) |
| Terminal I/O log | Background queue, batched output, rotation by size |
| Release builds | LTO + strip via `Package.swift` / `make build-release` |
| Secrets | Keychain passwords (reduces JSON size and churn) |

### 9.2 Known pressure points

| Area | Issue | Impact |
|------|--------|--------|
| `AppState` | Monolithic `@MainActor`; `configStore.objectWillChange` invalidates broad UI | Extra SwiftUI redraws |
| `TerminalSessionStore` | PTY + scrollback live until tab close | RAM ∝ open tabs |
| `saveLaunchState()` | Synchronous disk write on many tab ops | Main-thread I/O spikes |
| Sidebar search | Full-tree filter on every keystroke | CPU at 500+ sessions |
| `ConfigStore` | Recursive O(n) tree lookups | Drag/rename latency |
| Find (⌘F) | Full scrollback scan | CPU on log-heavy tabs |
| Encrypted backup | PBKDF2 120k iterations | ~3 s export (acceptable for backup) |

### 9.3 Phase overview

| Phase | Target | Theme |
|-------|--------|-------|
| **3.0** | v3.0 | Quick wins — debouncing, off-main I/O, narrower invalidation |
| **3.1** | v3.1 | Memory & tab lifecycle — hibernation, lazy start |
| **3.2** | v3.2 | UI scalability — virtualized sidebar, search index |
| **3.3** | v3.3 | Startup & sync — staggered restore, async backup |
| **4.0** | v4.0+ | Deferred product enhancements (§9.7) |

```mermaid
flowchart LR
    v2[v2.x shipped] --> v30[v3.0 quick wins]
    v30 --> v31[v3.1 memory]
    v31 --> v32[v3.2 scale UI]
    v32 --> v33[v3.3 startup]
    v33 --> v40[v4.0 enhancements]
```

---

### 9.4 Phase 3.0 — Performance quick wins (v3.0)

| ID | Priority | Requirement | Rationale |
|----|----------|-------------|-----------|
| PF-01 | P0 | Debounce `launch-state.json` writes (mirror session save debounce) | ✅ |
| PF-02 | P1 | Debounce sidebar search (150 ms) | ✅ |
| PF-03 | P0 | Off-main encode/write for `sessions.json` | ✅ |
| PF-04 | P1 | Session tree index (`UUID` → item, parent pointers) | ✅ |
| PF-05 | P0 | Narrow SwiftUI invalidation (stop full `AppState` fan-out) | ✅ |
| PF-06 | P1 | Configurable scrollback line cap per tab | ✅ |
| PF-07 | P2 | Document Instruments baseline (20-tab scenario) | ✅ `docs/PERFORMANCE.md` |

**Acceptance notes (3.0):** Tab switch and sidebar search feel instant with 500 sessions; session save does not hitch UI; launch-state write coalesced to ≤1 flush per 500 ms burst.

---

### 9.5 Phase 3.1 — Memory & tab lifecycle (v3.1)

| ID | Priority | Requirement | Rationale |
|----|----------|-------------|-----------|
| PF-10 | P0 | Tab hibernation — terminate inactive PTY after N minutes (configurable) | ✅ `hibernate_inactive_tabs_minutes` |
| PF-11 | P1 | Lazy process start — no PTY until tab first visible (incl. restore-on-launch) | ✅ `SplitPaneView` visibility mount |
| PF-12 | P2 | Same hibernation rules for detached windows | ✅ detached visibility + hibernation |
| PF-13 | P2 | I/O log sampling or metadata-only mode | ✅ `terminal_io_metadata_only` |
| PF-14 | P1 | Eager cleanup on tab close (PTY, broadcast handlers) | ✅ `cleanupTabResources` |

**Acceptance notes (3.1):** 20 idle tabs use substantially less memory than 20 active tabs; user can reconnect hibernated tab without data loss beyond scrollback policy.

---

### 9.6 Phase 3.2 — UI scalability (v3.2)

| ID | Priority | Requirement | Rationale |
|----|----------|-------------|-----------|
| PF-20 | P1 | Virtualized sidebar (flat visible rows or `NSOutlineView`) | ✅ flat row model + `List` |
| PF-21 | P1 | Background search index (name, host, protocol, notes) | ✅ `SessionTreeSearchIndex` |
| PF-22 | P2 | Incremental tree diff; preserve expand/collapse | ✅ stable flat row IDs + expand state |
| PF-23 | P2 | Debounced find; search from end; highlight cap | ✅ debounced find + clear-before-search |
| PF-24 | P2 | Broadcast batching; skip exited tabs | ✅ eligible filter + batch delay |

---

### 9.7 Phase 3.3 — Startup & I/O (v3.3)

| ID | Priority | Requirement | Rationale |
|----|----------|-------------|-----------|
| PF-30 | P1 | Fast cold launch — defer `sessions.json` until sidebar needed | ✅ `defer_sessions_load` |
| PF-31 | P1 | Staggered tab restore (batches with run-loop yield) | ✅ `stagger_tab_restore` |
| PF-32 | P2 | Async Keychain migration with progress for large trees | ✅ incremental migration |
| PF-33 | P2 | Async encrypted backup with progress UI | ✅ off-main export/import + overlay |
| PF-34 | P2 | Active `sync_path` watch + conflict backup/merge | ✅ `SessionsSyncWatcher` |

---

### 9.8 Phase 4.0 — Product enhancements (post-performance)

Deferred items from [§8](#8-roadmap--enhancement-status) plus UX depth. Execute after Phase 3 unless unblocked earlier.

| ID | Priority | Requirement | Notes |
|----|----------|-------------|-------|
| EN-01 | P1 | Copy-on-select / configurable paste | TB-21; SwiftTerm API |
| EN-02 | P2 | Session transcript export | TB-22 |
| EN-03 | P3 | Session recording (asciinema or plain text) | TB-31 |
| EN-04 | P2 | Custom ANSI color palette | TB-11 extension |
| EN-05 | P2 | Markdown notes panel in editor | UX-21 |
| EN-06 | P2 | Full SFTP panel (upload/download, bookmarks) | TB-30 extension |
| EN-07 | P2 | Sparkle / in-app updates | DP-03; after notarization |
| EN-08 | P1 | Keychain storage for notes with secrets | SEC-02 |
| EN-09 | P2 | UI smoke tests (XCUITest) | QA-02 |
| EN-10 | P2 | Connection health / stale tab indicator | Extends TW-10 |
| EN-11 | P2 | Per-tab env / cwd for remote sessions | Power users |
| EN-12 | P2 | Reusable bastion / jump-host profiles | Enterprise SSH |

---

### 9.9 Technical enablers (Phase 3)

| ID | Priority | Enabler | Unblocks |
|----|----------|---------|----------|
| TE-02 | P0 | Split `AppState` into focused observable models | PF-05, PF-10, testability |
| TE-06 | P1 | `TabController` state machine (idle → running → hibernated → exited) | PF-10, PF-11 | ✅ Partial (`TabSessionState.hibernated`, lifecycle manager) |
| TE-07 | P1 | Indexed session tree + flat row model | PF-04, PF-20, PF-21 | ✅ Partial (`SessionTreeIndex`) |
| TE-08 | P1 | `PersistenceCoordinator` (debounced, off-main) | PF-01, PF-03, PF-34 | ✅ Partial |
| TE-09 | P2 | `[performance]` section in `config.toml` | All PF-* toggles | ✅ |

Proposed `[performance]` schema (v3):

```toml
[performance]
launch_state_debounce_ms = 500
sidebar_search_debounce_ms = 150
max_scrollback_lines = 10000
hibernate_inactive_tabs_minutes = 30
terminal_io_metadata_only = false
stagger_tab_restore = true
sessions_save_off_main = true
```

---

### 9.10 Measurement targets

Capture baselines before Phase 3.0; verify after Phase 3.3.

| Scenario | Metric | Target |
|----------|--------|--------|
| Cold launch, empty config | Time to interactive window | < 300 ms |
| Restore 20 SSH tabs | Time to usable UI | < 2 s (staggered) |
| 20 tabs, 1 active | Idle CPU | < 5% |
| 20 tabs open (hibernation on) | Resident memory | < 500 MB |
| 500-session sidebar | Filter keystroke to update | < 100 ms |
| Drag session between folders | Perceived latency | < 50 ms |
| Encrypted backup export | UI freeze | 0 ms (async + progress) |

**Tooling:** Instruments (Time Profiler, Allocations, File Activity); unit perf smoke (e.g. filter 500 items < 100 ms); optional CI on macOS runner.

---

## 10. Related Documents

- [High-Level Design (HLD)](HLD.md)
- [User Guide](USER_GUIDE.md)
- [README](../README.md)
