const DEVICE_KEY = 'carbonloop-web-device-id';
const TOKEN_KEY = 'carbonloop-web-token';
const PENDING_KEY = 'carbonloop-pending-actions';

export function readJson(key, fallback) {
  try {
    const value = localStorage.getItem(key);
    return value === null ? fallback : JSON.parse(value);
  } catch {
    return fallback;
  }
}

export function writeJson(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

export function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

export function saveToken(token) {
  localStorage.setItem(TOKEN_KEY, token);
}

export function saveDeviceId() {
  let deviceId = localStorage.getItem(DEVICE_KEY);
  if (!deviceId) {
    deviceId = window.crypto?.randomUUID?.() || `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    localStorage.setItem(DEVICE_KEY, deviceId);
  }
  return deviceId;
}

export function getPendingActions() {
  const pending = readJson(PENDING_KEY, []);
  return Array.isArray(pending) ? pending : [];
}

export function savePendingActions(actions) {
  writeJson(PENDING_KEY, actions);
}
