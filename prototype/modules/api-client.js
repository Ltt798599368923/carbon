import { getToken } from './local-store.js';

const API_BASE = (window.CARBON_API_URL || 'http://127.0.0.1:8787').replace(/\/$/, '');

export async function request(path, options = {}) {
  const headers = {
    Accept: 'application/json',
    ...(options.body ? { 'Content-Type': 'application/json' } : {}),
  };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  let response;
  try {
    response = await fetch(`${API_BASE}${path}`, { ...options, headers });
  } catch {
    throw new Error('网络不可用');
  }
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.ok === false) {
    throw new Error(payload.error?.message || `请求失败 (${response.status})`);
  }
  return payload;
}

export function getApiBase() {
  return API_BASE;
}
