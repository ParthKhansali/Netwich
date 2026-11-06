import { api } from './api';
import {
  reach,
  fetchLiveStatus,
  sendDownloadHandoff,
  confirmDownloadHandoff,
  openMergeApp,
  revealDownloadedFile,
  AddDownloadRequest,
  BridgeDownloadItem
} from './bridge';
import { loadSettings, isSiteExcluded } from './settings';

const MENU_ID = 'download-with-netwich';
const CHECK_ALARM = 'check-netwich-status';
const openedAt = new Map<number, number>();

const notifiedCompletedIds = new Set<string>();
let hasInitializedDownloads = false;

const ICON = { 16: 'icons/icon-16.png', 32: 'icons/icon-32.png' };
const ICON_OFF = { 16: 'icons/icon-off-16.png', 32: 'icons/icon-off-32.png' };

function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 B';
  if (bytes >= 1_073_741_824) return (bytes / 1_073_741_824).toFixed(1) + ' GB';
  if (bytes >= 1_048_576) return (bytes / 1_048_576).toFixed(1) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return bytes + ' B';
}

function showNotification(id: string, options: { title: string; message: string; iconUrl?: string }) {
  if (api.notifications?.create) {
    api.notifications.create(id, {
      type: 'basic',
      iconUrl: options.iconUrl || 'icons/icon-128.png',
      title: options.title,
      message: options.message,
      priority: 2
    }).catch(() => {});
  }
}

async function sendToActiveTabs(message: any) {
  const tabs = await api.tabs.query({ active: true }).catch(() => []);
  for (const tab of tabs) {
    if (!tab.id || !tab.url || tab.url.startsWith('chrome://') || tab.url.startsWith('about:') || tab.url.startsWith('edge://')) {
      continue;
    }
    try {
      await api.tabs.sendMessage(tab.id, message);
    } catch {
      // Content script may not be loaded on this tab yet, dynamically inject it
      try {
        if (api.scripting?.executeScript) {
          await api.scripting.executeScript({
            target: { tabId: tab.id },
            files: ['content.js']
          });
          await api.tabs.sendMessage(tab.id, message).catch(() => {});
        }
      } catch {}
    }
  }
}

async function checkDownloadsProgress() {
  const status = await fetchLiveStatus();
  if (!status) return;

  const downloads = status.downloads || [];
  const active = downloads.filter((d) => d.status === 'downloading' || d.status === 'probing' || d.status === 'queued');
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
          title: 'Download Complete',
          message: `${d.filename} (${formatBytes(d.totalBytes)}) · Click to reveal in Finder`,
          iconUrl: 'icons/icon-128.png'
        });

        api.action.setBadgeText({ text: '✓' }).catch(() => {});
        api.action.setBadgeBackgroundColor({ color: '#30D158' }).catch(() => {});
        setTimeout(() => {
          void updateBadge();
        }, 4000);
      }
    }
  }

  if (active.length > 0) {
    api.action.setBadgeText({ text: String(active.length) }).catch(() => {});
    api.action.setBadgeBackgroundColor({ color: '#0A84FF' }).catch(() => {});
  } else if (api.action.getBadgeText) {
    const currentText = await api.action.getBadgeText({}).catch(() => '');
    if (currentText !== '✓') {
      api.action.setBadgeText({ text: '' }).catch(() => {});
    }
  }

  // Update floating HUD on the active browser tab
  if (downloads.length > 0) {
    const primary = active[0] || (completed.length > 0 ? completed[completed.length - 1] : null);
    if (primary) {
      await sendToActiveTabs({
        type: 'NETWICH_DOWNLOAD_PROGRESS',
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

  // Adaptive polling: poll every 750ms while downloads are active for smooth native-like HUD updates
  if (active.length > 0) {
    setTimeout(checkDownloadsProgress, 750);
  }
}

function getStoreId(source: any): string | undefined {
  return source.cookieStoreId ?? (source.incognito ? '1' : undefined);
}

function getHostnames(url: string | undefined): string[] {
  try {
    return url ? [new URL(url).hostname] : [];
  } catch {
    return [];
  }
}

async function collectBrowserContext(urls: string[], storeId?: string, referer?: string) {
  const cookieMap = new Map<string, any>();
  const hosts = [...urls, referer].flatMap(getHostnames);

  for (const u of new Set(urls)) {
    if (!u || !/^https?:/i.test(u)) continue;
    try {
      const found = await api.cookies.getAll({ url: u, storeId }).catch(async () => {
        const all = await api.cookies.getAll({ storeId, firstPartyDomain: null as any });
        return all.filter((c: any) => {
          return !c.firstPartyDomain || hosts.some((h) => h === c.firstPartyDomain || h.endsWith('.' + c.firstPartyDomain));
        });
      });

      for (const c of found) {
        cookieMap.set(`${c.domain}\n${c.path}\n${c.name}`, {
          name: c.name,
          value: c.value,
          domain: c.domain,
          hostOnly: c.hostOnly,
          path: c.path,
          secure: c.secure
        });
      }
    } catch {}
  }

  return {
    cookies: Array.from(cookieMap.values()),
    ...(referer && /^https?:/i.test(referer) ? { referer } : {}),
    userAgent: navigator.userAgent,
    name: 'Netwich Browser Extension'
  };
}

async function updateBadge(reached?: 'ok' | 'update' | 'closed') {
  const settings = await loadSettings();
  reached ??= await reach();
  const isOk = settings.capture && reached === 'ok';

  const title = !settings.capture
    ? 'Netwich: Capture is off'
    : reached === 'closed'
    ? 'Netwich is offline: downloads stay in browser'
    : reached === 'update'
    ? 'Update Netwich App to connect'
    : 'Netwich: Multi-Connection Accelerator Active';

  await api.action.setIcon({ path: isOk ? ICON : ICON_OFF }).catch(() => {});
  await api.action.setTitle({ title }).catch(() => {});
}

async function captureDownload(item: any): Promise<boolean> {
  const settings = await loadSettings();
  const targetUrl = item.finalUrl || item.url;

  if (!settings.capture || !targetUrl || !/^https?:/i.test(targetUrl)) {
    return false;
  }

  if (isSiteExcluded(settings.sites, [item.url, item.finalUrl, item.referrer])) {
    return false;
  }

  const rawFilename = (item.filename || '').split(/[\\/]/).pop() || undefined;
  const minBytes = settings.skipSmall ? settings.minMegabytes * 1024 * 1024 : undefined;

  const request: AddDownloadRequest = {
    url: targetUrl,
    pageUrl: item.referrer || undefined,
    fileName: rawFilename,
    minBytes,
    browser: await collectBrowserContext(
      [item.url, item.finalUrl],
      getStoreId(item),
      item.referrer
    )
  };

  const handoff = await sendDownloadHandoff(request);
  if (typeof handoff === 'string') {
    if (handoff === 'closed') await updateBadge('closed');
    return false;
  }

  // Cancel in browser
  await api.downloads.cancel(item.id).catch(() => {});
  const [after] = await api.downloads.search({ id: item.id }).catch(() => []);
  if (after?.state === 'complete') return false;

  await api.downloads.erase({ id: item.id }).catch(() => {});
  const confirmed = await confirmDownloadHandoff(handoff);

  await closeEmptyTab([item.url, item.finalUrl]);
  await updateBadge(confirmed ? 'ok' : undefined);

  if (confirmed) {
    showNotification(`start-${Date.now()}`, {
      title: 'Accelerating with Netwich',
      message: `${rawFilename || 'File'} · Multi-connection download started`,
      iconUrl: 'icons/icon-128.png'
    });

    // Broadcast floating HUD to active browser tabs
    await sendToActiveTabs({
      type: 'NETWICH_SHOW_DOWNLOAD',
      download: {
        id: (typeof handoff === 'object' && handoff.id) || 'new',
        filename: rawFilename || 'Download',
        totalBytes: item.totalBytes || 0,
        downloadedBytes: 0,
        progress: 0,
        speedBytesPerSec: 0,
        status: 'probing',
        isCompleted: false
      }
    });

    void checkDownloadsProgress();
  }
  return true;
}

async function closeEmptyTab(urls: (string | undefined)[]) {
  const recent = Date.now() - 30_000;
  try {
    const tabs = await api.tabs.query({});
    for (const tab of tabs) {
      const shows = (tab as any).pendingUrl ?? tab.url;
      if (tab.id === undefined || shows === undefined || !urls.includes(shows)) continue;
      if ((openedAt.get(tab.id) ?? 0) < recent) continue;
      await api.tabs.remove(tab.id).catch(() => {});
    }
  } catch {}
}

async function handleContextMenuClick(info: any, tab: any) {
  const url = info.linkUrl;
  if (!url) return;

  const request: AddDownloadRequest = {
    url,
    pageUrl: info.pageUrl,
    browser: await collectBrowserContext([url], tab && getStoreId(tab), info.pageUrl)
  };

  let handoff = await sendDownloadHandoff(request);
  if (handoff === 'closed') {
    await openMergeApp();
    handoff = await sendDownloadHandoff(request);
  }

  if (typeof handoff !== 'string') {
    const confirmed = await confirmDownloadHandoff(handoff);
    await updateBadge(confirmed ? 'ok' : undefined);
    if (confirmed) {
      showNotification(`start-${Date.now()}`, {
        title: 'Accelerating with Netwich',
        message: 'Link added to Netwich download engine',
        iconUrl: 'icons/icon-128.png'
      });
      await sendToActiveTabs({
        type: 'NETWICH_SHOW_DOWNLOAD',
        download: {
          id: (typeof handoff === 'object' && (handoff as any).id) || 'new',
          filename: url.split('/').pop()?.split('?')[0] || 'Download',
          totalBytes: 0,
          downloadedBytes: 0,
          progress: 0,
          speedBytesPerSec: 0,
          status: 'probing',
          isCompleted: false
        }
      });
      void checkDownloadsProgress();
    }
  }
}

function initExtension() {
  // Setup context menu
  api.contextMenus.removeAll().then(() => {
    api.contextMenus.create({
      id: MENU_ID,
      title: 'Download with Netwich',
      contexts: ['link']
    });
  }).catch(() => {});

  // Setup recurring alarm and active interval poller
  api.alarms.create(CHECK_ALARM, { periodInMinutes: 0.5 }).catch(() => {});
  setInterval(checkDownloadsProgress, 2000);
  void updateBadge();
  void checkDownloadsProgress();
}

// Notification click handler
if (api.notifications?.onClicked) {
  api.notifications.onClicked.addListener((notificationId: string) => {
    if (notificationId.startsWith('complete-')) {
      const downloadId = notificationId.replace('complete-', '');
      void revealDownloadedFile(downloadId);
    } else if (notificationId.startsWith('start-')) {
      void openMergeApp();
    }
  });
}

// Download interceptor
const determining = api.downloads.onDeterminingFilename;
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
  if (tab.id !== undefined) openedAt.set(tab.id, Date.now());
});

api.storage.onChanged.addListener(() => {
  void updateBadge();
});

api.runtime.onMessage.addListener((message) => {
  if (message.type === 'OPEN_APP' || message.wakeMerge || message.wakeNetwich) {
    void openMergeApp().then((ok) => updateBadge(ok ? 'ok' : 'closed'));
  }
  if (message.checkMerge || message.checkNetwich) void updateBadge();
});

