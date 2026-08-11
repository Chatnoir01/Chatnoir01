import { randomUUID } from 'node:crypto';

function clone(value) {
  return structuredClone(value);
}

export class MemoryStore {
  constructor(seed = {}) {
    this.clients = clone(seed.clients || []);
    this.invoices = clone(seed.invoices || []);
    this.organizations = clone(seed.organizations || []);
  }

  listClients(organizationId) {
    return clone(this.clients.filter(item => item.organizationId === organizationId));
  }

  getClient(organizationId, id) {
    const item = this.clients.find(row => row.organizationId === organizationId && row.id === id);
    return item ? clone(item) : null;
  }

  createClient(organizationId, input) {
    const now = new Date().toISOString();
    const client = {
      id: randomUUID(),
      organizationId,
      name: String(input.name || '').trim(),
      email: String(input.email || '').trim(),
      vatNumber: String(input.vatNumber || '').trim(),
      address: String(input.address || '').trim(),
      createdAt: now,
      updatedAt: now
    };
    this.clients.push(client);
    return clone(client);
  }

  updateClient(organizationId, id, patch) {
    const index = this.clients.findIndex(row => row.organizationId === organizationId && row.id === id);
    if (index === -1) return null;
    const current = this.clients[index];
    const next = {
      ...current,
      ...(patch.name !== undefined ? { name: String(patch.name).trim() } : {}),
      ...(patch.email !== undefined ? { email: String(patch.email).trim() } : {}),
      ...(patch.vatNumber !== undefined ? { vatNumber: String(patch.vatNumber).trim() } : {}),
      ...(patch.address !== undefined ? { address: String(patch.address).trim() } : {}),
      id: current.id,
      organizationId: current.organizationId,
      updatedAt: new Date().toISOString()
    };
    this.clients[index] = next;
    return clone(next);
  }

  deleteClient(organizationId, id) {
    if (this.invoices.some(row => row.organizationId === organizationId && row.clientId === id)) {
      return { deleted: false, reason: 'client_has_invoices' };
    }
    const before = this.clients.length;
    this.clients = this.clients.filter(row => !(row.organizationId === organizationId && row.id === id));
    return { deleted: this.clients.length !== before };
  }

  listInvoices(organizationId) {
    return clone(this.invoices.filter(item => item.organizationId === organizationId));
  }

  getInvoice(organizationId, id) {
    const item = this.invoices.find(row => row.organizationId === organizationId && row.id === id);
    return item ? clone(item) : null;
  }

  createInvoice(organizationId, input) {
    const now = new Date().toISOString();
    const invoice = {
      id: randomUUID(),
      organizationId,
      clientId: input.clientId,
      number: input.number,
      status: input.status || 'draft',
      issueDate: input.issueDate || now.slice(0, 10),
      dueDate: input.dueDate || null,
      lines: clone(input.lines || []),
      totals: clone(input.totals || null),
      createdAt: now,
      updatedAt: now
    };
    this.invoices.push(invoice);
    return clone(invoice);
  }

  updateInvoiceStatus(organizationId, id, status) {
    const index = this.invoices.findIndex(row => row.organizationId === organizationId && row.id === id);
    if (index === -1) return null;
    this.invoices[index] = {
      ...this.invoices[index],
      status,
      updatedAt: new Date().toISOString()
    };
    return clone(this.invoices[index]);
  }
}
