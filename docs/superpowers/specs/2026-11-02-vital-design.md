# Vital: design

Date: 2026-11-02. Status: draft for approval.

## Intent

Vital is a macOS menu bar app that answers one question quickly: **what is eating my Mac right now, and can I stop it?**

The owner's pain: the Mac (an M3 MacBook Pro with 8 GB RAM) gets slow, apps are slow to open and close, and Activity Monitor is itself slow to load in exactly those moments. Vital must stay responsive when the machine is not, show the culprits grouped by app, and let the owner quit or force quit them in two clicks.

It is a personal tool first and an open-source project second (MIT). Nothing in v1 is built to scale beyond that.

## Goals

1. Menu bar icon only. Click opens a translucent glass panel.
2. Show live CPU, memory (with swap and pressure), storage and thermal state (temperatures and fans).
3. For each resource, show which apps consume it. Apps are grouped (Chrome plus its helpers is one entry) and expand to individual processes.
4. Quit and Force Quit from the panel, with safe handling of system processes, other users' processes, and processes stuck in the kernel.
5. Stay lean: **closed-panel resident footprint under 20 MB (hard ceiling 40 MB), under 0.5% CPU when idle.** Vital must never make a struggling Mac worse.
6. Run on every Apple Silicon MacBook, M1 and later, macOS 14+. Degrade gracefully (hide or show "n/a") where a sensor is missing, never crash.

## Non-goals (v1)

- Alerts and notifications of any kind.
- Deleting or cleaning files (storage is read-only until v2).
- Intel Macs (later; needs a separate SMC path).
- GPU, network, battery panels.
- A live readout in the menu bar (icon only; a selectable readout comes later).
- Mac App Store distribution (impossible: private sensor APIs, unsandboxed).

## Anti-goals

Things that would make Vital a failure even if it technically works:

- It shows up in its own top-offenders list.
- It beach-balls or lags when the system is under heavy load.
- It claims to have killed a process that is still running.
- It kills something it should not (kernel_task, launchd, WindowServer, loginwindow, itself).
- It shows invented numbers when a sensor is unavailable.

## Platform and tooling (builder's call, confirmed as "whatever's lean")

- Swift 6, Swift Package Manager, no third-party dependencies. Xcode is installed and may be used for debugging but the build is scriptable from the command line.
- Targets: `VitalCore` (samplers and pure logic, no UI), `Vital` (AppKit shell plus SwiftUI views), `VitalTests`.
- A build script produces `Vital.app` (`LSUIElement` set, so no Dock icon), generates the icon set from the SVG source, signs ad hoc for development, and for release signs with the owner's Developer ID, notarizes with `notarytool` and produces a DMG.
- Deployment target macOS 14. Liquid Glass (`glassEffect`) is used when `#available(macOS 26, *)`. Below that, use `NSVisualEffectView` / SwiftUI materials.
- Lean UI rule: AppKit owns the status item and the panel window. The SwiftUI view tree is created when the panel opens and released when it closes, so the closed-state footprint carries no view hierarchy. This is the main lever for the 20 MB target.

## Visual design (decided by the owner)

**Look:** translucent glass, light and clean, native to macOS 26 Liquid Glass. Honor Reduce Transparency (opaque fallback) and Increase Contrast.

**Menu bar icon:** the Vial (option 1 from the mockups): a glass vial glyph as a template image (adapts to light and dark menu bars). The liquid level and tint reflect overall load in three bands (calm, busy, struggling) and only redraw when the band changes. The app icon is the same vial on a blue-violet gradient squircle with a light glass rim.

**Panel, top to bottom:**

1. *(Only when struggling)* A slim strip: "Mac is struggling", the main cause in one line, and a "Quit all not responding" button.
2. **Four stacked glass rows:**
   - CPU: sparkline and the P-core / E-core split (for example "4P + 4E · 34%").
   - Memory: used / total bar, swap used, and memory pressure (normal, elevated, critical).
   - Storage: used / total bar for the boot volume.
   - Thermal: green-yellow-red scale with a marker at the hottest relevant temperature, fan rpm beside it. Fan text is omitted when the Mac has no fans.
3. **Tabs:** CPU, Memory, Storage, Heat. Tapping a row selects its tab.
4. **Breakdown list** for the selected tab:
   - Entries are apps, ranked by that resource. Each shows icon, name, process count and the value.
   - Tapping an entry expands it to its individual processes.
   - Each app entry has Quit and Force Quit. Protected system processes show a lock instead.
   - Heat tab ranks by power draw (energy per second), since macOS has no per-app temperature. The UI says "power draw", not "temperature".
   - Storage tab shows categories and folders instead of processes (see Storage).

Ranking rule for CPU: sorted by CPU over the last sample window. Memory: by physical footprint (the number Activity Monitor calls "Memory").

## Data sources and behavior

All sampling uses direct system calls. **Vital never shells out** to `ps`, `top`, `vm_stat` or similar: spawning subprocesses is slow and heavy on a struggling Mac.

| Metric | Source |
|---|---|
| CPU total and per core | `host_processor_info` tick deltas. P/E split from `sysctl hw.perflevel0` / `hw.perflevel1`. |
| Per-process CPU, memory | `proc_listallpids`, `proc_pidinfo` / `proc_pid_rusage` (deltas for CPU time; `ri_phys_footprint` for memory). Processes are keyed by pid plus start time to survive pid reuse. |
| Memory, compressed, swap | `host_statistics64`, `sysctl vm.swapusage`. Pressure from the kernel memory-pressure level (dispatch memory-pressure source), not from a "percent used" guess. |
| Storage | `URLResourceValues` available capacity "for important usage" (matches Finder, counts purgeable space) plus total capacity. |
| Thermal state | `ProcessInfo.thermalState` (public). Mapped to nominal, fair, serious, critical. |
| Temperatures | Private HID sensor client (`IOHIDEventSystemClient`, temperature sensors on the PMU). Discover sensors by name at runtime instead of hard-coding a table per chip, with a per-chip-family fallback table adapted from Stats (MIT, credited). |
| Fans | SMC via IOKit (`AppleSMC`): fan count, current, min, max rpm. Zero fans means no fan UI. |
| Per-process power | Energy counters from `proc_pid_rusage` as deltas, converted to watts. (Builder to verify the exact field on macOS 14 through 27.) |
| Not responding | Private CoreGraphics/SkyLight call used by Activity Monitor. If unavailable on some OS version, the flag is simply not shown. |
| Grouping | Process path inside an `.app` bundle groups under that app; helpers and XPC services outside the bundle group by responsible process where available, else by name. |

**Unreadable processes (decided by the owner):** an unprivileged app cannot read `proc_pid_rusage` or task info for root-owned processes (tested on the owner's Mac: 211 of 595 running processes returned EPERM, including `launchd`, `logd`, `powerd`). v1 stays a single unprivileged app, with no helper. The breakdown lists every readable app with real numbers, plus one synthetic row, **"System and other users"**, whose value is the whole-system total minus the sum of the readable processes. It is labeled as an aggregate, never as a single process. Where macOS exposes a coarse CPU figure for a process we cannot read (for example the `kinfo_proc` data from `sysctl KERN_PROC_ALL`, builder to verify), the row may expand to name the biggest ones, marked approximate. Memory and power for those processes stay unavailable. A privileged helper for exact numbers is a possible v2.

**Cadence:** panel open: 1 s. Panel closed: about 5 s, and only the cheap whole-system metrics needed to pick the icon band (no process enumeration). No timers while the display sleeps or the Mac is asleep (observe sleep/wake and clear deltas on wake).

**Threading:** all sampling runs off the main thread at `utility` QoS. If a sample is still running when the next tick fires, the tick is skipped, never queued. If Vital's own sample time grows past a budget, it backs off its interval. The main thread only renders the latest snapshot.

**"Struggling" detection (for the icon band and the strip):** any of CPU at or above 90% for 10 s, memory pressure critical, swap growing quickly, or thermal state serious or critical. Enter and exit with hysteresis so the icon does not flicker. Thresholds are the builder's starting values and live in one place.

**Thermal scale (starting values, my call):** green up to 65 °C, yellow 65 to 85 °C, red above 85 °C, drawn on a 30 to 100 °C range. If temperatures are unreadable, the scale falls back to the public thermal state (nominal green, fair yellow, serious or critical red) and says so.

### Storage

- Top-level used / free comes from the capacity APIs above.
- The breakdown scan runs only while the Storage tab is open, at `background` QoS, is cancelable, and its result is cached with a timestamp. Never scanned in the background while the panel is closed.
- Categories: Applications, Documents, Desktop and Downloads, Developer (Xcode DerivedData, simulators, caches), Docker and VM images, Caches, System and Library, Other. Each category lists its largest folders, with Reveal in Finder.
- Without Full Disk Access some folders are unreadable. Show partial results labeled "partial", with a one-line link to grant access. Never block on this and never ask again after a decline.
- Local Time Machine snapshots and purgeable space are noted but never deletable in v1.

### Quit and Force Quit

- **Quit** sends a graceful terminate (for apps, via `NSRunningApplication`; for others, SIGTERM).
- **Force Quit** is offered immediately, and is emphasized if Quit did not work within 5 s.
- Every action asks for confirmation, once per action, with the app name and the helper count.
- **Protected** (shown, locked, never killable): pid 0 and 1, `kernel_task`, `launchd`, `WindowServer`, `loginwindow`, and Vital itself. Finder and Dock can be relaunched, so they are allowed with a warning.
- Processes owned by root or another user: the kill will fail with a permission error. Show the entry with the action disabled and the reason, "Needs administrator". No privilege escalation in v1. The "System and other users" aggregate row has no actions.
- **Verify after killing.** Re-check the process after about 1 s. If it is still there, report it truthfully. A process in uninterruptible kernel sleep cannot be killed by any signal: say "Stuck in the system (usually a disk or network volume). Only a restart or unplugging the device will clear it."
- "Quit all not responding" acts only on processes flagged unresponsive, and skips protected ones.
- Quitting an app with unsaved documents: graceful Quit lets the app prompt; Force Quit warns that unsaved work will be lost.

## Edge cases the builder must handle

- Fanless Macs (Air): no fan row, no error.
- Pro and Max chips with two fans; chips newer than the shipped tables (M4, M5 and later): discover sensors, and if none match, show thermal state only.
- Sensor read returns zero, NaN or an absurd value: treat as unavailable, never plot it.
- Counter wrap or negative delta after sleep/wake: drop that sample.
- Process exits between listing and inspection; pid reuse; zombie processes; processes whose paths cannot be read.
- Rosetta (x86_64) apps are grouped and labeled like any other.
- Multiple volumes: boot volume only in v1, with external volumes listed read-only if cheap.
- Low Power Mode and clamshell mode: no special casing, but no assumptions that cadence is constant.
- Notch and crowded menu bars: the icon is the only item, and the panel anchors to the icon wherever macOS places it. Fullscreen apps, multiple displays and Spaces: the panel appears on the display that holds the icon and dismisses on outside click or Escape.
- The user quits Vital's status item with Command-drag: respect it. Provide Quit in a small right-click menu, plus "Launch at login" (`SMAppService`) and "About".
- Only one instance runs.
- Accessibility: VoiceOver labels for every row and button; values are not conveyed by color alone (thermal scale also states the number and the word).
- English only in v1. Units: memory and storage in GB with base-10 for disk and base-2 for memory, matching Finder and Activity Monitor respectively.

## Verification (what "done" means)

- Pure logic (grouping, delta math, hysteresis, formatting, protected-process rules) has unit tests, with samplers behind protocols so the UI also runs on fixtures.
- Performance is measured, not assumed: `footprint` for resident memory with the panel closed and open; CPU over 5 minutes idle; sampling time per tick. Report real numbers against the 20 MB and 0.5% targets.
- Behavior under load: run a CPU burner and a memory hog, confirm Vital stays responsive, identifies the culprit, and that Quit and Force Quit work on a test process, including one that ignores SIGTERM.
- Only the owner's M3 MacBook Pro 14-inch (Mac15,3, 8 GB, one fan, 4P + 4E) is available for real-hardware testing. Other chips are covered through fixtures. A `vital --dump-sensors` command prints the sensor and fan inventory as JSON so other owners can contribute fixtures for their Macs.
- Screenshots of the panel in light and dark, with and without Reduce Transparency.

## Open source

MIT license. README with screenshots, build instructions, a sensors-and-privacy note (what private APIs are used and why, no network access, no telemetry), and credit to Stats and macmon as references. Repository name `vital`.

## Left to the builder

Internal module layout, exact sensor discovery implementation, exact thresholds and hysteresis constants (starting values above), sparkline rendering approach, animation details, DMG layout, the SVG source for the vial icon (follow mockup option 1).

## Calls I made that the owner has not confirmed

- App name is **Vital** (owner wrote "vial"; the folder and earlier discussion say Vital).
- The "Mac is struggling" strip is in v1.
- Memory target: under 20 MB closed, 40 MB hard ceiling. The open panel is allowed to use more while it is visible.
- Thermal color thresholds (65 and 85 °C) and the "struggling" thresholds.
- The Storage categories and the rule that scans run only on the Storage tab.
- Right-click menu contents and Launch at login on by default.
