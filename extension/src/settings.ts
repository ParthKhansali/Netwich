import { api } from './api';

export interface MergeExtensionSettings {
  capture: boolean;
  sites: string[];
  skipSmall: boolean;
  minMegabytes: number;
}

export const DEFAULTS: MergeExtensionSettings = {
  capture: true,
  sites: [],
  skipSmall: false,
  minMegabytes: 5
};

export async function loadSettings(): Promise<MergeExtensionSettings> {
  const stored = await api.storage.local.get(DEFAULTS);
  return { ...DEFAULTS, ...stored } as MergeExtensionSettings;
}

export function saveSettings(patch: Partial<MergeExtensionSettings>): Promise<void> {
  return api.storage.local.set(patch);
}

export function isSiteExcluded(sites: string[], urls: (string | undefined)[]): boolean {
  return urls.some((raw) => {
    if (!raw) return false;
    let host: string;
    try {
      host = new URL(raw).hostname.toLowerCase();
    } catch {
      return false;
    }
    return sites.some((site) => {
      const s = site.toLowerCase().trim();
      return host === s || host.endsWith('.' + s);
    });
  });
}

export function normalizeDomain(input: string): string | null {
  const text = input.trim().toLowerCase().replace(/^\*\./, '');
  try {
    const host = new URL(/^[a-z]+:\/\//.test(text) ? text : `https://${text}`).hostname;
    return host.includes('.') || host === 'localhost' ? host : null;
  } catch {
    return null;
  }
}

