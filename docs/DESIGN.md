# Merge — pure-Swift macOS internet aggregation + accelerated downloads

Single source of truth for the build. Derived from source inspection of `anmolkapil/plexo`
(`research/plexo`) and `net-merge/net-merge` (`research/netmerge`), plus Apple's platform
documentation (sources in §11).

**Supersedes the earlier Go/Node hybrid design.** Going all-Swift did not just change the shell — it
deleted the two hardest parts of the previous plan (a userspace TCP/IP stack and a root helper).

---

## 1. What changed, and why it is now much smaller

The previous plan needed a root daemon that created a `utun` and a userspace TCP stack (gVisor/lwIP)
to terminate flows — because that is how NetMerge works: `utun` + `0.0.0.0/1` routes + tun2socks.

There is a supported Apple API that hands you the same thing **as byte streams, with no root, no
routes, no MTU games, no kernel extension, and no TCP stack**:

**`NETransparentProxyProvider`** (NetworkExtension, macOS 11+). The system terminates each app's TCP
connection and gives the provider a `NEAppProxyTCPFlow` — `readData`/`writeData` plus the original
destination. The provider opens its own `NWConnection` to that destination, pinned to a chosen
`NWInterface` via `NWParameters.requiredInterface`, and copies bytes. That's the entire aggregation
engine.

Verified deployment facts:

| Fact | Source |
|---|---|
| A transparent proxy provider ships **outside the App Store** as a **system extension** with Developer ID signing. Only the *app extension* packaging is App Store–only. | TN3134 "Deploying a transparent proxy provider" |
| Direct-distribution builds must use the `*-systemextension` entitlement value: `app-proxy-provider-systemextension`. | Network Extensions Entitlement docs; Apple forums 67613 §8 |
| The provider's own `NWConnection`s are **not re-intercepted** by its own rules — loop prevention is structural, not something you implement. | Apple forums 677357; ADR in `XhinLiang/drawbridge` ("the loop problem disappears by construction") |
| Loopback traffic is **not** delivered to a transparent proxy (since macOS 11.3). | Apple forums (loopback thread) |
| Transparent proxies on macOS **stack** in install order; a provider can decline a flow with `return false` and the system routes it directly. | `NETransparentProxyProvider` docs; Apple forums 677357 |
| Network Extension capability is **not** available on a free Apple Developer account. | Stack Overflow 77974220; Apple capability table ("Network extensions" absent for Apple Developer tier) |

Consequences — the whole plan collapses:

| Old plan | Pure Swift |
|---|---|
| Go binary reimplemented in Swift (4.5k LOC: tun, route sync, netstack glue) | **deleted** |
| gVisor/lwIP userspace TCP stack | **deleted** (no stack needed) |
| root `utun` helper + `sudoers`/`SMAppService` daemon + single-instance lock | **deleted** (no root at any point) |
| route surgery (`0/1`+`128/1`, scoped defaults, `keepDevice`) | **deleted** (no routes touched) |
| "macOS drops the TetherKit link when net-merge starts/quits" | **gone** — we never touch interfaces or routes |
| Node sidecar (~55 MB) for Plexo's TS engine | **deleted** — Swift range downloader (~1.2k LOC) |
| Electron/Chromium | **deleted** |
| MTU 9000, IPv6 refuse-at-SYN hack, `flock`, `/var/run` markers | **gone** |

Estimated result: **~7 MB app, ~45–70 MB RAM idle** (no runtime to ship; system frameworks only),
versus 141 MB dmg / 250–350 MB RAM for a Plexo fork. *(unverified — measure the first build.)*

**The one hard prerequisite:** a **paid Apple Developer Program membership** ($99/yr). Without it the
app can compile but the system extension cannot load. That is the whole price of this architecture.
Everything else in §5 works today without it.

---

## 2. Architecture

Three targets, one language, no runtime dependencies.

```
Merge.app                                   (SwiftUI, non-sandboxed, LSUIElement, notarized)
├─ Contents/MacOS/Merge                      menu bar + window + download engine
├─ Contents/Library/System Extensions/
│    dev.parth.merge.proxy.systemextension   NETransparentProxyProvider (sandboxed)
└─ Contents/Resources/{extension/, …}        browser extension handed to the user
```

| Process | Runs as | Owns |
|---|---|---|
| `Merge` (app) | user | UI, download engine, browser bridge, app-group control file, provider lifecycle |
| `dev.parth.merge.proxy` (system extension) | system, sandboxed | flow interception, link health, per-flow scheduling, status file |
| `net` (Apple frameworks) | kernel | all TCP termination, all routing, all TLS |

**Nothing runs as root. No route is modified. No interface is created.**

### 2.1 Who aggregates what

- **System-wide traffic** → the extension. Every TCP flow from every app is offered to it.
- **Downloads** → the app's engine opens *N* parallel range requests with `URLSession`. Those are
  ordinary TCP flows, so the extension spreads them across links exactly like browser traffic. The
  engine needs no interface binding at all — and should not have any.
- **Nothing is aggregated twice.** With one healthy link the provider declines every flow
  (`return false`), the system routes normally, and overhead is zero.

### 2.2 Flow of one download

```
engine: 16 × GET https://host/file  Range: bytes=a-b   (URLSession, no pinning)
   → system offers each TCP flow to the extension (transparent, app unaware)
   → provider picks a link per flow: min (busy+1)/weight, family-matched, healthy
   → NWConnection(to: host, using: .tcp with requiredInterface = link)
   → bytes relayed both ways until EOF; per-link byte counters updated
```

Chunk planning still matters (splitting the file so you *have* 16 connections to spread), and it is
the only part of Plexo's engine worth porting.

### 2.3 Scheduling (ported from NetMerge's proven design)

`Sources/MergeKit/Scheduler.swift`:

- weight = user weight, else EWMA of measured throughput (α 0.3), floor 1 Mbit.
- pick `min (busyFlows + 1) / weight` among eligible links; ties broken by name (deterministic, testable).
- per-family busy counters; a flow is only offered links that support its address family.
- health tiers: `up` → `degraded` (weight ÷ 4) → `down` (skipped for 15 s), driven by TCP probes to
  `1.1.1.1:443` / `8.8.8.8:443` every 15 s (4 s while degraded) and by data-path failures.
- the extension never blocks: synchronous, lock-guarded, no allocation in the accept path.

---

## 3. Deliberate scope decisions

| Decision | Reason |
|---|---|
| **TCP only in v1** (UDP/QUIC declined → routed directly) | Removes UDP/QUIC-migration edge cases from the first release at the cost of browsers' HTTP/3 bypassing aggregation. Downloads from our engine force TCP (`assumesHTTP3Capable = false`). v2 adds `NEAppProxyUDPFlow`. |
| **No torrents, no NZB, no Telegram** | Plexo got these from WebTorrent/NNTP/MTProto in JS. Pure Swift means libtorrent (C++/boost) or a fresh implementation — weeks, and not part of "faster downloads from the web". |
| **No per-download link pinning in v1** | The extension decides per flow. "Download only on Wi-Fi" becomes a v2 loopback-relay feature inside the provider. |
| **No App Sandbox on the app** | It writes downloads anywhere and hosts a system extension. Notarized Developer ID instead. The *extension* is sandboxed, as required. |
| **Browser extension reused verbatim** | It speaks HTTP to `127.0.0.1:19288-19290`; there is no native-messaging host to port. Only branding changes. |

---

## 4. Permissions, end to end (the user-facing story)

The whole point of this architecture is a two-prompt install with no password.

| # | Moment | Prompt | Can we avoid it? |
|---|---|---|---|
| 1 | First launch, user flips "Combine connections" | **System Settings → Privacy & Security** (or the in-app prompt) *“Merge would like to install a system extension”* → Allow. Return to app / authenticate. | No. Every network extension needs it. Keep it to one time. |
| 2 | Immediately after | *“Merge would like to add a VPN configuration”* (`saveToPreferences`) → Allow. | No. Transparent proxies are NE configurations. Wording matters: explain it is local-only. |
| 3 | `NSSystemExtensionUsageDescription` | The sentence shown in prompt #1 | We write it: *"Merge needs a system extension to route your internet traffic across your connections. Nothing leaves your Mac."* |
| 4 | Settings → Launch at login (opt-in) | Login Items entry (`SMAppService.mainApp`) | Avoidable — only if the user enables it. |
| 5 | First save into `~/Downloads` | TCC *“Merge would like to access files in your Downloads folder”* | Avoidable-ish: default the save folder to `~/Downloads` and let the standard panel grant access, or default to `~/Downloads/Merge`. |
| 6 | Local Network (macOS 14+) | Only if we browse the LAN. **We never do** — private ranges are excluded from the proxy, so the system still resolves Bonjour itself. | Not triggered. |
| 7 | Full Disk Access, Accessibility, Input Monitoring, admin password, kernel extension approval, SIP change | — | **Never.** This is the biggest user-friendliness win over the NetMerge-based design. |

Development only (never shipped): `systemextensionsctl developer on` so the extension can load from
`DerivedData` instead of `/Applications`. Distribution builds need the app in `/Applications` and a
notarized ticket.

**Uninstall is one gesture**: dragging the app to the Trash removes the system extension
(documented macOS behaviour) and its NE configuration.

---

## 5. What works without the paid account

Everything except system-wide interception:

- the app, menu bar, settings, onboarding, history, per-download controls;
- the download engine (parallel ranges, resume, integrity, disk backpressure) — it will simply be
  served by the OS default route until the extension can load;
- the browser extension + local bridge (loopback is never proxied);
- all scheduler/link logic, unit-tested headlessly.

So the project is useful on day one and finishes when the entitlement exists.

---

## 6. Repository layout

```
merge/
├─ Package.swift                     MergeKit (logic, testable, no NE import) + mergecli
├─ project.yml                       xcodegen → Merge.xcodeproj (app + system extension)
├─ Sources/MergeKit/
│  ├─ Link.swift                     LinkID, AddressFamily, LinkCandidate, LinkSnapshot, HealthTier
│  ├─ Scheduler.swift                weighted least-flows, tiers, cooldown, EWMA weights
│  ├─ LinkInventory.swift            NWPathMonitor → candidates, virtual-interface filter
│  ├─ InterfaceScanner.swift         getifaddrs → per-interface IPv4/IPv6 (no link-local)
│  ├─ ProxyStatus.swift              app-group status.json / control.json contract
│  └─ (next) RangePlanner, Transfer, DownloadStore, BridgeServer
├─ Sources/mergecli/main.swift       `mergecli links` — inspect links headlessly
├─ App/                              MergeApp, AppState, ProxyController, LaunchAtLogin, views
├─ Proxy/                            ProxyProvider (NETransparentProxyProvider), FlowRelay
├─ extension/                        forked plexo/extension (chrome + firefox builds)
├─ Scripts/build.sh                  test → generate → build → embed → codesign/notarize
└─ docs/                             DESIGN.md (this), TESTING.md, NOTICES.md
```

---

## 7. Phases

**P0 — foundation (this commit).** SwiftPM package, scheduler + tests, xcodegen project, entitlements,
provider skeleton, app shell. Gate: `swift test`, `xcodegen generate`, `xcodebuild` all green.

**P1 — the provider actually relays.** `FlowRelay` (TCP pump, half-close, fail-open), health probes,
status/control files, live toggle. Gate: with the entitlement, `curl https://…` twice lands on two
different links (verify per-link byte counters in status.json) while `ifconfig` shows no route change.

**P2 — the engine.** `RangePlanner` (1–8 MiB blocks), `Transfer` (URLSession, `Accept-Encoding:
identity`, `If-Range`/ETag validation, 16 connections, disk backpressure), resume across relaunch,
pause/cancel. Gate: byte-identical output vs `curl` for a 500 MB file; kill -9 mid-download resumes.

**P3 — UX.** Overview + Downloads + Settings + onboarding (including the two prompts, explained in
plain language), notifications, "downloads on Wi-Fi only" warning, menu bar speed.

**P4 — browser extension.** Fork + rebrand, `BridgeServer` implementing `/ping`, `/add`, `/confirm`
(ports 19288–19290, `api: 1`, token handshake, cookie/referer/UA forwarding).

**P5 — ship.** Notarize, Sparkle 2 (EdDSA), crash supervision, full test matrix, NOTICES.

---

## 8. Risks

1. **Paid ADP requirement** — the only blocking prerequisite. Everything else is code.
2. **Provider bug = broken internet.** Mitigations: never block in `handleNewFlow`; decline flows when
   no link is eligible (fail-open); closed-loop timeouts; if the extension is killed, macOS disables
   the config and networking reverts. Test "provider killed mid-transfer" explicitly.
3. **TCP-only v1** — browser QUIC bypasses aggregation. Documented; v2 adds UDP flows.
4. **Throughput of a userspace byte pump** — each flow is a memcpy either side. Expected fine at
   300–800 Mbit/s; **measure before claiming any speed-up**.
5. **Aggregation is only as good as the links** — one connection never exceeds one link; per-connection
   server limits and per-IP session binding (logins re-prompting) are physical facts, not bugs.
6. **Entitlement/plist shape drift across Xcode versions** — pin the `*-systemextension` value and the
   `Contents/Library/System Extensions` layout; re-verify after each Xcode upgrade.
7. **TCC on Downloads** — default save path must be user-visible and explained once.

---

## 9. Testing

Unit (no network, run today): scheduler selection, weights, tiers, cooldown, family filtering,
concurrency safety (`swift test`).

Integration (needs entitlement + 2 links): per-link counters move for separate flows; no route change
(`route -n get default`, `ifconfig` before/after); provider disabled mid-transfer; sleep/wake; single
link declines all flows; `curl -6` behaviour when one link is v4-only; kill the app while aggregating.

Engine: byte-identical output, resume after `kill -9`, range-less server (single stream), 429/503
backpressure, disk saturation, 8→16 stream ramp.

**Nothing in this document claims a measured speed-up.** NetMerge's own README reports 232–303 Mbit/s
vs ~121 Mbit/s best single link on *its* hardware; that is a reference number, not a measurement of
this design.

---

## 10. Sources

- TN3134 Network Extension provider deployment — packaging matrix, Developer ID support.
- `com.apple.developer.networking.networkextension` — `app-proxy-provider-systemextension`.
- `NETransparentProxyProvider`, `NETransparentProxyNetworkSettings`, `NENetworkRule`,
  "Handling Flow Copying", `NEAppProxyTCPFlow.readData/writeData`.
- Apple forums 67613 (§8: Developer ID + system extension + `*-system` entitlement), 677357
  (ordering/self-exclusion of provider connections), loopback thread (macOS 11.3 loopback exclusion).
- Installing System Extensions and Drivers — `Contents/Library/System Extensions`,
  `systemextensionsctl developer on`, same Team ID, notarization.
- `smappservice/mainapp`, Sparkle 2 SPM + EdDSA.
- `XhinLiang/drawbridge` ADR 0001 — independent confirmation that provider sockets are not
  re-intercepted; `madeye/BaoLianDeng` TransparentProxyProvider.swift — worked example;
  `AlphaBitCore/nexus-gateway` NE fail-open notes (UDP 53/5353/67/68/123/500/4500 exclusions).
- Local: `research/plexo` (chunk plan, concurrency, integrity, bridge contract),
  `research/netmerge` (scheduler, health tiers, probe policy, per-link limits).
