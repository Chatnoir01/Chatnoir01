import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 31987;
const base = `http://127.0.0.1:${port}`;
let child;

async function waitForServer() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${base}/api/health`);
      if (response.ok) return;
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('server did not become ready');
}

before(async () => {
  child = spawn(process.execPath, ['server.js'], {
    cwd: process.cwd(),
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  await waitForServer();
});

after(() => {
  child?.kill('SIGTERM');
});

function headers(org = 'org-test') {
  return {
    'content-type': 'application/json',
    'x-pilot-organization': org
  };
}

test('health endpoint reports v0.2.0', async () => {
  const response = await fetch(`${base}/api/health`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.version, '0.2.0');
});

test('v1 endpoints require organization context', async () => {
  const response = await fetch(`${base}/api/v1/clients`);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: 'organization_required' });
});

test('creates and lists a client inside one organization only', async () => {
  const created = await fetch(`${base}/api/v1/clients`, {
    method: 'POST',
    headers: headers('org-alpha'),
    body: JSON.stringify({ name: 'Alpha SRL', email: 'hello@alpha.example' })
  });
  assert.equal(created.status, 201);
  const client = (await created.json()).data;
  assert.equal(client.name, 'Alpha SRL');

  const own = await fetch(`${base}/api/v1/clients`, { headers: headers('org-alpha') });
  assert.equal((await own.json()).data.length, 1);

  const other = await fetch(`${base}/api/v1/clients`, { headers: headers('org-beta') });
  assert.equal((await other.json()).data.length, 0);
});

test('creates an invoice only for a client in the same organization', async () => {
  const clientResponse = await fetch(`${base}/api/v1/clients`, {
    method: 'POST',
    headers: headers('org-invoice'),
    body: JSON.stringify({ name: 'Invoice Client' })
  });
  const client = (await clientResponse.json()).data;

  const response = await fetch(`${base}/api/v1/invoices`, {
    method: 'POST',
    headers: headers('org-invoice'),
    body: JSON.stringify({
      clientId: client.id,
      client: client.name,
      lines: [
        { description: 'Conseil', quantity: 2, unitPrice: 100, vat: 21, discountPercent: 0 }
      ]
    })
  });
  assert.equal(response.status, 201);
  const invoice = (await response.json()).data;
  assert.equal(invoice.number, `FAC-${new Date().getFullYear()}-0001`);
  assert.equal(invoice.totals.gross, 242);

  const crossTenant = await fetch(`${base}/api/v1/invoices`, {
    method: 'POST',
    headers: headers('org-other'),
    body: JSON.stringify({
      clientId: client.id,
      client: client.name,
      lines: [{ description: 'Bad', quantity: 1, unitPrice: 1, vat: 21 }]
    })
  });
  assert.equal(crossTenant.status, 400);
  assert.deepEqual(await crossTenant.json(), { error: 'invalid_client' });
});
