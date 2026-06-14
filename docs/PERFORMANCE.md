# Performance Baseline & Profiling

This document supports [SPEC §9.10](SPEC.md#910-measurement-targets) (Phase 3 measurement targets).

## Goals

| Scenario | Metric | Target |
|----------|--------|--------|
| Cold launch, empty config | Time to interactive window | < 300 ms |
| Restore 20 SSH tabs | Time to usable UI | < 2 s (staggered, Phase 3.3) |
| 20 tabs, 1 active | Idle CPU | < 5% |
| 20 tabs open | Resident memory | < 500 MB (with hibernation, Phase 3.1) |
| 500-session sidebar | Filter keystroke to update | < 100 ms |
| Drag session between folders | Perceived latency | < 50 ms |

## Instruments workflow (macOS)

1. Build release: `make build-release && make package-release`
2. Open **Instruments** → **Time Profiler** template
3. Attach to **Terminal Manager** (or launch via Instruments)
4. Reproduce the workload below for 60 seconds
5. Repeat with **Allocations** and **File Activity** templates

### Standard 20-tab workload

1. Create or import 20 SSH session profiles
2. Open all 20 in tabs
3. Leave 19 idle; in the active tab run `yes` or `tail -f` on a log file
4. Switch tabs every 5 seconds
5. Edit sidebar (rename session, drag to folder)
6. Quit app (verify launch-state and sessions flush)

### Sidebar scale workload

1. Import or generate a `sessions.json` with 500+ profiles (nested folders optional)
2. Type in **Search sessions…** — measure keystroke-to-list-update
3. Expand/collapse large folders

## Unit perf smoke tests

Run in CI:

```bash
make test
```

Included checks:

- `SessionTreeFilterTests` — filter correctness
- `SessionTreeIndexTests` — O(1) index rebuild
- `PersistenceCoordinatorTests` — off-main sessions write

Optional local benchmark (not in CI): filter 500 synthetic sessions in < 100 ms using `SessionTreeFilter.filter`.

## Phase 3.0 optimizations (shipped)

| ID | Change |
|----|--------|
| PF-01 | Debounced `launch-state.json` writes (`[performance].launch_state_debounce_ms`) |
| PF-02 | Debounced sidebar search (`sidebar_search_debounce_ms`) |
| PF-03 | Off-main `sessions.json` encode/write (`sessions_save_off_main`) |
| PF-04 | `SessionTreeIndex` for O(1) item lookup |
| PF-05 | Separate `ConfigStore` environment object (narrow SwiftUI invalidation) |
| PF-06 | Configurable scrollback cap (`max_scrollback_lines`) |

## Phase 3.1 optimizations (shipped)

| ID | Change |
|----|--------|
| PF-10 | Tab hibernation — terminate hidden PTYs after `[performance].hibernate_inactive_tabs_minutes` (0 = off) |
| PF-11 | Lazy PTY mount — only visible tabs (selected ± split panes) mount `EmbeddedTerminalView`; restore opens tabs without starting all sessions |
| PF-12 | Detached windows participate in visibility tracking and hibernation |
| PF-13 | Terminal I/O metadata-only mode (`terminal_io_metadata_only`) logs byte counts instead of content |
| PF-14 | `cleanupTabResources` on tab close / detached window close (PTY + broadcast handlers + lifecycle tracking) |

## Phase 3.2 optimizations (shipped)

| ID | Change |
|----|--------|
| PF-20 | Flat sidebar rows (`SessionSidebarFlatRowBuilder`) — lazy `List` without nested `ForEach` |
| PF-21 | `SessionTreeSearchIndex` — precomputed searchable text including notes |
| PF-22 | Stable row IDs; folder/group expand state preserved across tree updates |
| PF-23 | Debounced ⌘F input (`find_debounce_ms`); clears search state before next match |
| PF-24 | Broadcast skips exited/hibernated tabs; optional inter-tab delay (`broadcast_batch_delay_ms`) |

## Phase 3.3 optimizations (shipped)

| ID | Change |
|----|--------|
| PF-30 | Defer `sessions.json` load until sidebar opens (`defer_sessions_load`) |
| PF-31 | Staggered tab restore in batches (`stagger_tab_restore`, `stagger_tab_restore_batch_size`) |
| PF-32 | Incremental async Keychain password migration with progress for large trees |
| PF-33 | Encrypted backup export/import off main thread with progress overlay |
| PF-34 | `sync_path` file watcher, conflict backup, and mirror on save |

## Recorded baselines

Captured on development hardware via unit perf smoke tests (`swift test`, SessionTreeFilterPerformanceTests):

```
Date: 2026-06-14
Machine: arm64e macOS (local dev)
macOS: 14+
Tab count: n/a (unit smoke)
Idle CPU (%): not profiled (use Instruments 20-tab workload)
Memory (MB): not profiled (use Instruments with hibernation on)
Sidebar filter 500 sessions: ~5 ms (unit smoke, arm64 dev machine)
```

Record baseline numbers in this file after profiling on your hardware:

```
Date:
Machine:
macOS:
Tab count:
Idle CPU (%):
Memory (MB):
Sidebar filter (ms):
```

## Related

- [Functional Spec §9](SPEC.md#9-phase-3--performance--scale)
- [High-Level Design §13](HLD.md#13-performance--scale)
