# Security

## Reporting a vulnerability

Please report security problems privately through GitHub: **Security → Report a vulnerability** on this repository. Do not open a public issue for something exploitable. You can expect an acknowledgement within a few days.

## Scope worth knowing

- **Fan helper.** Fan control runs a small root helper registered through `SMAppService`. It accepts only a fan index and a speed, never SMC keys, paths or commands. Both sides pin the other's code signature, and the helper restores Auto on disconnect, sleep, high thermal pressure, a missed heartbeat or a restart. See [docs/FAN-CONTROL.md](docs/FAN-CONTROL.md).
- **Updater.** Checks and downloads start only when the user asks. An update must match its published checksum, carry the announced version and bundle identifier, and be signed by the same Apple developer team as the running copy before it replaces the app.
- **Private APIs.** Temperatures and fans use private IOHID and SMC interfaces. They are read-only except for the fan helper.
- **Data.** Vital stores nothing about you and sends nothing anywhere.

## Supported versions

Only the latest release receives fixes.
