import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 31987;
const base = `http://127.0.0.1:${port}`;
let child;

async function waitForServer() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try { const response = await fetch(`${base}/api/health`); if (response.ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('server did not become ready');
}

before(async () => {
  child = spawn(process.execPath, ['server.js'], { cwd: process.cwd(), env: { ...process.env, PORT: String(port), DATABASE_URL: '' }, stdio: ['ignore', 'pipe', 'pipe'] });
  await waitForServer();
});
after(() => child?.kill('SIGTERM'));

async function register(email, organizationName) {
  const response = await fetch(`${base}/api/auth/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: 'Test-password-123!', organizationName })
  });
  assert.equal(response.status, 201);
  return response.headers.get('set-cookie').split(';')[0];
}
function authHeaders(cookie) { return { cookie, 'content-type': 'application/json' }; }

test('health endpoint reports v0.4.0', async () => {
  const response = await fetch(`${base}/api/health`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.version, '0.4.0');
});

test('v1 endpoints require a valid authenticated session', async () => {
  const response = await fetch(`${base}/api/v1/clients`);
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: 'unauthorized' });
});

test('register creates a session and /me returns current organization', async () => {
  const cookie = await register('owner@example.test', 'Owner Studio');
  const response = await fetch(`${base}/api/auth/me`, { headers: { cookie } });
  assert.equal(response.status, 200);
  const data = (await response.json()).data;
  assert.equal(data.user.email, 'owner@example.test');
  assert.equal(data.organization.name, 'Owner Studio');
  assert.equal(data.role, 'owner');
});

test('login rejects wrong password and accepts correct password', async () => {
  await register('login@example.test', 'Login Studio');
  const bad = await fetch(`${base}/api/auth/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'login@example.test', password: 'wrong-password' })
  });
  assert.equal(bad.status, 401);
  const good = await fetch(`${base}/api/auth/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'login@example.test', password: 'Test-password-123!' })
  });
  assert.equal(good.status, 200);
  assert.match(good.headers.get('set-cookie'), /pilot_session=/);
});

test('clients and invoices are isolated by authenticated organization', async () => {
  const alpha = await register('alpha@example.test', 'Alpha');
  const beta = await register('beta@example.test', 'Beta');

  const created = await fetch(`${base}/api/v1/clients`, {
    method: 'POST', headers: authHeaders(alpha), body: JSON.stringify({ name: 'Alpha Client', email: 'hello@alpha.example' })
  });
  assert.equal(created.status, 201);
  const client = (await created.json()).data;

  const own = await fetch(`${base}/api/v1/clients`, { headers: { cookie: alpha } });
  assert.equal((await own.json()).data.length, 1);
  const other = await fetch(`${base}/api/v1/clients`, { headers: { cookie: beta } });
  assert.equal((await other.json()).data.length, 0);

  const invoiceResponse = await fetch(`${base}/api/v1/invoices`, {
    method: 'POST', headers: authHeaders(alpha),
    body: JSON.stringify({ clientId: client.id, client: client.name, lines: [{ description: 'Conseil', quantity: 2, unitPrice: 100, vat: 21, discount: 0 }] })
  });
  assert.equal(invoiceResponse.status, 201);
  const invoice = (await invoiceResponse.json()).data;
  assert.equal(invoice.totals.gross, 242);

  const crossTenant = await fetch(`${base}/api/v1/invoices`, {
    method: 'POST', headers: authHeaders(beta),
    body: JSON.stringify({ clientId: client.id, client: client.name, lines: [{ description: 'Bad', quantity: 1, unitPrice: 1, vat: 21 }] })
  });
  assert.equal(crossTenant.status, 400);
  assert.deepEqual(await crossTenant.json(), { error: 'invalid_client' });
});

test('logout invalidates the session', async () => {
  const cookie = await register('logout@example.test', 'Logout Studio');
  const logout = await fetch(`${base}/api/auth/logout`, { method: 'POST', headers: { cookie, 'content-type': 'application/json' }, body: '{}' });
  assert.equal(logout.status, 204);
  const me = await fetch(`${base}/api/auth/me`, { headers: { cookie } });
  assert.equal(me.status, 401);
});
