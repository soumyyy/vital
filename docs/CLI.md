# Command line

`vital` reports on your Mac as text or JSON. It is read-only: it never quits an app or changes a fan, so it is safe to hand to scripts and AI agents.

## Install

| How you installed Vital | Command line |
|---|---|
| Homebrew | `vital` is linked automatically |
| npm | `npm install -g vital-mac` |
| DMG | `sudo ln -s /Applications/Vital.app/Contents/MacOS/Vital /usr/local/bin/vital` |

Any other name works too, but the binary must be started as `vital` (lowercase) or with a command as its first argument, which is what tells it to answer in the terminal instead of opening the menu bar app.

## Commands

```
vital status [--json]
vital apps [--by cpu|memory|power|disk] [-n 10] [--processes] [--json]
vital history [cpu|memory|heat|down|up] [--range 1h] [--json]
vital help | version
```

`status` and `apps` take a live reading, which needs about a second. They work whether or not the menu bar app is running.

`apps` groups every helper process under its app, so "Google Chrome" is one row with its process count. CPU is a share of the whole Mac. `--processes` adds each app's processes (JSON only).

`history` reads the 24 hour record the menu bar app keeps in `~/Library/Application Support/Vital/history-24h.json`: one-minute averages of CPU, memory, heat and network. It has gaps while the Mac sleeps or Vital is not running. `--range` accepts 5m up to 24h, such as `90m` or `6h`.

## JSON

`--json` prints one object. `schema` is its version and changes only when a field is removed or changes meaning. A missing field means the value is not available on this Mac (no battery, no temperature sensor).

Units are in the name: `...Bytes`, `...BytesPerSecond`, `...Celsius`, `...Percent`.

```json
{
  "schema": 1,
  "summary": { "level": "good", "title": "Your Mac is running well" },
  "cpu": { "percent": 18.6, "cores": 8 },
  "memory": { "percent": 75.3, "usedBytes": 6442450944, "totalBytes": 8589934592, "pressure": "elevated" },
  "heat": { "state": "nominal", "hottestCelsius": 42, "fans": [{ "index": 0, "rpm": 0 }] },
  "notResponding": []
}
```

## For AI agents

Tell your agent to run `vital status --json` first and `vital apps --by memory -n 5 --json` when something is slow. Exit status is 0 on success, 1 on failure and 2 for a usage error; errors go to standard error. Nothing here can change the system, so no confirmation step is needed.
