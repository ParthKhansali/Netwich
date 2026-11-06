(() => {
  // extension/src/bridge.ts
  var BRIDGE_PORTS = [19288, 19289, 19290];
  var BRIDGE_API = 1;
  var activePort = null;
  function getActivePort() {
    return activePort;
  }
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

  // extension/src/api.ts
  var api = globalThis.browser ?? chrome;

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
  function normalizeDomain(input) {
    const text = input.trim().toLowerCase().replace(/^\*\./, "");
    try {
      const host = new URL(/^[a-z]+:\/\//.test(text) ? text : `https://${text}`).hostname;
      return host.includes(".") || host === "localhost" ? host : null;
    } catch {
      return null;
    }
  }

  // extension/src/options.ts
  var $ = (id) => document.getElementById(id);
  async function renderConnection() {
    const reached = await reach();
    const dot = $("status-dot");
    const label = $("connection-label");
    const port = $("port-label");
    if (reached === "ok") {
      if (dot) dot.className = "status-dot online";
      if (label) label.textContent = "Connected to Netwich";
      if (port) port.textContent = `127.0.0.1:${getActivePort() || 19288}`;
    } else if (reached === "update") {
      if (dot) dot.className = "status-dot warning";
      if (label) label.textContent = "App Update Required";
      if (port) port.textContent = "";
    } else {
      if (dot) dot.className = "status-dot offline";
      if (label) label.textContent = "Netwich Not Running";
      if (port) port.textContent = "Start Netwich to enable";
    }
  }
  async function renderSettings() {
    const settings = await loadSettings();
    const captureBox = $("opt-capture");
    if (captureBox) captureBox.checked = settings.capture;
    const skipBox = $("opt-skip-small");
    const minMbInput = $("opt-min-mb");
    if (skipBox) skipBox.checked = settings.skipSmall;
    if (minMbInput) {
      minMbInput.value = String(settings.minMegabytes || 5);
      minMbInput.disabled = !settings.skipSmall;
    }
    const list = $("sites-list");
    const emptyState = $("no-sites");
    if (list) {
      list.innerHTML = "";
      if (settings.sites.length === 0) {
        if (emptyState) emptyState.hidden = false;
      } else {
        if (emptyState) emptyState.hidden = true;
        for (const site of settings.sites) {
          const item = document.createElement("li");
          item.className = "site-item";
          const nameSpan = document.createElement("span");
          nameSpan.className = "site-name";
          nameSpan.textContent = site;
          const removeBtn = document.createElement("button");
          removeBtn.type = "button";
          removeBtn.className = "btn-ghost-danger";
          removeBtn.textContent = "Remove";
          removeBtn.addEventListener("click", async () => {
            const fresh = settings.sites.filter((s) => s !== site);
            await saveSettings({ sites: fresh });
            await renderSettings();
          });
          item.appendChild(nameSpan);
          item.appendChild(removeBtn);
          list.appendChild(item);
        }
      }
    }
  }
  function initListeners() {
    const captureBox = $("opt-capture");
    if (captureBox) {
      captureBox.addEventListener("change", async (e) => {
        await saveSettings({ capture: e.target.checked });
        await renderSettings();
      });
    }
    const skipBox = $("opt-skip-small");
    if (skipBox) {
      skipBox.addEventListener("change", async (e) => {
        await saveSettings({ skipSmall: e.target.checked });
        await renderSettings();
      });
    }
    const minMbInput = $("opt-min-mb");
    if (minMbInput) {
      minMbInput.addEventListener("change", async (e) => {
        const val = Math.max(1, parseInt(e.target.value, 10) || 5);
        await saveSettings({ minMegabytes: val });
        await renderSettings();
      });
    }
    const addSiteBtn = $("btn-add-site");
    const siteInput = $("input-new-site");
    if (addSiteBtn && siteInput) {
      const handleAdd = async () => {
        const domain = normalizeDomain(siteInput.value);
        if (!domain) {
          alert("Please enter a valid website hostname (e.g. dropbox.com)");
          return;
        }
        const settings = await loadSettings();
        if (!settings.sites.includes(domain)) {
          const updated = [...settings.sites, domain];
          await saveSettings({ sites: updated });
        }
        siteInput.value = "";
        await renderSettings();
      };
      addSiteBtn.addEventListener("click", handleAdd);
      siteInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          handleAdd();
        }
      });
    }
    const checkConnBtn = $("btn-check-connection");
    if (checkConnBtn) {
      checkConnBtn.addEventListener("click", async () => {
        await renderConnection();
      });
    }
    const openAppBtn = $("btn-open-app");
    if (openAppBtn) {
      openAppBtn.addEventListener("click", async () => {
        await openMergeApp();
      });
    }
  }
  document.addEventListener("DOMContentLoaded", async () => {
    initListeners();
    await Promise.all([renderConnection(), renderSettings()]);
  });
})();
