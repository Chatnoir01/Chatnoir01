import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresStore } from '../src/repository/postgres-store.js';

test('PostgresStore scopes client reads by organization id', async () => {
  const calls = [];
  const pool = {
    async query(sql, params) {
      calls.push({ sql, params });
      return {
        rows: [{
          id: '11111111-1111-4111-8111-111111111111',
          organization_id: '00000000-0000-4000-8000-000000000001',
          name: 'Client Test',
          email: 'client@example.test',
          vat_number: 'BE0123456789',
          address: 'Bruxelles',
          created_at: new Date('2026-08-11T00:00:00Z'),
          updated_at: new Date('2026-08-11T00:00:00Z')
        }]
      };
    }
  };
  const store = new PostgresStore(pool);
  const clients = await store.listClients('00000000-0000-4000-8000-000000000001');
  assert.equal(clients.length, 1);
  assert.equal(clients[0].organizationId, '00000000-0000-4000-8000-000000000001');
  assert.deepEqual(calls[0].params, ['00000000-0000-4000-8000-000000000001']);
  assert.match(calls[0].sql, /where organization_id=\$1/i);
});

test('PostgresStore rejects an invalid pool', () => {
  assert.throws(() => new PostgresStore({}), /pg-compatible pool/);
});
