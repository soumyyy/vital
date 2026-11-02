# Fan control

Vital can set a manual fan speed on MacBooks with fans. It is optional and off until you turn it on.

## Using it

1. Install the signed release in `/Applications`. Development builds cannot register the helper.
2. Open **Heat** and click **Turn on**. Approve Vital in **System Settings → General → Login Items & Extensions**.
3. Switch on manual speed and move the slider. The card shows the current speed separately from your target. Switch it off to return the fan to Auto.

Manual speed is temporary: it is not saved across launches, and quitting Vital restores Auto. Fanless Macs show no fan card.

## How it is built

- `Sources/Vital/FanClient.swift` owns one authenticated XPC connection, sends one request at a time and renews the helper's lease every three seconds while a manual speed is set.
- `Sources/VitalFanHelper/main.swift` is a root launch daemon registered with `SMAppService.daemon`. It serialises hardware writes and handles system sleep.
- `Sources/VitalCore/FanSession.swift` validates each request, clamps it to the fan's minimum and maximum, and verifies the mode and target after writing.
- `Sources/VitalFanIPC/FanService.swift` defines the two XPC operations (set a fan, read status). Each side pins the other's code signature.

The helper accepts a fan index and a number, never an SMC key. It supports direct `F<n>Md` and `F<n>Tg` control. It does not use `Ftst` unlocking or Intel `FS!` bits, so Macs that need those show an error.

## Safety

The helper restores each fan's previous automatic mode on disconnect, sleep, serious or critical thermal pressure, a heartbeat gap over 15 seconds, a timer gap over 10 seconds, or shutdown. It writes the original mode to `/var/db/dev.soumya.vital` before it changes hardware and recovers from that record after a restart. If that record cannot be read or written, manual control is refused. A failed return to Auto is retried every two seconds.

A helper crash or firmware that refuses Auto cannot be fully guarded against. If a fan seems stuck, restart the Mac. Another fan tool can interfere with mode changes.

## Development

```sh
Vital --fan-helper-status        # helper status and live fan readings
Vital --probe-fan-control        # request 4,000 rpm briefly, then verify Auto is restored
Vital --refresh-fan-helper       # unregister and register again after a signature change
Vital --unregister-fan-helper    # remove the helper registration
```

Normal launch never changes fan speed. Avoid running another fan tool during these checks.

macOS ties the helper to the app's signature. After changing signing identity, run `--refresh-fan-helper` once. Stale records for deleted development builds can stop the helper from launching; remove them rather than resetting all registrations.
