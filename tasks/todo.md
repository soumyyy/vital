# Vital: todo

Goal: ship Vital v1 per docs/superpowers/specs/2026-11-02-vital-design.md, following docs/superpowers/plans/2026-11-02-vital.md. Done when the 11 tasks are checked and measured numbers (footprint, idle CPU) are recorded below.

- [x] 1 Scaffold, repo, bare menu bar app
- [x] 2 Models, formatting, load bands
- [x] 3 CPU and memory samplers
- [x] 4 Process sampler, grouping, protection
- [x] 5 Storage
- [x] 6 Thermal and fans
- [x] 7 Process actions
- [x] 8 Sampler orchestration
- [x] 9 UI
- [x] 10 Icon and packaging
- [x] 11 Verification and docs

## Review
Built and pushed to the private repo soumyyy/vital. 52 unit and integration tests pass.

Measured (M3 MacBook Pro, 8 GB): 12 MB footprint and about 0% CPU with the panel never opened; about 90 MB and 3% CPU while open; about 28 MB after closing. The closed-after-use figure misses the 20 MB goal because SwiftUI, AppKit and Core Animation keep caches. Fix if it matters: run the panel UI in a short-lived helper process.

Not done or not verified:
- No Developer ID certificate on this Mac (only Apple Development), so notarization is scripted but untried.
- Only this M3 was tested. Other chips rely on runtime sensor discovery and `--dump-sensors` fixtures.
- Quit and Force Quit are covered by tests against real spawned processes, but the panel buttons were not clicked end to end.
- macOS 14 and 15 fallback (frosted material) was not run, only macOS 27.
- Heavy-load test (CPU burner and memory hog against the live UI) was not run.

## Round 2 (owner feedback)

Done: new heartbeat icon (menu bar glyph and app icon); storage rework (parallel streamed scan, 143 s down to 42 s, cached across panel opens, resumable, Full Disk Access hint); refresh button; 5 s CPU smoothing (total, clusters, per process); CPU shown as share of the whole CPU plus per-core style; plain "8 cores" wording; Fans card.

Fan control: NOT built. An unprivileged SMC write is refused (kIOReturnNotPrivileged), so it needs a root helper. Design and findings are in docs/superpowers/specs/2026-11-02-fan-control-helper.md. Needs the owner's decision and a Developer ID certificate.

Not verified visually in the live menu bar this round: the display was off, so the new panel and icon were checked through offscreen rendering (`Vital --render-panel`, `--dump-icons`) and command line probes only. 68 tests pass; closed-panel footprint 12 MB, about 0% CPU.

The Opus delegate ran out of usage mid-task after the icon and part of the storage work; the rest was finished directly.

Round 3: added network speed, battery card, idle wake-ups (Heat tab) and keeping-awake flags. 83 tests. Open panel about 33 MB, about 29 MB after closing. Disk tab not built (owner did not pick it).

Round 4 (lean): closed cadence 15 s when calm (5 s when busy), open cadence 2 s, hang check every 6 s, -Osize and strip (binary 2.0 MB to 0.85 MB). Measured: closed 12 MB and about 0.02% CPU; open 33 MB and about 1.8% CPU; after closing 28 MB. Bisect: empty panel leaves 17 MB, rows 3 MB, list 5 MB, tabs and pill 1 MB each, so about 17 MB is the SwiftUI floor.

## Round 5: UI redesign (spec)

Problem: the top half of the panel was five stacked vital cards (CPU, Memory, Storage, Thermal, Battery and Network), then five tabs, then the app list, which was mostly below the fold. The same number appeared up to four times (CPU % in card header, "Using N of 8 cores", row value, "% of a core"). P/E cores, swap, health, cycles, network and sleep blockers were all default-visible.

New hierarchy (top to bottom, one canonical place per fact):
1. Headline: one sentence that answers "is my Mac healthy?" ("Your Mac is running fine", "Chrome is slowing your Mac", "Memory is getting full"), an optional one-line reason, and a Quit button for the culprit app when there is one. When an app is not responding, the headline becomes the tinted struggling strip with "Force Quit N not responding". Derived by a pure `Health.headline(_:)` in VitalCore (tested).
2. Vital tiles: CPU, Memory, Storage, Heat. One number each (CPU %, memory used %, storage used %, hottest °C), and a thin meter that is neutral when fine and yellow or red only when it matters. The tiles are the selector (replaces the five tabs). The panel opens on the tile the headline is about.
3. Top apps for the selected tile: icon, name, one value. Six rows, "Show more" for up to twelve. Subtitles only for meaning ("Not responding"). Tap a row for its processes and Quit / Force Quit. Storage shows folder categories instead.
4. Details (disclosure under the list, closed by default), per tile:
   - CPU: last 2 minutes chart, cores in use, performance / efficiency cores.
   - Memory: used of total, pressure, swap, reading back from swap (page-ins) with the thrashing warning.
   - Storage: used of total and free, disk activity (reading and writing totals and the top apps; this was the Disk tab), Full Disk Access and skipped-folder notes.
   - Heat: CPU and GPU temperature, battery (charge, state, time, health, cycles), network speed, apps keeping the Mac awake, fan card (only when the Mac has fans).
   - Per-app extras moved into the expanded row: "% of a core" (CPU), wake-ups and keeping-awake (Heat).

Removed or merged: Disk tab (into Storage details and Memory details), Battery/Network card (into Heat details), separate struggling strip (merged into the headline), "8 cores" and "N processes" labels, thermal gradient scale, per-row second value line, card borders.

Panel height follows content (capped at 680 pt, top edge stays under the menu bar icon), so a calm Mac gets a short panel.

- [x] Health.headline + tile levels in VitalCore, with tests
- [x] Tiles, headline, list, details views; remove RowsView and TabsView
- [x] Dynamic panel height in PanelController
- [x] Renderer: --mock=calm|busy|struggling, --appearance=light|dark, --details, --wait=N
- [x] Renders reviewed for every state, iterate once
- [x] swift build, swift test, footprint and CPU measured
- [x] Commit own files only, push

## Round 5: UI redesign (review)

Built as specced. Tabs went from five to none: the four vital tiles are the selector. Disk folded into Storage details (reading, writing, busiest apps) and Memory details (read back from disk). The struggling strip merged into the headline. Expanded apps merge processes by name ("Browser Helper ×24"); the "% of a core" figure moved to a hover tooltip. On Heat, rows at 0.0 W are hidden. The panel opens on the vital the headline is about (never Storage, which would start a scan).

Verified offscreen (display asleep): calm, busy, struggling with a not-responding app, CPU/Memory/Heat details, an expanded app, Storage while scanning, light and dark. Renders in /tmp/vital-render/v4 and v5. Iterations fixed: duplicated process names, two percentages per process line, 0.0 W rows, "Cores in use" restating the CPU tile, and offscreen appearance bugs in the renderer.

Tests: 111 pass (12 new in HealthTests).

Measured (same machine, same method, release builds, A/B against HEAD): panel open 34 MB to 27 MB, open CPU 1.9% to 1.3-1.5%, after close 30 MB to 25-26 MB, never opened 11-12 MB and about 0% (unchanged).

Not verified: the live panel on screen (resize animation, top edge staying under the icon, Liquid Glass look, hover tooltips), macOS 14/15 frosted fallback, and a real hung app (staged with --mock).
