import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  calculateInvoiceTotals,
  nextInvoiceNumber,
  validateCompanyProfile,
  validateInvoiceDraft
} from './src/domain/invoice.js';
import { MemoryStore } from './src/repository/memory-store.js';

const root = fileURLToPath(new URL('.', import.meta.url));
const port = Number(process.env.PORT || 3000);
const store = new MemoryStore();

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8'
};

function sendJson(res, status, payload) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 64_000) throw new Error('PAYLOAD_TOO_LARGE');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

function getOrganizationId(req) {
  const value = req.headers['x-pilot-organization'];
  if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{3,64}$/.test(value)) return null;
  return value;
}

function validateClient(input, partial = false) {
  const errors = [];
  if (!partial || input.name !== undefined) {
    if (typeof input.name !== 'string' || input.name.trim().length < 2 || input.name.length > 200) errors.push('name');
  }
  if (input.email !== undefined && input.email !== '') {
    if (typeof input.email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)) errors.push('email');
  }
  if (input.vatNumber !== undefined && typeof input.vatNumber !== 'string') errors.push('vatNumber');
  if (input.address !== undefined && typeof input.address !== 'string') errors.push('address');
  return errors;
}

function parseApiPath(url) {
  const pathname = new URL(url, 'http://localhost').pathname;
  return pathname.split('/').filter(Boolean);
}

async function handleApi(req, res) {
  const parts = parseApiPath(req.url);

  if (req.method === 'GET' && req.url === '/api/health') {
    return sendJson(res, 200, { ok: true, service: 'pilot', version: '0.2.0' });
  }

  if (req.method === 'POST' && req.url === '/api/invoices/preview') {
    const draft = await readJson(req);
    const errors = validateInvoiceDraft(draft);
    if (errors.length) return sendJson(res, 400, { error: 'invalid_invoice', fields: errors });
    return sendJson(res, 200, calculateInvoiceTotals(draft));
  }

  if (req.method === 'POST' && req.url === '/api/company/validate') {
    const company = await readJson(req);
    const errors = validateCompanyProfile(company);
    return sendJson(res, errors.length ? 400 : 200, errors.length
      ? { error: 'invalid_company', fields: errors }
      : { ok: true });
  }

  if (parts[0] !== 'api' || parts[1] !== 'v1') return false;

  // Temporary pre-auth boundary for the MVP. This header is NOT authentication.
  // A real authenticated organization context must replace it before production.
  const organizationId = getOrganizationId(req);
  if (!organizationId) return sendJson(res, 400, { error: 'organization_required' });

  const resource = parts[2];
  const id = parts[3];

  if (resource === 'clients') {
    if (req.method === 'GET' && !id) return sendJson(res, 200, { data: store.listClients(organizationId) });
    if (req.method === 'GET' && id) {
      const client = store.getClient(organizationId, id);
      return client ? sendJson(res, 200, { data: client }) : sendJson(res, 404, { error: 'not_found' });
    }
    if (req.method === 'POST' && !id) {
      const input = await readJson(req);
      const errors = validateClient(input);
      if (errors.length) return sendJson(res, 400, { error: 'invalid_client', fields: errors });
      return sendJson(res, 201, { data: store.createClient(organizationId, input) });
    }
    if (req.method === 'PATCH' && id) {
      const input = await readJson(req);
      const errors = validateClient(input, true);
      if (errors.length) return sendJson(res, 400, { error: 'invalid_client', fields: errors });
      const client = store.updateClient(organizationId, id, input);
      return client ? sendJson(res, 200, { data: client }) : sendJson(res, 404, { error: 'not_found' });
    }
    if (req.method === 'DELETE' && id) {
      const result = store.deleteClient(organizationId, id);
      if (result.reason === 'client_has_invoices') return sendJson(res, 409, { error: result.reason });
      return result.deleted ? sendJson(res, 204, {}) : sendJson(res, 404, { error: 'not_found' });
    }
  }

  if (resource === 'invoices') {
    if (req.method === 'GET' && !id) return sendJson(res, 200, { data: store.listInvoices(organizationId) });
    if (req.method === 'GET' && id) {
      const invoice = store.getInvoice(organizationId, id);
      return invoice ? sendJson(res, 200, { data: invoice }) : sendJson(res, 404, { error: 'not_found' });
    }
    if (req.method === 'POST' && !id) {
      const input = await readJson(req);
      if (typeof input.clientId !== 'string' || !store.getClient(organizationId, input.clientId)) {
        return sendJson(res, 400, { error: 'invalid_client' });
      }
      const draft = { client: input.client || 'Client', lines: input.lines };
      const errors = validateInvoiceDraft(draft);
      if (errors.length) return sendJson(res, 400, { error: 'invalid_invoice', fields: errors });
      const totals = calculateInvoiceTotals(draft);
      const numbers = store.listInvoices(organizationId).map(row => row.number);
      const invoice = store.createInvoice(organizationId, {
        clientId: input.clientId,
        number: nextInvoiceNumber(numbers),
        status: 'draft',
        issueDate: input.issueDate,
        dueDate: input.dueDate,
        lines: input.lines,
        totals
      });
      return sendJson(res, 201, { data: invoice });
    }
    if (req.method === 'PATCH' && id && parts[4] === 'status') {
      const input = await readJson(req);
      const allowed = new Set(['draft', 'issued', 'paid', 'overdue', 'cancelled']);
      if (!allowed.has(input.status)) return sendJson(res, 400, { error: 'invalid_status' });
      const invoice = store.updateInvoiceStatus(organizationId, id, input.status);
      return invoice ? sendJson(res, 200, { data: invoice }) : sendJson(res, 404, { error: 'not_found' });
    }
  }

  return sendJson(res, 405, { error: 'method_not_allowed' });
}

async function serveStatic(req, res) {
  const requested = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const safe = normalize(requested).replace(/^(\.\.(\/|\\|$))+/, '');
  const target = join(root, safe);
  if (!target.startsWith(root)) return sendJson(res, 403, { error: 'forbidden' });
  try {
    const body = await readFile(target);
    res.writeHead(200, {
      'content-type': mime[extname(target)] || 'application/octet-stream',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'content-security-policy': "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"
    });
    res.end(body);
  } catch {
    sendJson(res, 404, { error: 'not_found' });
  }
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.url.startsWith('/api/')) {
      const handled = await handleApi(req, res);
      if (handled !== false) return handled;
    }

    if (!['GET', 'HEAD'].includes(req.method)) {
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }

    return serveStatic(req, res);
  } catch (error) {
    if (error.message === 'PAYLOAD_TOO_LARGE') return sendJson(res, 413, { error: 'payload_too_large' });
    if (error instanceof SyntaxError) return sendJson(res, 400, { error: 'invalid_json' });
    console.error(error);
    return sendJson(res, 500, { error: 'internal_error' });
  }
});

server.listen(port, () => {
  console.log(`Pilot running on http://localhost:${port}`);
});
