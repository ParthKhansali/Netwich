# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[semantic versioning](https://semver.org/).

## [0.1.0] — 2026-11-07

First public release.

### Added

- Multi-link aggregation over a local SOCKS5 proxy, with weighted
  least-connections scheduling and `IP_BOUND_IF` interface pinning.
- Parallel, resumable download engine with ranged chunks, progress metadata,
  free-space checks and verification before a file is marked complete.
- Browser bridge for the Chromium and Firefox extensions, including a floating
  download HUD and `netwich://` handoff.
- Five-step onboarding that probes real permission state and deep-links to the
  matching System Settings panes.
- DMG installer with an Applications shortcut, plus separate per-browser
  extension archives and an `INSTALL.txt`.
- `netwich://tab/<name>` deep links for switching tabs from automation or other apps.
- Menu bar extra with live throughput and one-click aggregation toggle.
- `mergecli` for inspecting links, the scheduler, the system proxy and downloads.

### Changed

- Complete interface rewrite: shared glass surface language, mesh-gradient
  backdrop, custom window chrome, sidebar selection animation and staggered
  content entrances.
- Real link health and per-adapter share replace the previous always-green badges.
- System proxy configuration is snapshotted before any change and restored
  exactly on quit or after a crash.
- Elevated changes are batched into a single administrator prompt.

### Fixed

- Downloads that transferred fewer bytes than requested were reported as completed.
- Range probing could buffer an entire file into memory.
- Filenames from servers or pages could escape the download folder (path traversal).
- The bridge reflected any `Origin` and granted wildcard CORS, letting any website
  read the download list and cancel transfers.
- Idle proxy connections were closed after 15 seconds, breaking SSH, WebSockets
  and paused transfers.
- Throughput was double-counted when the parallel engine ran through the proxy.
- The benchmark fabricated a 250 KB/s floor and silently enabled the system proxy.
- `IP_BOUND_IF` failures were ignored, so aggregation could silently use one link.

### Performance

- Telemetry timer now carries a tolerance and runs in the common run-loop mode,
  halving idle CPU in measurement (0.7–0.8% → 0.3–0.4%).
- Link rows are only published when their values actually change, avoiding a
  redundant view invalidation every second.
- Per-flow relay buffers reduced from 64 KiB to 32 KiB per direction.
- Extension bundles are minified; screenshots and demo assets are size-optimised.
