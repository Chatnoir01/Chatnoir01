import test from 'node:test';
import assert from 'node:assert/strict';
import { hashPassword, validatePassword, verifyPassword } from '../src/auth/passwords.js';
import { createSessionToken, hashSessionToken, parseCookies, sessionCookie } from '../src/auth/sessions.js';

test('password policy rejects weak passwords', () => {
  assert.equal(validatePassword('short'), false);
  assert.equal(validatePassword('Long-enough-password!'), true);
});

test('password hash is salted and verifies only the correct password', async () => {
  const first = await hashPassword('Long-enough-password!');
  const second = await hashPassword('Long-enough-password!');
  assert.notEqual(first, second);
  assert.equal(await verifyPassword('Long-enough-password!', first), true);
  assert.equal(await verifyPassword('Wrong-password-123!', first), false);
});

test('session tokens are high entropy and stored as hashes', () => {
  const token = createSessionToken();
  assert.ok(token.length >= 40);
  const hash = hashSessionToken(token);
  assert.match(hash, /^[a-f0-9]{64}$/);
  assert.notEqual(hash, token);
});

test('session cookie is HttpOnly and SameSite protected', () => {
  const cookie = sessionCookie('abc', true);
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /SameSite=Lax/);
  assert.match(cookie, /Secure/);
  assert.equal(parseCookies('a=1; pilot_session=abc').pilot_session, 'abc');
});
