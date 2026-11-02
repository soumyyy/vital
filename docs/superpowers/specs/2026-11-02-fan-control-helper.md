# Fan control: findings and design for a privileged helper

Status: not built. Needs the owner's decision.

## Finding (tested on the owner's M3 MacBook Pro, macOS 27)

- Reading fans works without privileges: `FNum`, `F0Ac` (actual), `F0Mn`, `F0Mx` are readable. This Mac has one fan, 0 rpm when idle, minimum 2317, maximum 6800.
- The keys needed for control exist: `F0Md` (mode, ui8, writable flag set) and `F0Tg` (target, float, writable flag set).
- Writing is refused to a normal app. A write of the fan's own current value to `F0Tg` returned `kIOReturnNotPrivileged` (0xe00002c1). Control therefore needs root.
- The `Ftst` unlock key that some Apple Silicon fan tools rely on does not exist on this Mac, so the exact method (set `F0Md` to manual, write `F0Tg`) must be verified on real hardware as root, one fan and one value at a time.

## Why this is a decision for the owner

The v1 design deliberately has no privileged helper. Fan control cannot work without one. A helper is a root process that writes to the SMC, so a bug can overheat a Mac or leave a fan stuck, and a flaw in its interface lets other local programs do the same.

## Proposed design

- A launch daemon registered through `SMAppService.daemon`. It requires the app and daemon to be signed with a Developer ID Application certificate (this Mac currently has only Apple Development certificates) and the user to approve it once in System Settings, Login Items.
- XPC interface with three calls only: `setManual(fan, rpm)`, `setAuto(fan)`, `status()`. The daemon validates the caller's code signature (team ID and bundle id) on every connection.
- Hard safety rules in the daemon, not in the app:
  - clamp every target to the fan's own `F0Mn`..`F0Mx` (`FanSafety.target` is the app-side copy of this rule);
  - revert to automatic on: app quit or crash (XPC invalidation), sleep, thermal state serious or critical, a 30 s heartbeat timeout, and daemon shutdown;
  - rate-limit changes; refuse manual mode while the thermal state is serious or critical;
  - never write anything except `F0Md` and `F0Tg`-style fan keys.
- Opt-in in the panel: the Fans card shows Auto and Manual. Manual stays disabled, with the reason shown, until the helper is installed and approved.

## What exists today

- `FanController` protocol, `NoopFanController` (reports unavailable, throws on any change) and `FanSafety.target` in `VitalCore`.
- A Fans card on the Heat tab showing live rpm, minimum and maximum, with Auto and Manual disabled and the reason shown.
