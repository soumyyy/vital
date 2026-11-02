# Fan control helper

Vital provides a manual RPM slider and a manual/Auto switch at the top of the Heat tab, with a single Turn on button until the helper is approved. Manual targets last for the app session and are not saved across launches.

## Components

- `Sources/Vital/FanClient.swift` owns the authenticated XPC connection, applies one request at a time, and renews the manual-control lease every three seconds. Controls remain disabled until a status reply confirms the connection. Timeouts and old connection callbacks cannot update a replacement connection.
- `Sources/Vital/Views/FanCard.swift` shows current RPM separately from the acknowledged manual target, plus connection, progress, and error states.
- `Sources/VitalFanHelper/main.swift` runs as a root launch daemon registered through `SMAppService.daemon`. It serializes writes, handles system sleep notifications, and restores Auto on connection invalidation or SIGTERM.
- `Sources/VitalCore/FanSession.swift` validates requests, clamps targets to hardware limits, and verifies mode and target after the complete write transaction. This allows firmware to latch manual mode when the target is written.
- `Sources/VitalFanIPC/FanService.swift` defines the two XPC operations: set a fan target or Auto, and read session status. Each peer pins the exact signed executable bundled beside it. XPC enforces the requirement on incoming messages.

The helper accepts a fan index and numeric target, never arbitrary SMC keys, paths, or commands. It supports direct `F<n>Md` and `F<n>Tg` control. It does not unlock `Ftst` or modify Intel `FS!` mode bits.

## Safety behavior

Manual requests require a finite target and valid hardware limits. They are clamped to the fan's minimum and maximum. Invalid fan counts, missing keys, unsupported formats, and requests during serious or critical thermal pressure are rejected.

The helper restores the fan's prior automatic mode, either `0` or `3`, on disconnect, sleep, high thermal pressure, a heartbeat gap longer than 15 seconds, a timer gap longer than 10 seconds, or normal helper shutdown. Failed resets remain pending and retry every two seconds. A manual request cannot clear a pending reset failure.

Auto is verified by reading the mode back before clearing the manual state. Helper crashes or firmware refusing Auto cannot guarantee restoration. A persistent reset error calls for a restart. Another fan-control tool can interfere with mode changes.

## Signing and registration

Both executables must have valid signatures, and macOS must approve the daemon. Apple Development signing was verified for local use on the owner's Mac. Developer ID signing and notarization are the distribution workflow.

Registration may initially report `notFound`. A registration attempt may return Operation not permitted while still reaching `requiresApproval`; the app checks the resulting status and opens System Settings in that case.

The helper resolves its executable path through dyld because launchd may supply a relative `argv[0]`. Launch Services must resolve the current bundle. Deleted builds with the same bundle identifier caused launch-constraint failures during testing; removing those stale registration records restored launch. Rebuilds must unregister the old helper before replacing the bundle.

## Verification

On the owner's M3 MacBook Pro with macOS 27, the fan reports a minimum of 2,317 RPM and a maximum of 6,800 RPM. A signed app and helper successfully applied 6,800 RPM through FanClient, and the measured fan speed reached approximately 6,800–6,900 RPM. Disconnect restored mode `0` and the system target.

Unit tests cover limits, invalid inputs and counts, rate limiting, complete-transaction verification, ignored writes, rollback, heartbeat expiry, sleep gaps, thermal pressure, and retrying failed resets. Live sleep and helper-crash behavior remain separate hardware verification tasks.

`Vital --probe-fan-control` performs a bounded 4,000 RPM check through the same app controller, reads the actual RPM, restores Auto, and verifies the mode. Normal app launch never runs this check.
