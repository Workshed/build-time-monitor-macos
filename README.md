# Build Time Monitor

A macOS 26 menu bar app that charts the Xcode build times recorded by
[xcode-build-time-recorder](https://github.com/Workshed/xcode-build-time-recorder).

- Click the hammer in the menu bar for a glanceable popover. It shows average incremental and full
  build times, build count, time spent building and failures, plus an interactive chart with one
  colour per project (hover a dot for scheme, branch@commit, config/SDK and Xcode version).
- 24h/7d plot every build with a rolling-median trend line. 30d/1y plot daily/weekly medians.
- "Open Dashboard" opens a window with per-project drill-down, a duration histogram,
  per-scheme median/p90 stats and a sortable table of every build.
- The CSV is watched and the app updates as soon as a build is recorded.

## Building

```sh
xcodegen generate
open BuildTimeMonitor.xcodeproj   # or:
xcodebuild -scheme BuildTimeMonitor -destination 'platform=macOS' test
```

Set the CSV path in Settings (gear icon in the popover). For sample data:

```sh
python3 Scripts/generate_sample_csv.py ~/build_times_sample.csv
```

### Debug launch flags

- `-PreviewPopover YES` shows the popover content in light and dark windows.
- `-PreviewHover YES` pins a hovered point.
- `-SnapshotDir <dir>` writes PNGs of the preview windows.
- `-csvPath <path>` overrides the configured CSV without saving it.

Liquid Glass doesn't render in snapshots.
