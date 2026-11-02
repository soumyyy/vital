# Lessons

- Owner wants git commits with no co-author or attribution trailer.
- Do not set `contentTintColor` on a template status item image: on macOS 26/27 the icon vanishes. Draw coloured non-template images instead.
- `proc_listallpids` returns a count of pids, not bytes (unlike `proc_listpids`).
- A real process's start time can change until it has exec'd; wait before keying tests on it.
- `screencapture` returns black when the display is asleep or locked; do not read that as an app bug.
- `fts` with `FTS_XDEV` still walked `/System/Volumes/Data`; exclude it explicitly.
- When the display is asleep, verify UI offscreen: `Vital --render-panel out.png --tab=Heat` renders the SwiftUI panel to a PNG without a screen.
- An unprivileged SMC write returns kIOReturnNotPrivileged (0xe00002c1); fan control needs root. Never fake it in the UI.
