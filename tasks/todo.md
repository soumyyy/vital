# Vital: todo

Goal: ship Vital v1 per docs/superpowers/specs/2026-11-02-vital-design.md, following docs/superpowers/plans/2026-11-02-vital.md. Done when the 11 tasks are checked and measured numbers (footprint, idle CPU) are recorded below.

- [x] 1 Scaffold, repo, bare menu bar app
- [x] 2 Models, formatting, load bands
- [x] 3 CPU and memory samplers
- [x] 4 Process sampler, grouping, protection
- [x] 5 Storage
- [x] 6 Thermal and fans
- [x] 7 Process actions
- [x] 8 Sampler orchestration
- [x] 9 UI
- [x] 10 Icon and packaging
- [x] 11 Verification and docs

## Review
Built and pushed to the private repo soumyyy/vital. 52 unit and integration tests pass.

Measured (M3 MacBook Pro, 8 GB): 12 MB footprint and about 0% CPU with the panel never opened; about 90 MB and 3% CPU while open; about 28 MB after closing. The closed-after-use figure misses the 20 MB goal because SwiftUI, AppKit and Core Animation keep caches. Fix if it matters: run the panel UI in a short-lived helper process.

Not done or not verified:
- No Developer ID certificate on this Mac (only Apple Development), so notarization is scripted but untried.
- Only this M3 was tested. Other chips rely on runtime sensor discovery and `--dump-sensors` fixtures.
- Quit and Force Quit are covered by tests against real spawned processes, but the panel buttons were not clicked end to end.
- macOS 14 and 15 fallback (frosted material) was not run, only macOS 27.
- Heavy-load test (CPU burner and memory hog against the live UI) was not run.
