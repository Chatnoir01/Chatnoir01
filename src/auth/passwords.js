import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb);
const KEYLEN = 64;

export function validatePassword(password) {
  return typeof password === 'string' && password.length >= 12 && password.length <= 200;
}

export async function hashPassword(password) {
  if (!validatePassword(password)) throw new TypeError('invalid_password');
  const salt = randomBytes(16);
  const derived = await scrypt(password, salt, KEYLEN, { N: 16384, r: 8, p: 1 });
  return `scrypt$16384$8$1$${salt.toString('base64')}$${Buffer.from(derived).toString('base64')}`;
}

export async function verifyPassword(password, encoded) {
  try {
    const [algorithm, n, r, p, saltB64, hashB64] = String(encoded).split('$');
    if (algorithm !== 'scrypt') return false;
    const expected = Buffer.from(hashB64, 'base64');
    if (expected.length !== KEYLEN) return false;
    const derived = await scrypt(password, Buffer.from(saltB64, 'base64'), KEYLEN, {
      N: Number(n), r: Number(r), p: Number(p)
    });
    return timingSafeEqual(Buffer.from(derived), expected);
  } catch {
    return false;
  }
}
