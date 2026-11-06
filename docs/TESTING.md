# Testing

Two categories, kept strictly apart: what runs on any machine today, and what needs the
paid-developer entitlement plus a second physical link.

## Runs today (no entitlement, no second link)

```bash
swift test              # 15 scheduler tests
./mergecli sched        # weight distribution of a 300/40 Mbit pair
./mergecli links        # what the inventory sees on this Mac
```

Covers: link selection, weight ratios, disabled links, per-family filtering, no-usable-family,
failure → degraded → down → cooldown → revival, measured-throughput EWMA, counter persistence
across candidate refreshes, removed links, max-flows cap, and 4000 concurrent acquire/release
operations leaving zero leaked flows.

## Needs the entitlement (`Proxy/`)

| # | Check | Method | Pass |
|---|---|---|---|
| P1 | Extension loads | flip the toggle | no error, `systemextensionsctl list` shows it |
| P2 | Flows are spread | `curl` 4 URLs at once, read `status.json` | ≥2 links report `flows > 0` |
| P3 | No route change | `netstat -rn \| head -5` before/after | identical |
| P4 | Fail-open | disable every link but one | flows still work, `declinedFlows` grows |
| P5 | Provider killed | `pkill -f MergeProxy` mid-transfer | macOS disables the config, traffic reverts |
| P6 | Sleep/wake | `pmset sleepnow`, wake, start a download | resumes without restarting the app |
| P7 | Local traffic untouched | ping the router, AirDrop, print | private ranges never appear in the proxy |
| P8 | IPv6 | `curl -6 https://…` on a v4-only second link | picks the v6-capable link or declines |

## Download engine (next milestone)

| # | Check | Pass |
|---|---|---|
| D1 | Byte-identical output | `shasum` matches `curl` for a 500 MB file |
| D2 | Resume | `kill -9` mid-download restarts from saved blocks, not zero |
| D3 | Range-less server | one stream, correct file, no corruption |
| D4 | Backpressure | 429/503 while others serve → stream count backs off |
| D5 | Disk saturation | stream count halves, no unbounded buffering |

## Not claimed

No speed-up has been measured for this design. A single connection never exceeds one link,
and a server that caps per-connection throughput cannot be exceeded by more connections.
Reference point only: NetMerge's README reports 232–303 Mbit/s vs ~121 Mbit/s best single
link on its own hardware, with a Wi-Fi + Android USB tether + iPhone hotspot setup.
