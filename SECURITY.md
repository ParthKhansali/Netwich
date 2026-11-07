# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for a security problem. Use GitHub's
[private vulnerability reporting](https://github.com/ParthKhansali/Netwich/security/advisories/new)
or email the maintainer through the address on the GitHub profile
[@ParthKhansali](https://github.com/ParthKhansali).

Include the version, macOS version, steps to reproduce, and what an attacker
gains. You can expect an acknowledgement within a few days.

## What Netwich exposes

Netwich runs two loopback services while the app is open:

| Port | Service | Reachable from |
| --- | --- | --- |
| `127.0.0.1:1080` | SOCKS5 proxy | Local processes only |
| `127.0.0.1:19288–19290` | Browser bridge | Extension origins only |

Design decisions that matter:

- The bridge checks `Origin` on every request. `http(s)` origins are rejected with
  `403` and receive no CORS grant, so a website cannot read your download list or
  cancel transfers. Requests without an `Origin` (native clients) are allowed.
- It never sets `Access-Control-Allow-Origin: *`.
- Downloaded filenames are reduced to a single path component before use, so a
  hostile `Content-Disposition` cannot escape the download folder.
- System proxy changes are written only through `networksetup`, after the previous
  state has been saved, and restored on quit or after a crash recovery pass.
- There is no telemetry, no account, and no remote service operated by the project.

## Supported versions

The latest release on the `main` branch is supported. Fixes are shipped as a new
tagged release.
