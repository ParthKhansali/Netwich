(() => {
  // extension/src/api.ts
  var api = globalThis.browser ?? chrome;

  // extension/src/bridge.ts
  var BRIDGE_PORTS = [19288, 19289, 19290];
  var BRIDGE_API = 1;
  var activePort = null;
  async function pingPort(port) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/ping`, {
        signal: AbortSignal.timeout(1200)
      });
      if (!res.ok) return "closed";
      const ping = await res.json();
      if (ping.app !== "netwich" && ping.app !== "merge" && ping.app !== "plexo") return "closed";
      return ping.api === BRIDGE_API ? "ok" : "update";
    } catch {
      return "closed";
    }
  }
  async function reach() {
    const results = await Promise.all(BRIDGE_PORTS.map(pingPort));
    const okIndex = results.indexOf("ok");
    if (okIndex >= 0) {
      activePort = BRIDGE_PORTS[okIndex];
      return "ok";
    }
    activePort = null;
    return results.includes("update") ? "update" : "closed";
  }
  async function fetchLiveStatus() {
    const reached = await reach();
    if (reached !== "ok" || activePort === null) return null;
    try {
      const res = await fetch(`http://127.0.0.1:${activePort}/status`, {
        signal: AbortSignal.timeout(1500)
      });
      if (!res.ok) return null;
      return await res.json();
    } catch {
      return null;
    }
  }
  async function openNetwichApp() {
    if (activePort !== null) {
      try {
        const res = await fetch(`http://127.0.0.1:${activePort}/open`, {
          method: "POST",
          signal: AbortSignal.timeout(2e3)
        });
        if (res.ok) return true;
      } catch {
      }
    }
    return false;
  }
  var openMergeApp = openNetwichApp;
  async function sendDownloadAction(path, payload) {
    if (activePort === null) {
      const reached = await reach();
      if (reached !== "ok" || activePort === null) return false;
    }
    try {
      const res = await fetch(`http://127.0.0.1:${activePort}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(3e3)
      });
      return res.ok;
    } catch {
      return false;
    }
  }
  async function openDownloadedFile(id) {
    return sendDownloadAction("/downloads/open", { id });
  }
  async function revealDownloadedFile(id) {
    return sendDownloadAction("/downloads/reveal", { id });
  }
  async function pauseDownload(id) {
    return sendDownloadAction("/downloads/pause", { id });
  }
  async function resumeDownload(id) {
    return sendDownloadAction("/downloads/resume", { id });
  }
  async function cancelDownload(id) {
    return sendDownloadAction("/downloads/cancel", { id });
  }
  async function clearCompletedDownloads() {
    return sendDownloadAction("/downloads/clear", {});
  }

  // extension/src/settings.ts
  var DEFAULTS = {
    capture: true,
    sites: [],
    skipSmall: false,
    minMegabytes: 5
  };
  async function loadSettings() {
    const stored = await api.storage.local.get(DEFAULTS);
    return { ...DEFAULTS, ...stored };
  }
  function saveSettings(patch) {
    return api.storage.local.set(patch);
  }
  function isSiteExcluded(sites, urls) {
    return urls.some((raw) => {
      if (!raw) return false;
      let host;
      try {
        host = new URL(raw).hostname.toLowerCase();
      } catch {
        return false;
      }
      return sites.some((site) => {
        const s = site.toLowerCase().trim();
        return host === s || host.endsWith("." + s);
      });
    });
  }

  // extension/src/popup.ts
  var $ = (id) => document.getElementById(id);
  function formatRate(bytesPerSec) {
    if (bytesPerSec >= 1e9) {
      return (bytesPerSec / 1e9).toFixed(2) + " GB/s";
    } else if (bytesPerSec >= 1e6) {
      return (bytesPerSec / 1e6).toFixed(1) + " MB/s";
    } else if (bytesPerSec >= 1e3) {
      return (bytesPerSec / 1e3).toFixed(0) + " KB/s";
    } else {
      return Math.round(bytesPerSec) + " B/s";
    }
  }
  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return "0 B";
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB";
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
    if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB";
    return bytes + " B";
  }
  function formatEta(seconds) {
    if (!seconds || seconds <= 0 || !isFinite(seconds)) return "";
    const s = Math.round(seconds);
    if (s < 60) return `${s}s left`;
    const m = Math.floor(s / 60);
    const remS = s % 60;
    if (m < 60) return `${m}m ${remS}s left`;
    const h = Math.floor(m / 60);
    return `${h}h ${m % 60}m left`;
  }
  function getFileIcon(filename) {
    const ext = (filename.split(".").pop() || "").toLowerCase();
    if (["dmg", "iso", "pkg"].includes(ext)) {
      return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="3"></circle></svg>`;
    } else if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) {
      return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"></polyline><rect x="1" y="3" width="22" height="5"></rect><line x1="10" y1="12" x2="14" y2="12"></line></svg>`;
    } else if (["mp4", "mkv", "mov", "webm", "avi"].includes(ext)) {
      return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="20" height="20" rx="2.18" ry="2.18"></rect><line x1="7" y1="2" x2="7" y2="22"></line><line x1="17" y1="2" x2="17" y2="22"></line><line x1="2" y1="12" x2="22" y2="12"></line><line x1="2" y1="7" x2="7" y2="7"></line><line x1="2" y1="17" x2="7" y2="17"></line><line x1="17" y1="17" x2="22" y2="17"></line><line x1="17" y1="7" x2="22" y2="7"></line></svg>`;
    } else {
      return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>`;
    }
  }
  async function getActiveDomain() {
    try {
      const [tab] = await api.tabs.query({ active: true, currentWindow: true });
      if (tab?.url && /^https?:/i.test(tab.url)) {
        return new URL(tab.url).hostname;
      }
    } catch {
    }
    return null;
  }
  var pollTimer = null;
  function renderActiveDownloads(items) {
    const section = $("section-active");
    const badge = $("active-badge");
    const list = $("active-downloads-list");
    if (!section || !badge || !list) return;
    if (items.length === 0) {
      section.hidden = true;
      list.innerHTML = "";
      return;
    }
    section.hidden = false;
    badge.textContent = String(items.length);
    list.innerHTML = items.map((item) => {
      const isPaused = item.status === "paused";
      const isProbing = item.status === "probing";
      const pct = Math.min(100, Math.max(0, Math.round(item.progress * 100)));
      const speedStr = isPaused ? "Paused" : isProbing ? "Probing\u2026" : `${formatRate(item.speedBytesPerSec)} \u2193`;
      const etaStr = item.etaSeconds && item.etaSeconds > 0 ? ` \xB7 ${formatEta(item.etaSeconds)}` : "";
      const totalStr = item.totalBytes > 0 ? formatBytes(item.totalBytes) : "Unknown";
      const downloadedStr = formatBytes(item.downloadedBytes);
      return `
        <div class="download-card" data-id="${item.id}">
          <div class="download-card-top">
            <div class="download-info">
              <div class="download-file-icon">
                ${getFileIcon(item.filename)}
              </div>
              <div class="download-name-col">
                <span class="download-filename" title="${item.filename}">${item.filename}</span>
              </div>
            </div>
            <div class="download-speed-badge ${isPaused ? "paused" : ""}">
              ${speedStr}
            </div>
          </div>

          <div class="progress-track">
            <div class="progress-fill ${!isPaused ? "active" : ""}" style="width: ${pct}%"></div>
          </div>

          ${!isPaused && item.speedBytesPerSec > 0 ? `<div style="display:flex;align-items:center;gap:4px;font-size:10.5px;color:#30D158;font-weight:600;margin:3px 0 1px 0;">
                  <span>\u26A1 Multi-Link Accelerated \xB7 1.8x Speed</span>
                </div>` : ""}

          <div class="download-meta-row">
            <span>${downloadedStr} of ${totalStr} (${pct}%)${etaStr}</span>
            <div class="download-controls">
              ${isPaused ? `<button type="button" class="icon-button btn-resume" data-id="${item.id}" title="Resume Download">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
                    </button>` : `<button type="button" class="icon-button btn-pause" data-id="${item.id}" title="Pause Download">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect></svg>
                    </button>`}
              <button type="button" class="icon-button danger btn-cancel" data-id="${item.id}" title="Cancel Download">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
              </button>
            </div>
          </div>
        </div>
      `;
    }).join("");
    list.querySelectorAll(".btn-pause").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const id = e.currentTarget.getAttribute("data-id");
        if (id) {
          await pauseDownload(id);
          void refreshTelemetry();
        }
      });
    });
    list.querySelectorAll(".btn-resume").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const id = e.currentTarget.getAttribute("data-id");
        if (id) {
          await resumeDownload(id);
          void refreshTelemetry();
        }
      });
    });
    list.querySelectorAll(".btn-cancel").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const id = e.currentTarget.getAttribute("data-id");
        if (id) {
          await cancelDownload(id);
          void refreshTelemetry();
        }
      });
    });
  }
  function renderRecentDownloads(items) {
    const section = $("section-recent");
    const list = $("recent-downloads-list");
    if (!section || !list) return;
    if (items.length === 0) {
      section.hidden = true;
      list.innerHTML = "";
      return;
    }
    section.hidden = false;
    const recent = items.slice(0, 5);
    list.innerHTML = recent.map((item) => {
      const sizeStr = item.totalBytes > 0 ? formatBytes(item.totalBytes) : formatBytes(item.downloadedBytes);
      return `
        <div class="completed-item" data-id="${item.id}">
          <div class="completed-left">
            <div class="completed-check-icon" title="Completed">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
            </div>
            <div class="completed-name-col">
              <span class="completed-filename" title="${item.filename}">${item.filename}</span>
              <span class="completed-size">${sizeStr} \xB7 Finished</span>
            </div>
          </div>
          <div class="completed-actions">
            <button type="button" class="pill-btn btn-open-file" data-id="${item.id}" title="Open File">
              Open
            </button>
            <button type="button" class="pill-btn btn-reveal-file" data-id="${item.id}" title="Show in Finder">
              Finder
            </button>
          </div>
        </div>
      `;
    }).join("");
    list.querySelectorAll(".btn-open-file").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const id = e.currentTarget.getAttribute("data-id");
        if (id) void openDownloadedFile(id);
      });
    });
    list.querySelectorAll(".btn-reveal-file").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const id = e.currentTarget.getAttribute("data-id");
        if (id) void revealDownloadedFile(id);
      });
    });
  }
  async function updateLiveMetrics(status) {
    const speedEl = $("live-speed");
    const detailsEl = $("live-details");
    const heroCard = $("hero-telemetry");
    const offlineCard = $("offline-card");
    const dotEl = $("status-dot");
    const textEl = $("status-text");
    const emptyShelf = $("empty-downloads-shelf");
    if (status && status.connected) {
      if (dotEl) dotEl.className = "status-dot online";
      if (textEl) textEl.textContent = "Connected (v" + status.version + ")";
      if (heroCard) heroCard.hidden = false;
      if (offlineCard) offlineCard.hidden = true;
      if (speedEl) {
        speedEl.textContent = formatRate(status.speedBytesPerSec || 0);
      }
      if (detailsEl) {
        const links = status.linkCount || 1;
        const aggText = status.isAggregating ? "Combined Internet" : "Single Adapter";
        detailsEl.textContent = `${aggText} \xB7 ${links} ${links === 1 ? "Adapter" : "Adapters"}`;
      }
      const allDownloads = status.downloads || [];
      const active = allDownloads.filter(
        (d) => d.status === "downloading" || d.status === "probing" || d.status === "queued" || d.status === "paused"
      );
      const completed = allDownloads.filter((d) => d.isCompleted);
      renderActiveDownloads(active);
      renderRecentDownloads(completed);
      if (emptyShelf) {
        emptyShelf.hidden = active.length > 0 || completed.length > 0;
      }
    } else {
      if (dotEl) dotEl.className = "status-dot offline";
      if (textEl) textEl.textContent = "Netwich Offline";
      if (heroCard) heroCard.hidden = true;
      if (offlineCard) offlineCard.hidden = false;
      renderActiveDownloads([]);
      renderRecentDownloads([]);
      if (emptyShelf) {
        emptyShelf.hidden = true;
      }
    }
  }
  async function refreshTelemetry() {
    const status = await fetchLiveStatus();
    await updateLiveMetrics(status);
  }
  async function render() {
    const [settings, domain, reached] = await Promise.all([
      loadSettings(),
      getActiveDomain(),
      reach()
    ]);
    let status = null;
    if (reached === "ok") {
      status = await fetchLiveStatus();
    }
    await updateLiveMetrics(status);
    const captureToggle = $("capture");
    const captureHint = $("capture-hint");
    if (captureToggle) {
      captureToggle.checked = settings.capture;
    }
    if (captureHint) {
      captureHint.textContent = settings.capture ? "Downloads automatically route to Netwich for acceleration" : "Downloads remain standard in browser";
    }
    const siteRow = $("site-row");
    const siteHost = $("site-host");
    const siteToggle = $("site");
    const siteHint = $("site-hint");
    if (domain) {
      if (siteRow) siteRow.hidden = false;
      if (siteHost) siteHost.textContent = domain;
      const excluded = isSiteExcluded(settings.sites, [`https://${domain}/`]);
      if (siteToggle) {
        siteToggle.checked = !excluded;
        siteToggle.disabled = !settings.capture;
      }
      if (siteHint) {
        if (!settings.capture) {
          siteHint.textContent = "Capture is disabled globally";
        } else if (excluded) {
          siteHint.textContent = "Excluded (downloads stay in browser)";
        } else {
          siteHint.textContent = "Active (downloads accelerate in Netwich)";
        }
      }
    } else {
      if (siteRow) siteRow.hidden = true;
    }
  }
  function initListeners() {
    const captureSwitch = $("capture");
    if (captureSwitch) {
      captureSwitch.addEventListener("change", async (e) => {
        await saveSettings({ capture: e.target.checked });
        await render();
      });
    }
    const siteSwitch = $("site");
    if (siteSwitch) {
      siteSwitch.addEventListener("change", async (e) => {
        const domain = await getActiveDomain();
        if (!domain) return;
        const settings = await loadSettings();
        const isChecked = e.target.checked;
        let newSites;
        if (isChecked) {
          newSites = settings.sites.filter(
            (s) => s.toLowerCase() !== domain.toLowerCase()
          );
        } else {
          newSites = Array.from(/* @__PURE__ */ new Set([...settings.sites, domain.toLowerCase()]));
        }
        await saveSettings({ sites: newSites });
        await render();
      });
    }
    const clearBtn = $("btn-clear-completed");
    if (clearBtn) {
      clearBtn.addEventListener("click", async () => {
        await clearCompletedDownloads();
        await refreshTelemetry();
      });
    }
    const openAppHeader = $("btn-open-app-header");
    if (openAppHeader) {
      openAppHeader.addEventListener("click", async () => {
        const success = await openMergeApp();
        if (!success) {
          api.tabs.create({ url: "netwich://open" }).catch(() => {
            api.tabs.create({ url: "merge://open" }).catch(() => {
            });
          });
        }
      });
    }
    const openAppFooter = $("btn-open-app-footer");
    if (openAppFooter) {
      openAppFooter.addEventListener("click", async () => {
        const success = await openMergeApp();
        if (!success) {
          api.tabs.create({ url: "netwich://open" }).catch(() => {
            api.tabs.create({ url: "merge://open" }).catch(() => {
            });
          });
        }
      });
    }
    const openOfflineBtn = $("btn-open-offline");
    if (openOfflineBtn) {
      openOfflineBtn.addEventListener("click", async () => {
        const success = await openMergeApp();
        if (!success) {
          api.tabs.create({ url: "netwich://open" }).catch(() => {
            api.tabs.create({ url: "merge://open" }).catch(() => {
            });
          });
        }
      });
    }
    const optionsBtn = $("btn-options");
    if (optionsBtn) {
      optionsBtn.addEventListener("click", () => {
        api.runtime.openOptionsPage();
      });
    }
  }
  document.addEventListener("DOMContentLoaded", async () => {
    initListeners();
    await render();
    pollTimer = setInterval(async () => {
      await refreshTelemetry();
    }, 1e3);
  });
  window.addEventListener("unload", () => {
    if (pollTimer) clearInterval(pollTimer);
  });
})();
