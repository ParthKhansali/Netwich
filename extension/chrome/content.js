(() => {
  // extension/src/content.ts
  (function() {
    if (window !== window.top) return;
    if (window.__netwichHUDInitialized) return;
    window.__netwichHUDInitialized = true;
    let hostEl = null;
    let shadowRoot = null;
    let currentDownload = null;
    let autoDismissTimer = null;
    let isMinimized = false;
    let isDismissed = false;
    let lastDownloadId = null;
    function formatBytes(bytes) {
      if (!bytes || bytes <= 0) return "0 B";
      if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB";
      if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
      if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB";
      return bytes + " B";
    }
    function formatRate(bytesPerSec) {
      if (!bytesPerSec || bytesPerSec <= 0) return "0 B/s";
      return `${formatBytes(bytesPerSec)}/s`;
    }
    function getFileIcon(filename) {
      const ext = filename.split(".").pop()?.toLowerCase() || "";
      if (["mp4", "mov", "webm", "mkv", "avi"].includes(ext)) return "\u{1F3AC}";
      if (["zip", "rar", "7z", "tar", "gz", "dmg"].includes(ext)) return "\u{1F4E6}";
      if (["mp3", "wav", "flac", "m4a"].includes(ext)) return "\u{1F3B5}";
      if (["png", "jpg", "jpeg", "webp", "svg", "gif"].includes(ext)) return "\u{1F5BC}\uFE0F";
      if (["pdf", "doc", "docx", "txt", "epub"].includes(ext)) return "\u{1F4C4}";
      if (["exe", "pkg", "app", "iso"].includes(ext)) return "\u{1F4BF}";
      return "\u26A1";
    }
    function ensureHUD() {
      if (shadowRoot && hostEl && document.contains(hostEl)) return shadowRoot;
      const existingHost = document.getElementById("netwich-download-hud-host");
      if (existingHost) {
        hostEl = existingHost;
      } else {
        hostEl = document.createElement("div");
        hostEl.id = "netwich-download-hud-host";
        hostEl.style.cssText = "all: initial; position: fixed; top: 16px; right: 20px; z-index: 2147483647; pointer-events: none;";
        const parent = document.body || document.documentElement;
        if (parent) {
          parent.appendChild(hostEl);
        }
      }
      if (hostEl.shadowRoot) {
        shadowRoot = hostEl.shadowRoot;
        return shadowRoot;
      }
      shadowRoot = hostEl.attachShadow({ mode: "open" });
      shadowRoot.innerHTML = `
      <style>
        * {
          box-sizing: border-box;
          margin: 0;
          padding: 0;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          -webkit-font-smoothing: antialiased;
        }

        .hud-container {
          pointer-events: auto;
          position: relative;
        }

        /* Full Card */
        .hud-card {
          width: 304px;
          border-radius: 16px;
          background: rgba(20, 20, 26, 0.84);
          backdrop-filter: blur(28px) saturate(190%);
          -webkit-backdrop-filter: blur(28px) saturate(190%);
          border: 1px solid rgba(255, 255, 255, 0.14);
          box-shadow: 0 20px 48px rgba(0, 0, 0, 0.55),
                      0 1px 2px rgba(255, 255, 255, 0.18) inset;
          color: #f2f2f7;
          overflow: hidden;
          transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.25s ease, filter 0.25s ease;
          transform: translateY(-16px) scale(0.97);
          opacity: 0;
          display: block;
        }

        .hud-card.visible {
          transform: translateY(0) scale(1);
          opacity: 1;
        }

        .hud-card.minimized {
          display: none !important;
        }

        /* Mini Floating Pill (when minimized) */
        .hud-mini-pill {
          display: none;
          align-items: center;
          gap: 8px;
          padding: 7px 12px;
          border-radius: 20px;
          background: rgba(20, 20, 26, 0.88);
          backdrop-filter: blur(24px) saturate(190%);
          -webkit-backdrop-filter: blur(24px) saturate(190%);
          border: 1px solid rgba(255, 255, 255, 0.16);
          box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
          cursor: pointer;
          color: #ffffff;
          font-size: 11.5px;
          font-weight: 500;
          transition: transform 0.2s cubic-bezier(0.16, 1, 0.3, 1), background 0.2s;
        }

        .hud-mini-pill:hover {
          background: rgba(30, 30, 38, 0.95);
          transform: scale(1.03);
        }

        .hud-mini-pill.visible {
          display: flex !important;
        }

        .pill-speed {
          color: #0A84FF;
          font-weight: 600;
        }

        .hud-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 10px 12px 8px 12px;
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
          background: rgba(255, 255, 255, 0.02);
        }

        .hud-brand {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11.5px;
          font-weight: 600;
          color: #a1a1a6;
        }

        .hud-dot {
          width: 7px;
          height: 7px;
          border-radius: 50%;
          background: #30D158;
          box-shadow: 0 0 6px #30D158;
          animation: pulse 2s infinite ease-in-out;
        }

        @keyframes pulse {
          0% { transform: scale(0.95); opacity: 0.8; }
          50% { transform: scale(1.15); opacity: 1; box-shadow: 0 0 10px #30D158; }
          100% { transform: scale(0.95); opacity: 0.8; }
        }

        .hud-controls {
          display: flex;
          align-items: center;
          gap: 2px;
        }

        .hud-btn-icon {
          background: transparent;
          border: none;
          color: #8e8e93;
          font-size: 13px;
          cursor: pointer;
          width: 22px;
          height: 22px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 6px;
          transition: background 0.15s, color 0.15s;
        }

        .hud-btn-icon:hover {
          background: rgba(255, 255, 255, 0.12);
          color: #ffffff;
        }

        .hud-body {
          padding: 12px;
          display: flex;
          gap: 10px;
        }

        .hud-icon-box {
          width: 38px;
          height: 38px;
          border-radius: 10px;
          background: linear-gradient(135deg, rgba(10, 132, 255, 0.2), rgba(94, 92, 230, 0.15));
          border: 1px solid rgba(10, 132, 255, 0.25);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 19px;
          flex-shrink: 0;
        }

        .hud-info {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }

        .hud-filename {
          font-size: 12.5px;
          font-weight: 600;
          color: #ffffff;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .hud-status-line {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11px;
          color: #8e8e93;
        }

        .hud-speed {
          color: #0A84FF;
          font-weight: 600;
          font-feature-settings: "tnum";
        }

        .hud-progress-wrap {
          margin-top: 5px;
          position: relative;
          height: 5px;
          background: rgba(255, 255, 255, 0.1);
          border-radius: 2.5px;
          overflow: hidden;
        }

        .hud-progress-bar {
          height: 100%;
          width: 0%;
          background: linear-gradient(90deg, #0A84FF, #5E5CE6, #30D158);
          border-radius: 2.5px;
          transition: width 0.25s ease;
        }

        .hud-progress-bar.completed {
          background: #30D158;
          box-shadow: 0 0 8px rgba(48, 209, 88, 0.5);
        }

        /* Acceleration Badge Strip */
        .hud-accel-strip {
          margin: 0 12px 6px 12px;
          padding: 4px 8px;
          border-radius: 6px;
          background: rgba(10, 132, 255, 0.1);
          border: 1px solid rgba(10, 132, 255, 0.2);
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 10px;
          color: #0A84FF;
          font-weight: 600;
        }

        .hud-footer {
          padding: 6px 12px 10px 12px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 11px;
        }

        .hud-percent {
          font-weight: 600;
          color: #e5e5ea;
          font-feature-settings: "tnum";
        }

        .hud-actions {
          display: flex;
          gap: 6px;
        }

        .hud-btn {
          background: #0A84FF;
          border: 1px solid #0A84FF;
          color: #ffffff;
          font-size: 11px;
          font-weight: 500;
          padding: 4px 10px;
          border-radius: 6px;
          cursor: pointer;
          transition: background 0.15s ease;
        }

        .hud-btn:hover {
          background: #0077ED;
          border-color: #0077ED;
        }
      </style>

      <div class="hud-container" id="container">
        <!-- Full Card -->
        <div class="hud-card" id="card">
          <div class="hud-header">
            <div class="hud-brand">
              <div class="hud-dot" id="dot"></div>
              <span id="header-title">Netwich Download</span>
            </div>
            <div class="hud-controls">
              <button class="hud-btn-icon" id="minimize-btn" title="Minimize to Pill">
                <svg width="10" height="2" viewBox="0 0 10 2" fill="currentColor"><rect width="10" height="2" rx="1"></rect></svg>
              </button>
              <button class="hud-btn-icon" id="close-btn" title="Dismiss">\u2715</button>
            </div>
          </div>

          <div class="hud-body">
            <div class="hud-icon-box" id="file-icon">\u26A1</div>
            <div class="hud-info">
              <div class="hud-filename" id="filename">Preparing download...</div>
              <div class="hud-status-line">
                <span id="status-text">Connecting...</span>
                <span id="dot-sep" style="display:none;">\u2022</span>
                <span class="hud-speed" id="speed" style="display:none;"></span>
              </div>
              <div class="hud-progress-wrap">
                <div class="hud-progress-bar" id="progress-bar"></div>
              </div>
            </div>
          </div>

          <div class="hud-accel-strip" id="accel-strip">
            <span id="accel-label">\u26A1 Multi-Link Turbo</span>
            <span id="accel-detail">8 Parallel Streams</span>
          </div>

          <div class="hud-footer">
            <div class="hud-percent" id="percent">0%</div>
            <div class="hud-actions">
              <button class="hud-btn" id="open-app-btn">Open App</button>
            </div>
          </div>
        </div>

        <!-- Mini Floating Pill -->
        <div class="hud-mini-pill" id="mini-pill" title="Click to expand">
          <span>\u26A1</span>
          <span id="pill-info">Downloading...</span>
          <span class="pill-speed" id="pill-speed"></span>
        </div>
      </div>
    `;
      const closeBtn = shadowRoot.getElementById("close-btn");
      closeBtn?.addEventListener("click", () => {
        isDismissed = true;
        if (currentDownload?.id) {
          try {
            sessionStorage.setItem("netwich_dismissed_" + currentDownload.id, "1");
          } catch {
          }
        }
        hideHUD();
      });
      const minimizeBtn = shadowRoot.getElementById("minimize-btn");
      minimizeBtn?.addEventListener("click", () => {
        isMinimized = true;
        applyMinimizedState();
      });
      const miniPill = shadowRoot.getElementById("mini-pill");
      miniPill?.addEventListener("click", () => {
        isMinimized = false;
        applyMinimizedState();
      });
      const openBtn = shadowRoot.getElementById("open-app-btn");
      openBtn?.addEventListener("click", () => {
        chrome.runtime.sendMessage({ type: "OPEN_APP" });
      });
      return shadowRoot;
    }
    function applyMinimizedState() {
      if (!shadowRoot) return;
      const card = shadowRoot.getElementById("card");
      const miniPill = shadowRoot.getElementById("mini-pill");
      if (isMinimized) {
        card?.classList.add("minimized");
        miniPill?.classList.add("visible");
      } else {
        card?.classList.remove("minimized");
        miniPill?.classList.remove("visible");
      }
    }
    function showHUD(download, forceShow = false) {
      if (isDismissed && lastDownloadId === download.id) {
        return;
      }
      try {
        if (sessionStorage.getItem("netwich_dismissed_" + download.id) === "1") {
          return;
        }
      } catch {
      }
      if (!forceShow) {
        if (!shadowRoot) return;
        const card2 = shadowRoot.getElementById("card");
        const miniPill = shadowRoot.getElementById("mini-pill");
        const isVisible = card2?.classList.contains("visible") || miniPill?.classList.contains("visible");
        if (!isVisible) return;
      }
      if (lastDownloadId !== download.id) {
        isDismissed = false;
        lastDownloadId = download.id;
      }
      const root = ensureHUD();
      currentDownload = download;
      if (autoDismissTimer) {
        clearTimeout(autoDismissTimer);
        autoDismissTimer = null;
      }
      const card = root.getElementById("card");
      const filenameEl = root.getElementById("filename");
      const statusTextEl = root.getElementById("status-text");
      const speedEl = root.getElementById("speed");
      const dotSep = root.getElementById("dot-sep");
      const progressBar = root.getElementById("progress-bar");
      const percentEl = root.getElementById("percent");
      const fileIconEl = root.getElementById("file-icon");
      const headerTitle = root.getElementById("header-title");
      const dot = root.getElementById("dot");
      const accelStrip = root.getElementById("accel-strip");
      const accelLabel = root.getElementById("accel-label");
      const accelDetail = root.getElementById("accel-detail");
      const pillInfo = root.getElementById("pill-info");
      const pillSpeed = root.getElementById("pill-speed");
      if (filenameEl) filenameEl.textContent = download.filename;
      if (fileIconEl) fileIconEl.textContent = getFileIcon(download.filename);
      const pct = Math.min(100, Math.max(0, Math.round((download.progress || 0) * 100)));
      if (percentEl) percentEl.textContent = `${pct}%`;
      if (progressBar) {
        progressBar.style.width = `${pct}%`;
      }
      if (pillInfo) {
        const dl = formatBytes(download.downloadedBytes);
        pillInfo.textContent = `${dl} (${pct}%)`;
      }
      if (pillSpeed) {
        pillSpeed.textContent = download.speedBytesPerSec > 0 ? formatRate(download.speedBytesPerSec) : "";
      }
      if (download.isCompleted || download.status === "completed") {
        if (headerTitle) headerTitle.textContent = "Download Complete";
        if (statusTextEl) statusTextEl.textContent = `Saved (${formatBytes(download.totalBytes)})`;
        if (speedEl) speedEl.style.display = "none";
        if (dotSep) dotSep.style.display = "none";
        if (accelStrip) accelStrip.style.display = "none";
        if (dot) {
          dot.style.background = "#30D158";
          dot.style.boxShadow = "0 0 10px #30D158";
        }
        if (progressBar) {
          progressBar.classList.add("completed");
          progressBar.style.width = "100%";
        }
        if (percentEl) percentEl.textContent = "100%";
        autoDismissTimer = setTimeout(() => {
          isDismissed = true;
          if (currentDownload?.id) {
            try {
              sessionStorage.setItem("netwich_dismissed_" + currentDownload.id, "1");
            } catch {
            }
          }
          hideHUD();
        }, 4e3);
      } else if (download.status === "failed") {
        if (headerTitle) headerTitle.textContent = "Download Failed";
        if (statusTextEl) statusTextEl.textContent = "Network connection lost";
        if (speedEl) speedEl.style.display = "none";
        if (dotSep) dotSep.style.display = "none";
        if (accelStrip) accelStrip.style.display = "none";
        if (dot) {
          dot.style.background = "#FF453A";
          dot.style.boxShadow = "0 0 8px #FF453A";
        }
      } else {
        if (headerTitle) headerTitle.textContent = "Netwich Accelerating";
        if (progressBar) progressBar.classList.remove("completed");
        if (download.totalBytes > 0) {
          const dl = formatBytes(download.downloadedBytes);
          const tot = formatBytes(download.totalBytes);
          if (statusTextEl) statusTextEl.textContent = `${dl} of ${tot}`;
        } else {
          if (statusTextEl) statusTextEl.textContent = "Chunking & accelerating...";
        }
        if (download.speedBytesPerSec > 0) {
          if (speedEl) {
            speedEl.textContent = formatRate(download.speedBytesPerSec);
            speedEl.style.display = "inline";
          }
          if (dotSep) dotSep.style.display = "inline";
        } else {
          if (speedEl) speedEl.style.display = "none";
          if (dotSep) dotSep.style.display = "none";
        }
        if (accelStrip) {
          accelStrip.style.display = "flex";
          const links = download.linksCount || 1;
          if (links >= 2) {
            if (accelLabel) accelLabel.textContent = `\u26A1 Multi-Link (${links} Adapters \xB7 1.8x Speed)`;
            if (accelDetail) accelDetail.textContent = "+80% Throughput";
          } else {
            if (accelLabel) accelLabel.textContent = "\u26A1 Turbo Multi-Stream";
            if (accelDetail) accelDetail.textContent = "8 Parallel Chunks";
          }
        }
      }
      card?.classList.add("visible");
      applyMinimizedState();
    }
    function hideHUD() {
      if (!shadowRoot) return;
      const card = shadowRoot.getElementById("card");
      const miniPill = shadowRoot.getElementById("mini-pill");
      card?.classList.remove("visible");
      miniPill?.classList.remove("visible");
    }
    chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
      if (message.type === "NETWICH_SHOW_DOWNLOAD") {
        if (message.download) {
          showHUD(message.download, true);
          sendResponse({ success: true });
        }
      } else if (message.type === "NETWICH_DOWNLOAD_PROGRESS") {
        if (message.download) {
          showHUD(message.download, false);
          sendResponse({ success: true });
        }
      } else if (message.type === "NETWICH_HIDE_DOWNLOAD") {
        hideHUD();
        sendResponse({ success: true });
      }
    });
  })();
})();
