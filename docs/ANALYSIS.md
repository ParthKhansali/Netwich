# Netwich engineering audit

Reviewed: the Swift package (`Sources/MergeKit`), the app layer (`App/`), the system
extension target (`Proxy/`), and both browser builds (`extension/`).

Each finding below lists what was wrong, why it mattered, and what changed. Items are
ordered by real-world impact, not by how interesting they were to find.

---

## P0 — could corrupt data, lose user settings, or be exploited

### 1. Truncated downloads were reported as successful
`downloadChunk` retried four times and then returned `downloadedBytes` **without checking
that the chunk was complete**. `startDownload` then called `finalizeDownload`, renamed the
part file, and marked the item `.completed`. A server that closed early, a flaky tether, or
a proxy drop produced a short file with a green "Done" badge and no way to tell.
`downloadSingle` had the same shape: when the retry loop exhausted `maxAttempts`, it fell
through to finalize.

**Fixed:** `downloadChunk` throws `DownloadError.incompleteTransfer` when the byte count is
short, so the parallel path falls back to a single stream; `finalizeDownload` re-reads the
file size from disk and refuses to promote a part file whose size ≠ `Content-Length`.

### 2. The probe could load an entire file into memory
Range-support detection used `session.data(for:)`, which buffers the whole response body.
Against a server that ignores `Range: bytes=0-0` — common on CDNs and file lockers — that
reads the full file into RAM before the download even starts.

**Fixed:** probes now use `URLSession.bytes(for:)` and read only the response headers. The
body stream is never consumed, and releasing it cancels the transfer.

### 3. Path traversal from untrusted filenames
`DownloadItem.filename` came from `url.lastPathComponent`, `Content-Disposition`, or the
browser extension's `fileName` field, and was passed straight to
`destinationFolder.appendingPathComponent(filename)`. A hostile server or page could supply
`../../../../Library/LaunchAgents/x.plist` and write outside the download folder.

**Fixed:** `DownloadItem.sanitizeName` reduces every name to one path component, rejects
`.`/`..`/empty, strips NUL, and truncates to 200 characters. Covered by tests in
`Tests/MergeKitTests/SecurityTests.swift`.

### 4. Any website could read the download list and control the app
`BrowserBridgeServer` ran an unauthenticated HTTP server on `127.0.0.1:19288` and echoed
**any** `Origin` header back in `Access-Control-Allow-Origin`. A page the user visited
could `fetch("http://127.0.0.1:19288/status")`, read every filename plus the absolute save
path, then POST to `/downloads/cancel`, `/downloads/clear`, or `/add` with an arbitrary URL.
The `/open` endpoint could also be triggered from a page.

**Fixed:** a strict origin policy — extension schemes (`chrome-extension://`,
`moz-extension://`, `safari-web-extension://`) are accepted; any `http(s)` origin is
rejected with `403` and receives no CORS grant. Requests without an `Origin` (native
clients, `netwich://` handoffs, the test suite) are allowed. CORS is never wildcarded.
The parser now reads until the header terminator and then exactly `Content-Length` bytes,
so large cookie payloads are not truncated mid-JSON; pending offers are capped; responses
loop on `send` instead of assuming one write. Five regression tests cover this.

### 5. Enabling aggregation silently destroyed an existing proxy configuration
`SystemProxyManager` turned the SOCKS proxy on for every service and then "restored" it by
turning it off. A user with a corporate SOCKS proxy permanently lost it. State was a bare
`[String]`, so there was nothing to restore *to*.

**Fixed:** every service's `(server, port, enabled)` is snapshotted and written **before**
the first mutation; disable restores that snapshot exactly. The state file is versioned.
`recoverStaleState()` repairs a crash using the snapshot only.

Related: the old `emergencyDisableAll()` ran at every launch and at exit, and disabled any
service whose SOCKS proxy pointed at *any* `127.0.0.1` address — including a proxy Netwich
never set. It is now port-scoped (`127.0.0.1:1080`), runs only on the terminate path, and
`SystemProxyManager.init` no longer spawns processes at all.

### 6. Aggregation could never work for a non-admin user, with no explanation
`networksetup` write commands require admin rights and return
`** Error: Command requires admin privileges` (exit 14) otherwise. The app swallowed the
failure and showed a generic message. There was also no path to elevate.

**Fixed:** `PrivilegedShell` retries only the commands that actually failed through a single
`osascript … with administrator privileges` call, which produces one native password sheet
for the whole batch. Cancelling surfaces
`SetupError.permissionDenied`, which onboarding explains. Argument quoting is POSIX-safe.

References: [networksetup requires admin](https://ss64.com/mac/networksetup.html),
[the same failure reported against a commercial client](https://github.com/chen08209/FlClash/issues/2425).

---

## P1 — correctness, responsiveness and CPU

### 7. Launch blocked on synchronous subprocess work
`AppState.init` called `systemProxy.disableProxy()`, which listed services and spawned two
`networksetup` processes per service — on the main thread, before the first frame. That is
easily 600 ms–2 s of beachball, and on some machines it could surface an auth prompt during
launch.

**Fixed:** `init` only wires objects. `bootstrap()` (called from the view's `.task`) starts
the bridge and proxy, then does stale-proxy recovery on a utility queue.

### 8. Every connection idle for 15 seconds was killed
`LocalProxyServer.pump` polled with a 15 s timeout and `break` on timeout, treating a quiet
connection as finished. That breaks SSH sessions, WebSockets, long-polling, and any download
that pauses. It also set `SO_RCVTIMEO`/`SO_SNDTIMEO` to 15 s on outbound sockets.

**Fixed:** idle polls continue; only a real stop request ends them. Socket timeouts removed.
`stop()` now shuts down every live socket so pumps unblock immediately instead of waiting for
a timeout.

### 9. `IP_BOUND_IF` failures were ignored — aggregation could silently do nothing
The return value of `setsockopt(…, IP_BOUND_IF, …)` was discarded. If binding failed, the
connection went out over the default route and the user saw a working (but not aggregated)
download with no diagnostic.

**Fixed:** the bind result is checked; failure closes the socket and tries the next candidate,
and the error is recorded per link.

### 10. Classic `waitUntilExit` + pipe deadlock
Three places ran a process, called `waitUntilExit()`, and only then drained the pipe. That
hangs forever when output exceeds the pipe buffer.

**Fixed:** `ProcessRunner` drains stdout/stderr concurrently, then waits, with a watchdog that
terminates a process that sits on a prompt.

### 11. `sudo route` at launch
`ScopedRouteManager` tried `sudo -n route add` on every sync. For a normal user that is a
failed authorization every time, and with `-n` removed it would prompt.

**Fixed:** scoped-route mutation only runs when already `euid == 0`; otherwise the system's own
routes are left alone and `IP_BOUND_IF` uses them.

### 12. Throughput was double-counted, and health was faked
- The meter added `downloads.reduce(speed)` to the proxy's byte delta, but downloads route
  *through* the proxy — the same bytes were counted twice.
- `LinkRow.tier` was hardcoded to `.up`, so the UI always showed "Healthy/Stacked" even for a
  link the scheduler had taken down.
- `totalBytesRoutedToday` was never reset, despite the name.

**Fixed:** when aggregation is on the meter takes `max(proxyDelta, engineSpeed)` (never the
sum); rows merge the scheduler's live tier/weight; the daily counter persists with a date key.

### 13. The benchmark invented numbers and changed system settings
`runBenchmark` called `setOn(true)`, silently enabling the system proxy. Both measurement
paths clamped to `max(value, 250_000)` and `max(value, 500_000)`, so a total failure was
reported as 250 KB/s and the "gain %" was computed from that fiction.

**Fixed:** the benchmark never toggles aggregation, reports failures as failures, measures
through Cloudflare's speed endpoint with `curl --interface`, and states in the UI that it
uses mobile data on a tethered link.

### 14. Chunk writes were serialised
`ChunkFileWriter` did `seek` + `write` under an `NSLock`. The file offset is shared state, so
eight parallel chunks queued behind one mutex.

**Fixed:** `pwrite` with an explicit offset per call — kernel-atomic, no lock, no seek.

### 15. Smaller correctness fixes
- `clearCompleted()` removed rows but leaked `.netwich-part` / metadata files.
- No free-space check before `truncate(toOffset: totalBytes)`.
- Resuming after the remote file changed reused stale chunk offsets (corrupt output). Now an
  ETag or length change resets the transfer.
- `linkRows` was recomputed (with a scheduler lock and allocation) several times per frame;
  it is now cached and refreshed once per telemetry tick.
- `writeExact` ignored partial writes on the SOCKS handshake path.
- Proxy flow count is now capped (`maxConnections`) so one buggy client cannot spawn
  thousands of blocking threads.

---

## P2 — architecture and dead weight

| Finding | Status |
|---|---|
| `App/ProxyController.swift` and the whole `Proxy/` system-extension target are **never referenced** by the app. Nobody activates the extension; the shipping path is `networksetup`. | Left in place (it needs a paid developer account), documented as unused. It also makes the README's architecture section misleading. |
| The SOCKS server uses one blocking thread per connection (`DispatchQueue.global().async`). Fine at a few hundred flows; a `kqueue`/`Network.framework` event loop would scale far better and use less stack. | Not changed — a rewrite of the transport layer, not a fix. Recorded as the next big performance step. |
| SOCKS5 `UDP ASSOCIATE` is not implemented, so QUIC/HTTP3 bypasses aggregation entirely and DNS-over-UDP goes direct. | Documented; needs a UDP relay to fix. |
| The browser extension directories were duplicated with near-identical copies, and `build.sh` copied compiled JS from `chrome/` into the repo root on every build. | `build.sh` is now resilient (esbuild failure falls back to committed bundles) and no longer writes to the repo root. |
| `DownloadRecord` persists chunks but not the ETag, so cross-launch resume cannot validate the remote file. | Partially fixed (in-session validation); persisting the ETag is a follow-up. |
| `ExtensionSetupView` revealed `file:///Users/parth/Developer/network proj/...` hardcoded paths. | Rewritten to resolve paths from `Bundle.main`. |
| The default user agent is a hardcoded Chrome 122 string. | Unchanged; should be derived from the bundle version. |

---

## UI rebuild

The old interface was ~2,800 lines in one file, built from `List`, `Form`, and `.bordered`
buttons: it looked like a settings panel, had no visual hierarchy, and several "features"
(fake multiplier badges, always-green health) actively misled.

The new interface is split into `App/Theme.swift`, `App/Views.swift`, `App/DownloadsViews.swift`
and `App/Pages.swift`:

- **Backdrop:** animated `MeshGradient` (macOS 15+) with a vignette, falling back to a static
  gradient on macOS 14.
- **Glass:** one `GlassSurface` modifier — `ultraThinMaterial` + three-stop specular gradient
  border + inner top highlight + layered shadow — so every card shares a single material
  language instead of ad-hoc `.background(.background, in: RoundedRectangle(...))`.
- **Custom shell:** transparent title bar (`WindowChrome`), a real sidebar with a
  `matchedGeometryEffect` selection pill instead of `NavigationSplitView`'s stock list.
- **Motion:** shared spring vocabulary (`Motion`), staggered entrance per card, hover lift,
  animated numeric transitions on every speed readout, a rotating power ring, and a shimmer
  on active progress bars.
- **Data honesty:** link health, per-adapter share meters, real chunk strips, and a benchmark
  card that shows what actually happened.

`docs/ANALYSIS.md` is the companion to `README.md`; the README now documents the DMG,
the separate extension archives, and the real permission story.

---

## Setup and packaging

- **Onboarding** is now a five-step wizard whose permissions step is live: it reads the actual
  bundle location, quarantine xattr, admin-group membership, login-item status and bundled
  extension payload, and each row opens the right place —
  `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension`,
  `…com.apple.LoginItems-Settings.extension`, `…com.apple.Network-Settings.extension`,
  or Finder. Reference for the identifiers:
  [macOS System Settings links](https://macmost.com/mac-settings-links).
- **`Scripts/package.sh`** builds Release, embeds the extension payload, writes
  `Netwich-Extension-Chromium-<v>.zip` and `Netwich-Extension-Firefox-<v>.zip`
  separately, and creates a drag-to-Applications DMG with an `Extensions` folder and an
  `INSTALL.txt`. Ad-hoc signing by default; Developer ID + notarisation via env vars.
  Reference: [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

### Known limitations to state plainly

1. The DMG is **ad-hoc signed**, not notarised. On another Mac the first launch requires
   Privacy & Security → Open Anyway. That is Apple's policy for any unsigned download and the
   onboarding screen links directly to it.
2. There is **no automated installer** for the browser extension: browsers do not allow one
   app to sideload into another. The best possible experience is what ships here — a ZIP, a
   revealed folder, and copy-ready steps.
3. The interface was verified by capturing every window from the installed 0.1.0 build; the
   screenshots and demo in the README come from those captures. Behaviour that needs two live
   links (real aggregation, elevated proxy changes) still has to be exercised on hardware with
   a second connection.
