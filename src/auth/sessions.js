import { createHash, randomBytes } from 'node:crypto';

export const SESSION_COOKIE = 'pilot_session';
export const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 30;

export function createSessionToken() {
  return randomBytes(32).toString('base64url');
}

export function hashSessionToken(token) {
  return createHash('sha256').update(String(token)).digest('hex');
}

export function parseCookies(header = '') {
  const out = {};
  for (const pair of String(header).split(';')) {
    const index = pair.indexOf('=');
    if (index < 1) continue;
    const key = pair.slice(0, index).trim();
    const value = pair.slice(index + 1).trim();
    if (key) out[key] = decodeURIComponent(value);
  }
  return out;
}

export function sessionCookie(token, secure = false) {
  return `${SESSION_COOKIE}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}${secure ? '; Secure' : ''}`;
}

export function clearSessionCookie(secure = false) {
  return `${SESSION_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure ? '; Secure' : ''}`;
}
