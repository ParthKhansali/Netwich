(() => {
  // extension/src/api.ts
  var api = globalThis.browser ?? chrome;

  // extension/src/bridge.ts
  var BRIDGE_PORTS = [19288, 19289, 19290];
  var BRIDGE_API = 1;
  var BRIDGE_TIMEOUT_MS = 6e3;
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
  async function openMergeApp() {
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
  async function sendDownloadHandoff(request) {
    if (await reach() !== "ok" || activePort === null) return "closed";
    const port = activePort;
    try {
      const res = await fetch(`http://127.0.0.1:${port}/add`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(request),
        signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS)
      });
      if (!res.ok) return "kept";
      const body = await res.json();
      return { port, token: body.token };
    } catch (err) {
      if (err instanceof DOMException && err.name === "TimeoutError") {
        return "kept";
      }
      return "closed";
    }
  }
  async function confirmDownloadHandoff(handoff) {
    try {
      const res = await fetch(`http://127.0.0.1:${handoff.port}/confirm`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: handoff.token }),
        signal: AbortSignal.timeout(3e3)
      });
      return res.ok;
    } catch {
      return false;
    }
  }
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
  async function revealDownloadedFile(id) {
    return sendDownloadAction("/downloads/reveal", { id });
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

  // extension/src/background.ts
  var MENU_ID = "download-with-netwich";
  var CHECK_ALARM = "check-netwich-status";
  var openedAt = /* @__PURE__ */ new Map();
  var notifiedCompletedIds = /* @__PURE__ */ new Set();
  var hasInitializedDownloads = false;
  var ICON = { 16: "icons/icon-16.png", 32: "icons/icon-32.png" };
  var ICON_OFF = { 16: "icons/icon-off-16.png", 32: "icons/icon-off-32.png" };
  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return "0 B";
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB";
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
    if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB";
    return bytes + " B";
  }
  function showNotification(id, options) {
    if (api.notifications?.create) {
      api.notifications.create(id, {
        type: "basic",
        iconUrl: options.iconUrl || "icons/icon-128.png",
        title: options.title,
        message: options.message,
        priority: 2
      }).catch(() => {
      });
    }
  }
  async function sendToActiveTabs(message) {
    const tabs = await api.tabs.query({ active: true }).catch(() => []);
    for (const tab of tabs) {
      if (!tab.id || !tab.url || tab.url.startsWith("chrome://") || tab.url.startsWith("about:") || tab.url.startsWith("edge://")) {
        continue;
      }
      try {
        await api.tabs.sendMessage(tab.id, message);
      } catch {
        try {
          if (api.scripting?.executeScript) {
            await api.scripting.executeScript({
              target: { tabId: tab.id },
              files: ["content.js"]
            });
            await api.tabs.sendMessage(tab.id, message).catch(() => {
            });
          }
        } catch {
        }
      }
    }
  }
  async function checkDownloadsProgress() {
    const status = await fetchLiveStatus();
    if (!status) return;
    const downloads = status.downloads || [];
    const active = downloads.filter((d) => d.status === "downloading" || d.status === "probing" || d.status === "queued");
    const completed = downloads.filter((d) => d.isCompleted);
    if (!hasInitializedDownloads) {
      hasInitializedDownloads = true;
      for (const d of completed) {
        notifiedCompletedIds.add(d.id);
      }
    } else {
      for (const d of completed) {
        if (!notifiedCompletedIds.has(d.id)) {
          notifiedCompletedIds.add(d.id);
          showNotification(`complete-${d.id}`, {
            title: "Download Complete",
            message: `${d.filename} (${formatBytes(d.totalBytes)}) \xB7 Click to reveal in Finder`,
            iconUrl: "icons/icon-128.png"
          });
          api.action.setBadgeText({ text: "\u2713" }).catch(() => {
          });
          api.action.setBadgeBackgroundColor({ color: "#30D158" }).catch(() => {
          });
          setTimeout(() => {
            void updateBadge();
          }, 4e3);
        }
      }
    }
    if (active.length > 0) {
      api.action.setBadgeText({ text: String(active.length) }).catch(() => {
      });
      api.action.setBadgeBackgroundColor({ color: "#0A84FF" }).catch(() => {
      });
    } else if (api.action.getBadgeText) {
      const currentText = await api.action.getBadgeText({}).catch(() => "");
      if (currentText !== "\u2713") {
        api.action.setBadgeText({ text: "" }).catch(() => {
        });
      }
    }
    if (downloads.length > 0) {
      const primary = active[0] || (completed.length > 0 ? completed[completed.length - 1] : null);
      if (primary) {
        await sendToActiveTabs({
          type: "NETWICH_DOWNLOAD_PROGRESS",
          download: {
            id: primary.id,
            filename: primary.filename,
            totalBytes: primary.totalBytes,
            downloadedBytes: primary.downloadedBytes,
            progress: primary.progress,
            speedBytesPerSec: primary.speedBytesPerSec,
            status: primary.status,
            isCompleted: primary.isCompleted,
            linksCount: status.linkCount || 1
          }
        });
      }
    }
    if (active.length > 0) {
      setTimeout(checkDownloadsProgress, 750);
    }
  }
  function getStoreId(source) {
    return source.cookieStoreId ?? (source.incognito ? "1" : void 0);
  }
  function getHostnames(url) {
    try {
      return url ? [new URL(url).hostname] : [];
    } catch {
      return [];
    }
  }
  async function collectBrowserContext(urls, storeId, referer) {
    const cookieMap = /* @__PURE__ */ new Map();
    const hosts = [...urls, referer].flatMap(getHostnames);
    for (const u of new Set(urls)) {
      if (!u || !/^https?:/i.test(u)) continue;
      try {
        const found = await api.cookies.getAll({ url: u, storeId }).catch(async () => {
          const all = await api.cookies.getAll({ storeId, firstPartyDomain: null });
          return all.filter((c) => {
            return !c.firstPartyDomain || hosts.some((h) => h === c.firstPartyDomain || h.endsWith("." + c.firstPartyDomain));
          });
        });
        for (const c of found) {
          cookieMap.set(`${c.domain}
${c.path}
${c.name}`, {
            name: c.name,
            value: c.value,
            domain: c.domain,
            hostOnly: c.hostOnly,
            path: c.path,
            secure: c.secure
          });
        }
      } catch {
      }
    }
    return {
      cookies: Array.from(cookieMap.values()),
      ...referer && /^https?:/i.test(referer) ? { referer } : {},
      userAgent: navigator.userAgent,
      name: "Netwich Browser Extension"
    };
  }
  async function updateBadge(reached) {
    const settings = await loadSettings();
    reached ??= await reach();
    const isOk = settings.capture && reached === "ok";
    const title = !settings.capture ? "Netwich: Capture is off" : reached === "closed" ? "Netwich is offline: downloads stay in browser" : reached === "update" ? "Update Netwich App to connect" : "Netwich: Multi-Connection Accelerator Active";
    await api.action.setIcon({ path: isOk ? ICON : ICON_OFF }).catch(() => {
    });
    await api.action.setTitle({ title }).catch(() => {
    });
  }
  async function captureDownload(item) {
    const settings = await loadSettings();
    const targetUrl = item.finalUrl || item.url;
    if (!settings.capture || !targetUrl || !/^https?:/i.test(targetUrl)) {
      return false;
    }
    if (isSiteExcluded(settings.sites, [item.url, item.finalUrl, item.referrer])) {
      return false;
    }
    const rawFilename = (item.filename || "").split(/[\\/]/).pop() || void 0;
    const minBytes = settings.skipSmall ? settings.minMegabytes * 1024 * 1024 : void 0;
    const request = {
      url: targetUrl,
      pageUrl: item.referrer || void 0,
      fileName: rawFilename,
      minBytes,
      browser: await collectBrowserContext(
        [item.url, item.finalUrl],
        getStoreId(item),
        item.referrer
      )
    };
    const handoff = await sendDownloadHandoff(request);
    if (typeof handoff === "string") {
      if (handoff === "closed") await updateBadge("closed");
      return false;
    }
    await api.downloads.cancel(item.id).catch(() => {
    });
    const [after] = await api.downloads.search({ id: item.id }).catch(() => []);
    if (after?.state === "complete") return false;
    await api.downloads.erase({ id: item.id }).catch(() => {
    });
    const confirmed = await confirmDownloadHandoff(handoff);
    await closeEmptyTab([item.url, item.finalUrl]);
    await updateBadge(confirmed ? "ok" : void 0);
    if (confirmed) {
      showNotification(`start-${Date.now()}`, {
        title: "Accelerating with Netwich",
        message: `${rawFilename || "File"} \xB7 Multi-connection download started`,
        iconUrl: "icons/icon-128.png"
      });
      await sendToActiveTabs({
        type: "NETWICH_SHOW_DOWNLOAD",
        download: {
          id: typeof handoff === "object" && handoff.id || "new",
          filename: rawFilename || "Download",
          totalBytes: item.totalBytes || 0,
          downloadedBytes: 0,
          progress: 0,
          speedBytesPerSec: 0,
          status: "probing",
          isCompleted: false
        }
      });
      void checkDownloadsProgress();
    }
    return true;
  }
  async function closeEmptyTab(urls) {
    const recent = Date.now() - 3e4;
    try {
      const tabs = await api.tabs.query({});
      for (const tab of tabs) {
        const shows = tab.pendingUrl ?? tab.url;
        if (tab.id === void 0 || shows === void 0 || !urls.includes(shows)) continue;
        if ((openedAt.get(tab.id) ?? 0) < recent) continue;
        await api.tabs.remove(tab.id).catch(() => {
        });
      }
    } catch {
    }
  }
  async function handleContextMenuClick(info, tab) {
    const url = info.linkUrl;
    if (!url) return;
    const request = {
      url,
      pageUrl: info.pageUrl,
      browser: await collectBrowserContext([url], tab && getStoreId(tab), info.pageUrl)
    };
    let handoff = await sendDownloadHandoff(request);
    if (handoff === "closed") {
      await openMergeApp();
      handoff = await sendDownloadHandoff(request);
    }
    if (typeof handoff !== "string") {
      const confirmed = await confirmDownloadHandoff(handoff);
      await updateBadge(confirmed ? "ok" : void 0);
      if (confirmed) {
        showNotification(`start-${Date.now()}`, {
          title: "Accelerating with Netwich",
          message: "Link added to Netwich download engine",
          iconUrl: "icons/icon-128.png"
        });
        await sendToActiveTabs({
          type: "NETWICH_SHOW_DOWNLOAD",
          download: {
            id: typeof handoff === "object" && handoff.id || "new",
            filename: url.split("/").pop()?.split("?")[0] || "Download",
            totalBytes: 0,
            downloadedBytes: 0,
            progress: 0,
            speedBytesPerSec: 0,
            status: "probing",
            isCompleted: false
          }
        });
        void checkDownloadsProgress();
      }
    }
  }
  function initExtension() {
    api.contextMenus.removeAll().then(() => {
      api.contextMenus.create({
        id: MENU_ID,
        title: "Download with Netwich",
        contexts: ["link"]
      });
    }).catch(() => {
    });
    api.alarms.create(CHECK_ALARM, { periodInMinutes: 0.5 }).catch(() => {
    });
    setInterval(checkDownloadsProgress, 2e3);
    void updateBadge();
    void checkDownloadsProgress();
  }
  if (api.notifications?.onClicked) {
    api.notifications.onClicked.addListener((notificationId) => {
      if (notificationId.startsWith("complete-")) {
        const downloadId = notificationId.replace("complete-", "");
        void revealDownloadedFile(downloadId);
      } else if (notificationId.startsWith("start-")) {
        void openMergeApp();
      }
    });
  }
  var determining = api.downloads.onDeterminingFilename;
  if (determining) {
    determining.addListener((item, suggest) => {
      void captureDownload(item).then((handled) => {
        if (!handled) suggest();
      });
      return true;
    });
  } else {
    api.downloads.onCreated.addListener((item) => {
      void captureDownload(item);
    });
  }
  api.runtime.onInstalled.addListener(initExtension);
  api.runtime.onStartup.addListener(initExtension);
  initExtension();
  api.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === CHECK_ALARM) void updateBadge();
  });
  api.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId === MENU_ID) void handleContextMenuClick(info, tab);
  });
  api.tabs.onCreated.addListener((tab) => {
    if (tab.id !== void 0) openedAt.set(tab.id, Date.now());
  });
  api.storage.onChanged.addListener(() => {
    void updateBadge();
  });
  api.runtime.onMessage.addListener((message) => {
    if (message.type === "OPEN_APP" || message.wakeMerge || message.wakeNetwich) {
      void openMergeApp().then((ok) => updateBadge(ok ? "ok" : "closed"));
    }
    if (message.checkMerge || message.checkNetwich) void updateBadge();
  });
})();
