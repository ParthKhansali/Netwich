# Netwich: Stack your connections.

Netwich is a native macOS utility that combines multiple internet connections (such as your home Wi-Fi and your phone's USB tethering) and accelerates file downloads with coordinated multi-link transfers.

Built in pure Swift with Apple's native design language. Zero cloud servers to maintain, zero VPN subscription fees, and unprivileged userspace networking that costs nothing.

---

## Key Features

### 1. System-Wide Internet Aggregation
- Distributes outbound internet traffic across all active physical network adapters (Wi-Fi, Ethernet, USB tethering).
- Runs an unprivileged, high-performance local SOCKS5 aggregator on `127.0.0.1:1080`.
- Configures macOS system proxy settings seamlessly with zero admin prompts.
- Weighted least-connections scheduler with real-time EWMA throughput metrics and health checks.
- Automatic failover: if one link drops, traffic continues through the remaining links.
- Automated cleanup on quit or crash so normal networking is never disrupted.

### 2. Accelerated Multi-Chunk Downloads
- Splits large files into parallel HTTP range chunks (4, 8, 16, or 32 concurrent streams).
- Distributes individual chunk connections across distinct physical network adapters.
- Real-time download progress, live throughput gauges, and ETA calculations.
- Full pause and resume capability with persistent `.merge-meta.json` sidecar files.
- Graceful single-stream fallback for servers that do not support HTTP byte ranges.
- Drag-and-drop URL support and clipboard integration.

### 3. Browser Extension Integration
- Built-in HTTP bridge on `127.0.0.1:19288` (with fallback to 19289, 19290).
- Chrome, Brave, Edge, Arc, and Firefox extensions packaged directly in `extension/` and embedded in `Netwich.app/Contents/Resources/extension`.
- One-click download capture directly from your browser.

### 4. Apple Silicon Native UI
- Native macOS design with sidebar navigation, SF Symbols, and smooth animations.
- Interactive 4-page onboarding flow on first launch.
- Real-time Rx and Tx traffic speed meters.
- Compact Menu Bar extra showing live download speeds and quick toggle.
- Android USB tethering guide with compatibility instructions.

---

## Getting Started

### Building from Source

Prerequisites:
- macOS 14+ on Apple Silicon
- Xcode (Command Line Tools)
- `xcodegen` (`brew install xcodegen`)

```bash
# Run unit and integration tests
swift test

# Build and assemble Netwich.app
./Scripts/build.sh
```

The compiled application will be generated at `build/Netwich.app` (with a `build/Merge.app` symlink for backwards compatibility).

### Running Netwich

```bash
open build/Netwich.app
```

Or run the headless CLI tool:

```bash
# Inspect detected physical network adapters
./.build/debug/mergecli links

# Test scheduler weighting across links
./.build/debug/mergecli sched

# Check system network services
./.build/debug/mergecli systemproxy

# Download a file via CLI multi-chunk engine
./.build/debug/mergecli download "https://proof.ovh.net/files/1Mb.dat"
```

---

## Installing the Browser Extension

1. In Google Chrome, Brave, Edge, or Arc:
   - Navigate to `chrome://extensions`
   - Enable **Developer mode** (top right)
   - Click **Load unpacked**
   - Select the `extension/chrome` folder inside the project
2. In Mozilla Firefox:
   - Navigate to `about:debugging#/runtime/this-firefox`
   - Click **Load Temporary Add-on...**
   - Select `extension/firefox/manifest.json`

---

## Architecture

```
Netwich.app
├── Contents/MacOS/Netwich               # Main SwiftUI application and engines
├── Contents/Resources/Netwich.icns      # macOS App Icon
├── Contents/Resources/netwichTemplate*  # Menu bar monochrome template icon
├── Contents/Resources/extension/        # Packaged Chrome & Firefox browser extensions
└── Contents/Library/System Extensions/  # Optional system extension
```

### Components:
- **`Sources/MergeKit/LocalProxy.swift`**: Local multi-homed SOCKS5 proxy server binding outbound connections with `IP_BOUND_IF`.
- **`Sources/MergeKit/SystemProxyManager.swift`**: System-wide proxy switcher with automated recovery.
- **`Sources/MergeKit/DownloadEngine.swift`**: Parallel HTTP range downloader with chunk distribution and resume support.
- **`Sources/MergeKit/BrowserBridge.swift`**: Local HTTP bridge (`/ping`, `/add`, `/confirm`) for browser extensions.
- **`Sources/MergeKit/Scheduler.swift`**: Flow scheduling, EWMA weights, and link health tracking.
- **`App/`**: SwiftUI views (Overview, Downloads, Extension, Tethering, Settings, Onboarding, MenuBarExtra).

---

## Credits & Licensing

- Open source under the MIT License.
- Designed & built by **Parth Khansali** (https://github.com/ParthKhansali).
