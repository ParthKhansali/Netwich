# Contributing to Netwich

Thanks for taking a look. Netwich is a native macOS app plus a small browser
extension, so a change usually touches one of three places:

```
Sources/MergeKit/   the engine (proxy, scheduler, downloads, bridge, system proxy)
App/                SwiftUI interface
extension/          Chromium + Firefox builds and their shared TypeScript source
```

## Getting set up

```bash
brew install xcodegen
swift test
./Scripts/build.sh
open build/Netwich.app
```

You need macOS 14+ and Apple Silicon. Xcode 16 or newer is required because the
backdrop uses `MeshGradient` (macOS 15) behind an availability check.

## Before opening a pull request

1. `swift test` — all hermetic tests must pass. Run `NETWICH_INTEGRATION=1 swift test` when
you touched proxies, routes or the download transport; those six tests need real adapters
and internet access and are skipped on CI.
2. `./Scripts/package.sh` if you touched packaging, entitlements or the extension
   build; it must produce a DMG and both ZIPs.
3. Keep the engine free of UI imports and the UI free of subprocess work on the
   main thread. Anything that shells out belongs behind `ProcessRunner` and off
   the main actor.
4. If you change the extension's TypeScript, run `./Scripts/build.sh`, which
   re-bundles into `extension/chrome` and mirrors the output into `extension/firefox`.

## Security-sensitive areas

Changes to `BrowserBridge.swift`, `SystemProxyManager.swift` or
`DownloadEngine.swift` get extra scrutiny:

- The bridge must never grant CORS to a website origin. Extension schemes only.
- Filenames from the network are untrusted. Sanitise before joining a path.
- System proxy state must be snapshotted before it is changed and restored exactly.
- Do not add a `sudo` call. Elevation goes through one batched `osascript` prompt.

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md)
rather than in a public issue.

## Style

Match the surrounding code. No new dependencies without a reason; the app ships
as a single binary and should stay that way.

By contributing you agree that your work is licensed under the MIT License.
