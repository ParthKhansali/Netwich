// Universal WebExtension API wrapper for Chrome, Firefox, Safari, Edge, Brave
export interface WebExtensionAPI {
  tabs: typeof chrome.tabs;
  downloads: typeof chrome.downloads;
  contextMenus: typeof chrome.contextMenus;
  cookies: typeof chrome.cookies;
  storage: typeof chrome.storage;
  action: typeof chrome.action;
  alarms: typeof chrome.alarms;
  permissions: typeof chrome.permissions;
  runtime: typeof chrome.runtime;
  notifications: typeof chrome.notifications;
}

export const api: WebExtensionAPI = (globalThis as any).browser ?? chrome;

