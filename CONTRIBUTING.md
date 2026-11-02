# Contributing

Thanks for helping. Vital is a small, deliberately lean app, so changes that keep it light and honest are the easiest to merge.

## Build and test

Requires Xcode with Swift 6 on an Apple Silicon Mac running macOS 14 or later.

```sh
swift test                         # unit tests (no hardware needed)
Scripts/build-app.sh release       # builds build/Vital.app
open build/Vital.app
```

`build-app.sh` signs with your Apple Development identity when it finds one, and ad hoc otherwise. Everything except fan control works ad hoc. Fan control needs a signed build installed in `/Applications`; see [docs/FAN-CONTROL.md](docs/FAN-CONTROL.md). Keep only one registered copy of Vital per bundle identifier.

Useful checks that run without the UI:

```sh
build/Vital.app/Contents/MacOS/Vital --probe            # live CPU, memory and process samples
build/Vital.app/Contents/MacOS/Vital --dump-sensors     # sensor and fan inventory as JSON
build/Vital.app/Contents/MacOS/Vital --render-panel out.png [--tab=Heat] [--overview] [--appearance=light|dark]
```

`--render-panel` draws the panel offscreen, which helps when no display is available. It does not draw Liquid Glass, and dark mode text can render dark.

## Guidelines

- Keep the footprint small: no third-party dependencies, no `Canvas` or `drawingGroup` in the panel (measured 60 MB of GPU memory), no shelling out to measure.
- Never show an invented number. A missing sensor is "n/a".
- Logic that can be tested without hardware belongs in `VitalCore` with a Swift Testing test. Sampling and fan code take their hardware behind a protocol so tests can fake it.
- Fan control must fail safe: any doubt returns the fans to Auto.
- No network access other than the user-initiated update check, and no telemetry.
- Run `swift test` before opening a pull request, and describe how you checked the change on a real Mac.

## Releasing

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md) and [docs/TESTING.md](docs/TESTING.md).
