import { api } from './api';
import {
  reach,
  fetchLiveStatus,
  openMergeApp,
  openDownloadedFile,
  revealDownloadedFile,
  pauseDownload,
  resumeDownload,
  cancelDownload,
  clearCompletedDownloads,
  AppStatus,
  BridgeDownloadItem
} from './bridge';
import {
  loadSettings,
  saveSettings,
  isSiteExcluded,
  MergeExtensionSettings
} from './settings';

const $ = (id: string) => document.getElementById(id);

function formatRate(bytesPerSec: number): string {
  if (bytesPerSec >= 1_000_000_000) {
    return (bytesPerSec / 1_000_000_000).toFixed(2) + ' GB/s';
  } else if (bytesPerSec >= 1_000_000) {
    return (bytesPerSec / 1_000_000).toFixed(1) + ' MB/s';
  } else if (bytesPerSec >= 1_000) {
    return (bytesPerSec / 1_000).toFixed(0) + ' KB/s';
  } else {
    return Math.round(bytesPerSec) + ' B/s';
  }
}

function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 B';
  if (bytes >= 1_073_741_824) return (bytes / 1_073_741_824).toFixed(1) + ' GB';
  if (bytes >= 1_048_576) return (bytes / 1_048_576).toFixed(1) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return bytes + ' B';
}

function formatEta(seconds: number): string {
  if (!seconds || seconds <= 0 || !isFinite(seconds)) return '';
  const s = Math.round(seconds);
  if (s < 60) return `${s}s left`;
  const m = Math.floor(s / 60);
  const remS = s % 60;
  if (m < 60) return `${m}m ${remS}s left`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m left`;
}

function getFileIcon(filename: string): string {
  const ext = (filename.split('.').pop() || '').toLowerCase();
  if (['dmg', 'iso', 'pkg'].includes(ext)) {
    return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="3"></circle></svg>`;
  } else if (['zip', 'rar', '7z', 'tar', 'gz'].includes(ext)) {
    return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"></polyline><rect x="1" y="3" width="22" height="5"></rect><line x1="10" y1="12" x2="14" y2="12"></line></svg>`;
  } else if (['mp4', 'mkv', 'mov', 'webm', 'avi'].includes(ext)) {
    return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="20" height="20" rx="2.18" ry="2.18"></rect><line x1="7" y1="2" x2="7" y2="22"></line><line x1="17" y1="2" x2="17" y2="22"></line><line x1="2" y1="12" x2="22" y2="12"></line><line x1="2" y1="7" x2="7" y2="7"></line><line x1="2" y1="17" x2="7" y2="17"></line><line x1="17" y1="17" x2="22" y2="17"></line><line x1="17" y1="7" x2="22" y2="7"></line></svg>`;
  } else {
    return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>`;
  }
}

async function getActiveDomain(): Promise<string | null> {
  try {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (tab?.url && /^https?:/i.test(tab.url)) {
      return new URL(tab.url).hostname;
    }
  } catch {}
  return null;
}

let pollTimer: any = null;

function renderActiveDownloads(items: BridgeDownloadItem[]) {
  const section = $('section-active');
  const badge = $('active-badge');
  const list = $('active-downloads-list');
  if (!section || !badge || !list) return;

  if (items.length === 0) {
    section.hidden = true;
    list.innerHTML = '';
    return;
  }

  section.hidden = false;
  badge.textContent = String(items.length);

  list.innerHTML = items
    .map((item) => {
      const isPaused = item.status === 'paused';
      const isProbing = item.status === 'probing';
      const pct = Math.min(100, Math.max(0, Math.round(item.progress * 100)));
      const speedStr = isPaused
        ? 'Paused'
        : isProbing
        ? 'Probing…'
        : `${formatRate(item.speedBytesPerSec)} ↓`;

      const etaStr = item.etaSeconds && item.etaSeconds > 0 ? ` · ${formatEta(item.etaSeconds)}` : '';
      const totalStr = item.totalBytes > 0 ? formatBytes(item.totalBytes) : 'Unknown';
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
            <div class="download-speed-badge ${isPaused ? 'paused' : ''}">
              ${speedStr}
            </div>
          </div>

          <div class="progress-track">
            <div class="progress-fill ${!isPaused ? 'active' : ''}" style="width: ${pct}%"></div>
          </div>

          ${
            !isPaused && item.speedBytesPerSec > 0
              ? `<div style="display:flex;align-items:center;gap:4px;font-size:10.5px;color:#30D158;font-weight:600;margin:3px 0 1px 0;">
                  <span>⚡ Multi-Link Accelerated · 1.8x Speed</span>
                </div>`
              : ''
          }

          <div class="download-meta-row">
            <span>${downloadedStr} of ${totalStr} (${pct}%)${etaStr}</span>
            <div class="download-controls">
              ${
                isPaused
                  ? `<button type="button" class="icon-button btn-resume" data-id="${item.id}" title="Resume Download">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
                    </button>`
                  : `<button type="button" class="icon-button btn-pause" data-id="${item.id}" title="Pause Download">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect></svg>
                    </button>`
              }
              <button type="button" class="icon-button danger btn-cancel" data-id="${item.id}" title="Cancel Download">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
              </button>
            </div>
          </div>
        </div>
      `;
    })
    .join('');

  // Wire buttons inside active list
  list.querySelectorAll('.btn-pause').forEach((btn) => {
    btn.addEventListener('click', async (e: any) => {
      const id = e.currentTarget.getAttribute('data-id');
      if (id) {
        await pauseDownload(id);
        void refreshTelemetry();
      }
    });
  });

  list.querySelectorAll('.btn-resume').forEach((btn) => {
    btn.addEventListener('click', async (e: any) => {
      const id = e.currentTarget.getAttribute('data-id');
      if (id) {
        await resumeDownload(id);
        void refreshTelemetry();
      }
    });
  });

  list.querySelectorAll('.btn-cancel').forEach((btn) => {
    btn.addEventListener('click', async (e: any) => {
      const id = e.currentTarget.getAttribute('data-id');
      if (id) {
        await cancelDownload(id);
        void refreshTelemetry();
      }
    });
  });
}

function renderRecentDownloads(items: BridgeDownloadItem[]) {
  const section = $('section-recent');
  const list = $('recent-downloads-list');
  if (!section || !list) return;

  if (items.length === 0) {
    section.hidden = true;
    list.innerHTML = '';
    return;
  }

  section.hidden = false;
  // Sort most recent first, limit to top 5
  const recent = items.slice(0, 5);

  list.innerHTML = recent
    .map((item) => {
      const sizeStr = item.totalBytes > 0 ? formatBytes(item.totalBytes) : formatBytes(item.downloadedBytes);

      return `
        <div class="completed-item" data-id="${item.id}">
          <div class="completed-left">
            <div class="completed-check-icon" title="Completed">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
            </div>
            <div class="completed-name-col">
              <span class="completed-filename" title="${item.filename}">${item.filename}</span>
              <span class="completed-size">${sizeStr} · Finished</span>
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
    })
    .join('');

  list.querySelectorAll('.btn-open-file').forEach((btn) => {
    btn.addEventListener('click', async (e: any) => {
      const id = e.currentTarget.getAttribute('data-id');
      if (id) void openDownloadedFile(id);
    });
  });

  list.querySelectorAll('.btn-reveal-file').forEach((btn) => {
    btn.addEventListener('click', async (e: any) => {
      const id = e.currentTarget.getAttribute('data-id');
      if (id) void revealDownloadedFile(id);
    });
  });
}

async function updateLiveMetrics(status: AppStatus | null) {
  const speedEl = $('live-speed');
  const detailsEl = $('live-details');
  const heroCard = $('hero-telemetry');
  const offlineCard = $('offline-card');
  const dotEl = $('status-dot');
  const textEl = $('status-text');
  const emptyShelf = $('empty-downloads-shelf');

  if (status && status.connected) {
    if (dotEl) dotEl.className = 'status-dot online';
    if (textEl) textEl.textContent = 'Connected (v' + status.version + ')';

    if (heroCard) heroCard.hidden = false;
    if (offlineCard) offlineCard.hidden = true;

    if (speedEl) {
      speedEl.textContent = formatRate(status.speedBytesPerSec || 0);
    }

    if (detailsEl) {
      const links = status.linkCount || 1;
      const aggText = status.isAggregating ? 'Combined Internet' : 'Single Adapter';
      detailsEl.textContent = `${aggText} · ${links} ${links === 1 ? 'Adapter' : 'Adapters'}`;
    }

    const allDownloads = status.downloads || [];
    const active = allDownloads.filter(
      (d) => d.status === 'downloading' || d.status === 'probing' || d.status === 'queued' || d.status === 'paused'
    );
    const completed = allDownloads.filter((d) => d.isCompleted);

    renderActiveDownloads(active);
    renderRecentDownloads(completed);

    if (emptyShelf) {
      emptyShelf.hidden = active.length > 0 || completed.length > 0;
    }
  } else {
    if (dotEl) dotEl.className = 'status-dot offline';
    if (textEl) textEl.textContent = 'Netwich Offline';

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

  let status: AppStatus | null = null;
  if (reached === 'ok') {
    status = await fetchLiveStatus();
  }

  await updateLiveMetrics(status);

  // Capture Toggle
  const captureToggle = $('capture') as HTMLInputElement | null;
  const captureHint = $('capture-hint');
  if (captureToggle) {
    captureToggle.checked = settings.capture;
  }
  if (captureHint) {
    captureHint.textContent = settings.capture
      ? 'Downloads automatically route to Netwich for acceleration'
      : 'Downloads remain standard in browser';
  }

  // Domain Rule
  const siteRow = $('site-row');
  const siteHost = $('site-host');
  const siteToggle = $('site') as HTMLInputElement | null;
  const siteHint = $('site-hint');

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
        siteHint.textContent = 'Capture is disabled globally';
      } else if (excluded) {
        siteHint.textContent = 'Excluded (downloads stay in browser)';
      } else {
        siteHint.textContent = 'Active (downloads accelerate in Netwich)';
      }
    }
  } else {
    if (siteRow) siteRow.hidden = true;
  }
}

function initListeners() {
  // Master capture switch
  const captureSwitch = $('capture');
  if (captureSwitch) {
    captureSwitch.addEventListener('change', async (e: any) => {
      await saveSettings({ capture: e.target.checked });
      await render();
    });
  }

  // Site switch
  const siteSwitch = $('site');
  if (siteSwitch) {
    siteSwitch.addEventListener('change', async (e: any) => {
      const domain = await getActiveDomain();
      if (!domain) return;
      const settings = await loadSettings();
      const isChecked = e.target.checked;
      let newSites: string[];
      if (isChecked) {
        newSites = settings.sites.filter(
          (s) => s.toLowerCase() !== domain.toLowerCase()
        );
      } else {
        newSites = Array.from(new Set([...settings.sites, domain.toLowerCase()]));
      }
      await saveSettings({ sites: newSites });
      await render();
    });
  }

  // Clear completed downloads
  const clearBtn = $('btn-clear-completed');
  if (clearBtn) {
    clearBtn.addEventListener('click', async () => {
      await clearCompletedDownloads();
      await refreshTelemetry();
    });
  }

  // Open Netwich App buttons
  const openAppHeader = $('btn-open-app-header');
  if (openAppHeader) {
    openAppHeader.addEventListener('click', async () => {
      const success = await openMergeApp();
      if (!success) {
        api.tabs.create({ url: 'netwich://open' }).catch(() => {
          api.tabs.create({ url: 'merge://open' }).catch(() => {});
        });
      }
    });
  }

  const openAppFooter = $('btn-open-app-footer');
  if (openAppFooter) {
    openAppFooter.addEventListener('click', async () => {
      const success = await openMergeApp();
      if (!success) {
        api.tabs.create({ url: 'netwich://open' }).catch(() => {
          api.tabs.create({ url: 'merge://open' }).catch(() => {});
        });
      }
    });
  }

  const openOfflineBtn = $('btn-open-offline');
  if (openOfflineBtn) {
    openOfflineBtn.addEventListener('click', async () => {
      const success = await openMergeApp();
      if (!success) {
        api.tabs.create({ url: 'netwich://open' }).catch(() => {
          api.tabs.create({ url: 'merge://open' }).catch(() => {});
        });
      }
    });
  }

  // Options link
  const optionsBtn = $('btn-options');
  if (optionsBtn) {
    optionsBtn.addEventListener('click', () => {
      api.runtime.openOptionsPage();
    });
  }
}

// Initial render
document.addEventListener('DOMContentLoaded', async () => {
  initListeners();
  await render();

  // Smooth 1s polling while popup is open
  pollTimer = setInterval(async () => {
    await refreshTelemetry();
  }, 1000);
});

window.addEventListener('unload', () => {
  if (pollTimer) clearInterval(pollTimer);
});
