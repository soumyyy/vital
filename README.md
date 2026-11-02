# Vital

A lean menu bar monitor for Apple Silicon Macs. It answers one question: what is eating my Mac right now, and can I stop it?

- **CPU** as plain core counts, shown both as a share of the whole CPU and Activity Monitor style (100% = one core), smoothed over 5 seconds. **Memory** with swap and pressure, **storage**, **temperature and fans** on a green-yellow-red scale.
- **Breakdown per app**: Chrome plus its helpers is one entry, expandable to individual processes. Tabs rank by CPU, memory, storage or heat (power draw).
- **Battery** (charge, watts, time left, health, cycles), **network speed**, **idle wake-ups** per app on the Heat tab, and a flag on apps that are **keeping the Mac awake**.
- **Fans**: live speed with min and max. Changing fan speed needs a root helper that is not built; the control is disabled and says why (see `docs/superpowers/specs/2026-11-02-fan-control-helper.md`).
- **Refresh** button for a fresh sample, and a rescan on the Storage tab (about 40 s for a full scan on an SSD with 450 GB used).
- **Quit and Force Quit** with confirmation, protected system processes, and truthful results (including processes stuck in the kernel).
- **Mac is struggling** strip with "Force Quit not responding" when the machine is overloaded.
- Liquid Glass panel on macOS 26+, frosted material on macOS 14 and 15, opaque with Reduce Transparency.

macOS 14+, Apple Silicon (M1 and later). No network access, no telemetry.

## Build

```sh
Scripts/build-app.sh release     # build/Vital.app (ad-hoc signed)
open build/Vital.app
swift test                       # 83 tests
```

`Scripts/release.sh` makes a DMG. With `SIGN_IDENTITY="Developer ID Application: ..."` and `NOTARY_PROFILE=<notarytool keychain profile>` it signs and notarizes.

## Measured on a MacBook Pro 14" (M3, 8 GB)

| State | Footprint | CPU |
|---|---|---|
| Panel never opened | 12 MB (re-measured after the last changes) | about 0% (5 s cadence, no process scan) |
| Panel open | about 33 MB | about 3% at 1 s cadence |
| Panel closed again | about 25-28 MB (SwiftUI and font caches stay) | about 0% |

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
