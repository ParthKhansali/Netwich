export const BRIDGE_PORTS = [19288, 19289, 19290];
export const BRIDGE_API = 1;
export const BRIDGE_TIMEOUT_MS = 6000;

export interface BridgeDownloadItem {
  id: string;
  filename: string;
  url: string;
  status: 'downloading' | 'probing' | 'queued' | 'paused' | 'completed' | 'failed' | string;
  statusTitle: string;
  isCompleted: boolean;
  progress: number;
  downloadedBytes: number;
  totalBytes: number;
  speedBytesPerSec: number;
  etaSeconds?: number;
  destinationPath?: string;
  addedDate?: number;
}

export interface AppStatus {
  app: string;
  version: string;
  connected: boolean;
  isAggregating: boolean;
  speedBytesPerSec: number;
  activeConnections: number;
  linkCount: number;
  downloads?: BridgeDownloadItem[];
}

export interface AddDownloadRequest {
  url: string;
  pageUrl?: string;
  fileName?: string;
  minBytes?: number;
  browser?: {
    cookies: any[];
    referer?: string;
    userAgent: string;
    name: string;
  };
}

let activePort: number | null = null;

export function getActivePort(): number | null {
  return activePort;
}

async function pingPort(port: number): Promise<'ok' | 'update' | 'closed'> {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/ping`, {
      signal: AbortSignal.timeout(1200)
    });
    if (!res.ok) return 'closed';
    const ping = await res.json();
    if (ping.app !== 'netwich' && ping.app !== 'merge' && ping.app !== 'plexo') return 'closed';
    return ping.api === BRIDGE_API ? 'ok' : 'update';
  } catch {
    return 'closed';
  }
}

export async function reach(): Promise<'ok' | 'update' | 'closed'> {
  const results = await Promise.all(BRIDGE_PORTS.map(pingPort));
  const okIndex = results.indexOf('ok');
  if (okIndex >= 0) {
    activePort = BRIDGE_PORTS[okIndex];
    return 'ok';
  }
  activePort = null;
  return results.includes('update') ? 'update' : 'closed';
}

export async function fetchLiveStatus(): Promise<AppStatus | null> {
  const reached = await reach();
  if (reached !== 'ok' || activePort === null) return null;
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

export async function openNetwichApp(): Promise<boolean> {
  if (activePort !== null) {
    try {
      const res = await fetch(`http://127.0.0.1:${activePort}/open`, {
        method: 'POST',
        signal: AbortSignal.timeout(2000)
      });
      if (res.ok) return true;
    } catch {
      // Fallback below
    }
  }
  return false;
}

export const openMergeApp = openNetwichApp;

export async function sendDownloadHandoff(
  request: AddDownloadRequest
): Promise<{ port: number; token: string } | 'closed' | 'kept'> {
  if ((await reach()) !== 'ok' || activePort === null) return 'closed';
  const port = activePort;
  try {
    const res = await fetch(`http://127.0.0.1:${port}/add`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
      signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS)
    });
    if (!res.ok) return 'kept';
    const body = await res.json();
    return { port, token: body.token };
  } catch (err: any) {
    if (err instanceof DOMException && err.name === 'TimeoutError') {
      return 'kept';
    }
    return 'closed';
  }
}

export async function confirmDownloadHandoff(handoff: { port: number; token: string }): Promise<boolean> {
  try {
    const res = await fetch(`http://127.0.0.1:${handoff.port}/confirm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: handoff.token }),
      signal: AbortSignal.timeout(3000)
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function sendDownloadAction(path: string, payload: any): Promise<boolean> {
  if (activePort === null) {
    const reached = await reach();
    if (reached !== 'ok' || activePort === null) return false;
  }
  try {
    const res = await fetch(`http://127.0.0.1:${activePort}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(3000)
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function openDownloadedFile(id: string): Promise<boolean> {
  return sendDownloadAction('/downloads/open', { id });
}

export async function revealDownloadedFile(id: string): Promise<boolean> {
  return sendDownloadAction('/downloads/reveal', { id });
}

export async function pauseDownload(id: string): Promise<boolean> {
  return sendDownloadAction('/downloads/pause', { id });
}

export async function resumeDownload(id: string): Promise<boolean> {
  return sendDownloadAction('/downloads/resume', { id });
}

export async function cancelDownload(id: string): Promise<boolean> {
  return sendDownloadAction('/downloads/cancel', { id });
}

export async function clearCompletedDownloads(): Promise<boolean> {
  return sendDownloadAction('/downloads/clear', {});
}

