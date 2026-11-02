# Vital

A lean menu bar monitor for Apple Silicon Macs. It answers one question: what is eating my Mac right now, and can I stop it?

- **CPU** as plain core counts, shown both as a share of the whole CPU and Activity Monitor style (100% = one core), smoothed over 5 seconds. **Memory** with swap and pressure, **storage**, **temperature and fans** on a green-yellow-red scale.
- **Breakdown per app**: Chrome plus its helpers is one entry, expandable to individual processes. Tabs rank by CPU, memory, storage or heat (power draw).
- **Battery** (charge, watts, time left, health, cycles), **network speed**, **idle wake-ups** per app on the Heat tab, and a flag on apps that are **keeping the Mac awake**.
- **Disk** tab: which apps read and write the most, how much the Mac is reading back from disk because memory is short, and bytes written since launch.
- **Fans**: live speed, a manual RPM slider, and an Auto button on the Heat tab. Click **Enable control**, then approve Vital in System Settings → General → Login Items & Extensions. The bundled root helper clamps speeds to hardware limits and resets to Auto on disconnect, sleep, high thermal pressure, or a missed heartbeat. Manual mode is temporary and is not saved across launches. Direct `F0Md` fan control is supported; Macs that require `Ftst` unlocking or Intel `FS!` control show an error.
- **Refresh** button for a fresh sample, and a rescan on the Storage tab (about 40 s for a full scan on an SSD with 450 GB used).
- **Quit and Force Quit** with confirmation, protected system processes, and truthful results (including processes stuck in the kernel).
- **Mac is struggling** strip with "Force Quit not responding" when the machine is overloaded.
- Liquid Glass panel on macOS 26+, frosted material on macOS 14 and 15, opaque with Reduce Transparency.

macOS 14+, Apple Silicon (M1 and later). No network access, no telemetry.

## Build

```sh
Scripts/build-app.sh release     # build/Vital.app (ad-hoc signed)
open build/Vital.app
swift test                       # 95 tests
```

`Scripts/release.sh` makes a DMG. With `SIGN_IDENTITY="Developer ID Application: ..."` and `NOTARY_PROFILE=<notarytool keychain profile>` it signs and notarizes.

## Measured on a MacBook Pro 14" (M3, 8 GB)

| State | Footprint | CPU |
|---|---|---|
| Panel never opened | 12 MB | about 0.02% (wakes every 15 s when calm, every 5 s when busy) |
| Panel open | about 33 MB | about 1.8% (updates every 2 s) |
| Panel closed again | about 28 MB | about 0% |

The 28 MB after closing is the floor for SwiftUI in this process: an empty panel alone leaves 17 MB, and the panel content the rest. Going lower would take a separate short-lived UI process.

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
