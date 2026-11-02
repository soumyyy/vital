# Vital

A lean menu bar monitor for Apple Silicon Macs. It answers one question: what is eating my Mac right now, and can I stop it?

Download the signed, notarized app from [GitHub Releases](https://github.com/soumyyy/vital/releases/latest). See [installation and removal](docs/INSTALL.md).

For distribution, see the [release runbook](docs/RELEASING.md).

- **One headline**: a single sentence says whether your Mac is fine and, if not, which app is the cause, with a Quit button. When apps stop responding it turns red with Force Quit.
- **Four vitals, one number each**: CPU, memory, storage and heat. Colour appears only when something needs attention. Tap a vital to list the apps using the most of it (folders, for storage).
- **Breakdown per app**: Chrome plus its helpers is one entry, expandable to its processes (merged by name) with Quit and Force Quit. CPU is a share of the whole CPU, smoothed over 5 seconds; hover a process for the Activity Monitor figure (100% = one core).
- **Details on demand**: each vital has a Details section, closed by default: performance and efficiency cores; memory pressure, swap and memory read back from disk; free space and which apps read and write the disk; temperatures, battery (charge, watts, time left, health, cycles), network speed and apps keeping the Mac awake. Idle wake-ups show in an expanded app on Heat.
- **Overview**: the grid button in the pill shows CPU, memory, disk, network and heat graphs for the last five minutes, storage capacity and the battery.
- **Updates**: three-dot menu → **Update Software…** (also in the right-click menu and the About window). Vital checks the latest GitHub release, shows what changed, downloads the zip, checks its SHA-256 and code signature (same developer as the running copy), replaces itself and restarts. It never checks on its own.
- **Fans**: live speed and manual control at the top of Heat. Click **Turn on**, then approve Vital in System Settings → General → Login Items & Extensions. The bundled root helper clamps speeds to hardware limits and resets to Auto on disconnect, sleep, high thermal pressure, or a missed heartbeat. Manual mode is temporary and is not saved across launches. The helper records ownership before changing hardware and recovers Auto after a helper restart. Direct `F0Md` fan control is supported; Macs that require `Ftst` unlocking or Intel `FS!` control show an error.
- **Refresh** button for fresh readings, and a rescan when Storage is selected (about 40 s for a full scan on an SSD with 450 GB used).
- **Quit and Force Quit** with confirmation, protected system processes, and truthful results (including processes stuck in the kernel).
- The app-list panel keeps a consistent height; Overview fits its content and available screen space.
- Liquid Glass panel on macOS 26+, frosted material on macOS 14 and 15, opaque with Reduce Transparency.

macOS 14+, Apple Silicon (M1 and later). Physical validation currently covers an M3 MacBook Pro on macOS 27; broader hardware and older macOS UI validation remains in progress. No telemetry. Update checks start only when you choose **Update Software**. Downloading an approved update also retrieves its release archive.

## Build

For normal use, launch the installed `/Applications/Vital.app`. The commands below create a development copy; avoid running both copies at once.

```sh
Scripts/build-app.sh release     # build/Vital.app (local development signing)
open build/Vital.app
swift test
```

`Scripts/release.sh` writes distribution artifacts to `build/release/`, separately from the running development app. Use a Developer ID Application identity and a validated `notarytool` Keychain profile:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=vital-notary Scripts/release.sh
```

The script signs the app and helper with hardened runtime and secure timestamps, notarizes and staples the app, then signs, notarizes, and staples the DMG. It verifies Gatekeeper acceptance and creates a ZIP for the updater, `SHA256SUMS`, and a checksum line in `release-notes.txt`. Publishing remains a separate step. `SKIP_BUILD=1` resumes packaging and notarization of an existing signed release app.

## Update Vital

In the app, choose **Update Software…**, review the version and release notes, then click **Update and Restart**. Checks and downloads happen only when you request them. Keep Vital in a writable Applications folder; if the folder cannot be replaced, the app explains how to update using the release download instead.

An update verifies the archive checksum when supplied, the app version and identity, and an Apple-issued Developer ID signature from the same team. It ends manual fan control before replacing the bundle. Only previously enabled fan control is restored. If macOS requires approval again, Heat shows **Approve control** and links to System Settings. Protected folder scans still ask only when you explicitly choose Scan; launch at login remains opt-in.

To publish a new update, choose a higher version and build number, run the signed/notarized release script, then upload both the generated ZIP and DMG to a GitHub Release tagged `v<version>` in the chosen public release repository. Set `UpdateFeed.defaultURL` to that repository before building. Include the ZIP checksum line from `release-notes.txt` in the release body. The in-app updater consumes the ZIP; the DMG is for manual installation. Release builds below `build/release/` are not published automatically. The update feed uses the public `soumyyy/vital` repository without credentials. Never embed a GitHub token in the app.

Homebrew-managed installations can instead use `brew upgrade --cask <owner>/tap/vital` once the tap is published. Each cask release must point to the matching DMG version and checksum.

## Enable fan control

1. Build. `Scripts/build-app.sh` signs with your Apple Development identity automatically, because macOS pins the helper to the app's signature. An ad hoc build (no identity) runs but cannot connect to the helper. To pick one yourself:

```sh
SIGN_IDENTITY="Apple Development: Your Name (ID)" Scripts/build-app.sh release
```

2. Open `build/Vital.app`, select Heat, and click **Turn on**.
3. Approve Vital under **System Settings → General → Login Items & Extensions → Background App Activity**.
4. Switch on manual speed and move the slider to set a target. The card shows current RPM separately from the target. Switch it off to return control to macOS.

The slider becomes available after the helper connects. **Reconnect** retries a failed connection. After rebuilding with a different signature, run `build/Vital.app/Contents/MacOS/Vital --refresh-fan-helper` once. Closing the panel keeps a manual target active; quitting Vital restores Auto.

For local development, quit Vital and unregister the helper before replacing an existing signed bundle:

```sh
build/Vital.app/Contents/MacOS/Vital --unregister-fan-helper
```

Keep one registered Vital bundle per bundle identifier. Stale Launch Services records for deleted development builds can prevent the helper from launching. A valid signature alone does not prove the helper can run.

`Vital --fan-helper-status` prints helper status and live fan readings. `Vital --probe-fan-control` explicitly tests a short 4,000 RPM request through the app controller and then restores Auto. Avoid another fan-control tool during these checks.

## Measured on a MacBook Pro 14" (M3, 8 GB)

| State | Footprint | CPU |
|---|---|---|
| Panel never opened | 12 MB | about 0.02% (wakes every 15 s when calm, every 5 s when busy) |
| Panel open | about 27 MB | about 1.4% (updates every 2 s) |
| Panel closed again | about 26 MB | about 0% |

The 26 MB after closing is the floor for SwiftUI in this process: an empty panel alone leaves 17 MB, and the panel content the rest. Going lower would take a separate short-lived UI process.

## How it works

- Direct Mach, libproc and sysctl calls. It never shells out to `ps` or `top`.
- Measuring runs off the main thread at utility priority, skips overlapping ticks, and backs off if it gets expensive.
- Permissions: Vital asks for none by default. The storage scan never opens Documents, Desktop, Downloads, Photos, Music, Movies, iCloud Drive or other apps' data. Each personal folder has a Scan button; macOS asks only if you tap it. Full Disk Access is optional.
- macOS does not let an unprivileged app read memory or exact CPU for root-owned processes, so those appear as one approximate **System and other users** row.
- Temperatures come from the private IOHID sensor client and fans from the SMC (the same data `powermetrics` reads). These private APIs are why Vital is not on the Mac App Store and is not sandboxed. If a sensor is missing it shows "n/a", never an invented number.
- `Vital --dump-sensors` prints the sensor and fan inventory as JSON. Please attach it when reporting an unsupported Mac.
- `Vital --probe` and `Vital --probe-storage` print live samples.

## Limits

- A process stuck in uninterruptible kernel sleep (usually a hung disk or network volume) cannot be killed by any signal. Vital tells you so.
- macOS has no per-app temperature. The Heat tab ranks apps by power draw.
- Intel Macs, alerts, deleting files, and a live menu bar readout are not in v1.

## Credits

Sensor approach informed by [Stats](https://github.com/exelban/Stats) and [macmon](https://github.com/vladkens/macmon) (both MIT).

License: MIT.
