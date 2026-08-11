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
import { createStore } from './src/repository/store-factory.js';
import { hashPassword, validatePassword, verifyPassword } from './src/auth/passwords.js';
import {
  SESSION_COOKIE,
  SESSION_TTL_MS,
  clearSessionCookie,
  createSessionToken,
  hashSessionToken,
  parseCookies,
  sessionCookie
} from './src/auth/sessions.js';

const root = fileURLToPath(new URL('.', import.meta.url));
const port = Number(process.env.PORT || 3000);
const store = await createStore();
const secureCookies = process.env.NODE_ENV === 'production';

const mime = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.webmanifest': 'application/manifest+json; charset=utf-8'
};

function sendJson(res, status, payload, headers = {}) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', ...headers
  });
  res.end(status === 204 ? '' : JSON.stringify(payload));
}

async function readJson(req) {
  const contentType = String(req.headers['content-type'] || '');
  if (!contentType.toLowerCase().startsWith('application/json')) throw new Error('UNSUPPORTED_MEDIA_TYPE');
  const chunks = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length; if (size > 64_000) throw new Error('PAYLOAD_TOO_LARGE'); chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

function validEmail(value) { return typeof value === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254; }
function validOrganizationName(value) { return typeof value === 'string' && value.trim().length >= 2 && value.trim().length <= 120; }
function parseApiPath(url) { return new URL(url, 'http://localhost').pathname.split('/').filter(Boolean); }

function validateClient(input, partial = false) {
  const errors = [];
  if (!partial || input.name !== undefined) if (typeof input.name !== 'string' || input.name.trim().length < 2 || input.name.length > 200) errors.push('name');
  if (input.email !== undefined && input.email !== '') if (!validEmail(input.email)) errors.push('email');
  if (input.vatNumber !== undefined && typeof input.vatNumber !== 'string') errors.push('vatNumber');
  if (input.address !== undefined && typeof input.address !== 'string') errors.push('address');
  return errors;
}

function enforceSameOrigin(req) {
  if (!['POST', 'PATCH', 'PUT', 'DELETE'].includes(req.method)) return true;
  const origin = req.headers.origin;
  if (!origin) return true;
  try { return new URL(origin).host === req.headers.host; } catch { return false; }
}

async function authContext(req) {
  const token = parseCookies(req.headers.cookie || '')[SESSION_COOKIE];
  if (!token) return null;
  return store.getSession(hashSessionToken(token));
}

async function createLoginSession(res, userId, organizationId) {
  const token = createSessionToken();
  await store.createSession({
    tokenHash: hashSessionToken(token), userId, organizationId,
    expiresAt: new Date(Date.now() + SESSION_TTL_MS).toISOString()
  });
  return { 'set-cookie': sessionCookie(token, secureCookies) };
}

async function handleAuth(req, res) {
  if (req.method === 'POST' && req.url === '/api/auth/register') {
    const input = await readJson(req);
    const fields = [];
    if (!validEmail(input.email)) fields.push('email');
    if (!validatePassword(input.password)) fields.push('password');
    if (!validOrganizationName(input.organizationName)) fields.push('organizationName');
    if (fields.length) return sendJson(res, 400, { error: 'invalid_registration', fields });
    if (await store.findUserByEmail(input.email)) return sendJson(res, 409, { error: 'email_exists' });
    try {
      const user = await store.createUser({ email: input.email, passwordHash: await hashPassword(input.password) });
      const organization = await store.createOrganization({ name: input.organizationName });
      await store.addMembership(organization.id, user.id, 'owner');
      const headers = await createLoginSession(res, user.id, organization.id);
      return sendJson(res, 201, { data: { user: { id: user.id, email: user.email }, organization, role: 'owner' } }, headers);
    } catch (error) {
      if (error?.code === '23505' || error?.message === 'email_exists') return sendJson(res, 409, { error: 'email_exists' });
      throw error;
    }
  }

  if (req.method === 'POST' && req.url === '/api/auth/login') {
    const input = await readJson(req);
    if (!validEmail(input.email) || typeof input.password !== 'string') return sendJson(res, 401, { error: 'invalid_credentials' });
    const user = await store.findUserByEmail(input.email);
    if (!user || !(await verifyPassword(input.password, user.passwordHash))) return sendJson(res, 401, { error: 'invalid_credentials' });
    const memberships = await store.listMemberships(user.id);
    if (!memberships.length) return sendJson(res, 403, { error: 'no_organization' });
    const membership = memberships[0];
    const headers = await createLoginSession(res, user.id, membership.organizationId);
    return sendJson(res, 200, { data: { user: { id: user.id, email: user.email }, organization: membership.organization, role: membership.role } }, headers);
  }

  if (req.method === 'POST' && req.url === '/api/auth/logout') {
    const token = parseCookies(req.headers.cookie || '')[SESSION_COOKIE];
    if (token) await store.deleteSession(hashSessionToken(token));
    return sendJson(res, 204, {}, { 'set-cookie': clearSessionCookie(secureCookies) });
  }

  if (req.method === 'GET' && req.url === '/api/auth/me') {
    const session = await authContext(req);
    if (!session) return sendJson(res, 401, { error: 'unauthorized' });
    const memberships = await store.listMemberships(session.userId);
    const current = memberships.find(row => row.organizationId === session.organizationId);
    return sendJson(res, 200, { data: { user: session.user, organization: current?.organization || null, role: session.role } });
  }
  return false;
}

async function handleApi(req, res) {
  const parts = parseApiPath(req.url);
  if (!enforceSameOrigin(req)) return sendJson(res, 403, { error: 'invalid_origin' });

  if (req.method === 'GET' && req.url === '/api/health') {
    return sendJson(res, 200, { ok: true, service: 'pilot', version: '0.4.0', storage: process.env.DATABASE_URL ? 'postgresql' : 'memory' });
  }

  if (req.url.startsWith('/api/auth/')) {
    const result = await handleAuth(req, res); if (result !== false) return result;
  }

  if (req.method === 'POST' && req.url === '/api/invoices/preview') {
    const draft = await readJson(req); const errors = validateInvoiceDraft(draft);
    if (errors.length) return sendJson(res, 400, { error: 'invalid_invoice', fields: errors });
    return sendJson(res, 200, calculateInvoiceTotals(draft));
  }
  if (req.method === 'POST' && req.url === '/api/company/validate') {
    const company = await readJson(req); const errors = validateCompanyProfile(company);
    return sendJson(res, errors.length ? 400 : 200, errors.length ? { error: 'invalid_company', fields: errors } : { ok: true });
  }

  if (parts[0] !== 'api' || parts[1] !== 'v1') return false;
  const session = await authContext(req);
  if (!session) return sendJson(res, 401, { error: 'unauthorized' });
  const organizationId = session.organizationId;
  const resource = parts[2]; const id = parts[3];

  if (resource === 'clients') {
    if (req.method === 'GET' && !id) return sendJson(res, 200, { data: await store.listClients(organizationId) });
    if (req.method === 'GET' && id) {
      const client = await store.getClient(organizationId, id); return client ? sendJson(res, 200, { data: client }) : sendJson(res, 404, { error: 'not_found' });
    }
    if (req.method === 'POST' && !id) {
      const input = await readJson(req); const errors = validateClient(input);
      if (errors.length) return sendJson(res, 400, { error: 'invalid_client', fields: errors });
      return sendJson(res, 201, { data: await store.createClient(organizationId, input) });
    }
    if (req.method === 'PATCH' && id) {
      const input = await readJson(req); const errors = validateClient(input, true);
      if (errors.length) return sendJson(res, 400, { error: 'invalid_client', fields: errors });
      const client = await store.updateClient(organizationId, id, input); return client ? sendJson(res, 200, { data: client }) : sendJson(res, 404, { error: 'not_found' });
    }
    if (req.method === 'DELETE' && id) {
      const result = await store.deleteClient(organizationId, id);
      if (result.reason === 'client_has_invoices') return sendJson(res, 409, { error: result.reason });
      return result.deleted ? sendJson(res, 204, {}) : sendJson(res, 404, { error: 'not_found' });
    }
  }

  if (resource === 'invoices') {
    if (req.method === 'GET' && !id) return sendJson(res, 200, { data: await store.listInvoices(organizationId) });
    if (req.method === 'GET' && id) {
      const invoice = await store.getInvoice(organizationId, id); return invoice ? sendJson(res, 200, { data: invoice }) : sendJson(res, 404, { error: 'not_found' });
    }
    if (req.method === 'POST' && !id) {
      const input = await readJson(req);
      if (typeof input.clientId !== 'string' || !(await store.getClient(organizationId, input.clientId))) return sendJson(res, 400, { error: 'invalid_client' });
      const draft = { client: input.client || 'Client', lines: input.lines }; const errors = validateInvoiceDraft(draft);
      if (errors.length) return sendJson(res, 400, { error: 'invalid_invoice', fields: errors });
      const totals = calculateInvoiceTotals(draft); const numbers = (await store.listInvoices(organizationId)).map(row => row.number);
      const invoice = await store.createInvoice(organizationId, { clientId: input.clientId, number: nextInvoiceNumber(numbers), status: 'draft', issueDate: input.issueDate, dueDate: input.dueDate, lines: input.lines, totals });
      return sendJson(res, 201, { data: invoice });
    }
    if (req.method === 'PATCH' && id && parts[4] === 'status') {
      const input = await readJson(req); const allowed = new Set(['draft', 'issued', 'paid', 'overdue', 'cancelled']);
      if (!allowed.has(input.status)) return sendJson(res, 400, { error: 'invalid_status' });
      const invoice = await store.updateInvoiceStatus(organizationId, id, input.status); return invoice ? sendJson(res, 200, { data: invoice }) : sendJson(res, 404, { error: 'not_found' });
    }
  }
  return sendJson(res, 405, { error: 'method_not_allowed' });
}

async function serveStatic(req, res) {
  const requested = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const safe = normalize(requested).replace(/^(\.\.(\/|\\|$))+/, ''); const target = join(root, safe);
  if (!target.startsWith(root)) return sendJson(res, 403, { error: 'forbidden' });
  try {
    const body = await readFile(target);
    res.writeHead(200, {
      'content-type': mime[extname(target)] || 'application/octet-stream', 'x-content-type-options': 'nosniff',
      'referrer-policy': 'same-origin', 'x-frame-options': 'DENY',
      'content-security-policy': "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
    });
    res.end(body);
  } catch { sendJson(res, 404, { error: 'not_found' }); }
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.url.startsWith('/api/')) { const handled = await handleApi(req, res); if (handled !== false) return handled; }
    if (!['GET', 'HEAD'].includes(req.method)) return sendJson(res, 405, { error: 'method_not_allowed' });
    return serveStatic(req, res);
  } catch (error) {
    if (error.message === 'PAYLOAD_TOO_LARGE') return sendJson(res, 413, { error: 'payload_too_large' });
    if (error.message === 'UNSUPPORTED_MEDIA_TYPE') return sendJson(res, 415, { error: 'unsupported_media_type' });
    if (error instanceof SyntaxError) return sendJson(res, 400, { error: 'invalid_json' });
    console.error(error); return sendJson(res, 500, { error: 'internal_error' });
  }
});

server.listen(port, () => console.log(`Pilot running on http://localhost:${port}`));
