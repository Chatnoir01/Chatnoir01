import test from 'node:test';
import assert from 'node:assert/strict';
import { MemoryStore } from '../src/repository/memory-store.js';

test('clients are isolated by organization', () => {
  const store = new MemoryStore();
  const a = store.createClient('org-a', { name: 'Client A' });
  store.createClient('org-b', { name: 'Client B' });
  assert.deepEqual(store.listClients('org-a').map(c => c.name), ['Client A']);
  assert.equal(store.getClient('org-b', a.id), null);
});

test('client identity and tenant cannot be overwritten by patch', () => {
  const store = new MemoryStore();
  const client = store.createClient('org-a', { name: 'Initial' });
  const updated = store.updateClient('org-a', client.id, {
    name: 'Updated', id: 'attacker-id', organizationId: 'org-b'
  });
  assert.equal(updated.id, client.id);
  assert.equal(updated.organizationId, 'org-a');
  assert.equal(updated.name, 'Updated');
});

test('cannot delete client referenced by invoice', () => {
  const store = new MemoryStore();
  const client = store.createClient('org-a', { name: 'Client' });
  store.createInvoice('org-a', {
    clientId: client.id,
    number: 'FAC-2026-0001',
    lines: [],
    totals: { gross: 100 }
  });
  assert.deepEqual(store.deleteClient('org-a', client.id), {
    deleted: false,
    reason: 'client_has_invoices'
  });
});

test('invoice lookup is tenant-scoped', () => {
  const store = new MemoryStore();
  const invoice = store.createInvoice('org-a', {
    clientId: 'client-a', number: 'FAC-2026-0001', lines: [], totals: { gross: 50 }
  });
  assert.equal(store.getInvoice('org-b', invoice.id), null);
  assert.equal(store.getInvoice('org-a', invoice.id).number, 'FAC-2026-0001');
});

test('invoice status update is tenant-scoped', () => {
  const store = new MemoryStore();
  const invoice = store.createInvoice('org-a', {
    clientId: 'client-a', number: 'FAC-2026-0001', lines: [], totals: { gross: 50 }
  });
  assert.equal(store.updateInvoiceStatus('org-b', invoice.id, 'paid'), null);
  assert.equal(store.updateInvoiceStatus('org-a', invoice.id, 'paid').status, 'paid');
});
