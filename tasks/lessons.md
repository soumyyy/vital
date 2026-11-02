# Lessons

- Owner wants git commits with no co-author or attribution trailer.
- Do not set `contentTintColor` on a template status item image: on macOS 26/27 the icon vanishes. Draw coloured non-template images instead.
- `proc_listallpids` returns a count of pids, not bytes (unlike `proc_listpids`).
- A real process's start time can change until it has exec'd; wait before keying tests on it.
- `screencapture` returns black when the display is asleep or locked; do not read that as an app bug.
- `fts` with `FTS_XDEV` still walked `/System/Volumes/Data`; exclude it explicitly.
- When the display is asleep, verify UI offscreen: `Vital --render-panel out.png --tab=Heat` renders the SwiftUI panel to a PNG without a screen.
- An unprivileged SMC write returns kIOReturnNotPrivileged (0xe00002c1); fan control needs root. Never fake it in the UI.
- A SwiftUI `Canvas` allocated about 60 MB of GPU memory while the panel was open (90 MB to 30 MB after switching to Path shapes). Avoid Canvas and drawingGroup in the panel.
- Reading ~/Documents, Desktop, Downloads, Pictures, Music, Movies, ~/Library/Containers or iCloud triggers macOS permission prompts. Scan them only on explicit user request.
- Offscreen panel renders lie about appearance unless the NSHostingView sits in an offscreen NSWindow with `window.appearance` set and is drawn inside `performAsCurrentDrawingAppearance`. Even then, hierarchical shape styles (`.fill(.primary.opacity(x))`, `.foregroundStyle(.tertiary)` on SF Symbols) resolved to white in light mode; `Color.primary.opacity(x)` resolved correctly. Use explicit `Color` for fills and glyphs.
- A property's `didSet` does not run when it is set inside its own class's `init`, so `PanelModel.tab`'s storage side effect does not fire there.
