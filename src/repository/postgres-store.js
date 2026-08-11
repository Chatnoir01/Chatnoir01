function iso(value) {
  return value?.toISOString?.() || value || null;
}
function cents(value) {
  return Math.round(Number(value || 0) * 100);
}
function money(value) {
  return Number(value || 0) / 100;
}
function mapClient(row) {
  return {
    id: row.id,
    organizationId: row.organization_id,
    name: row.name,
    email: row.email || '',
    vatNumber: row.vat_number || '',
    address: row.address || '',
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at)
  };
}
function mapInvoiceHeader(row) {
  return {
    id: row.id,
    organizationId: row.organization_id,
    clientId: row.client_id,
    number: row.number,
    status: row.status,
    issueDate: iso(row.issue_date)?.slice?.(0, 10) || row.issue_date,
    dueDate: iso(row.due_date)?.slice?.(0, 10) || row.due_date,
    totals: {
      currency: row.currency || 'EUR',
      net: money(row.net_cents),
      vat: money(row.vat_cents),
      gross: money(row.gross_cents)
    },
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at)
  };
}
function mapLine(row) {
  return {
    description: row.description,
    quantity: Number(row.quantity),
    unitPrice: money(row.unit_price_cents),
    discount: Number(row.discount_percent),
    vat: Number(row.vat_rate)
  };
}
const invoiceSelect = `
  select id, organization_id, client_id, number, status, issue_date, due_date,
         currency, net_cents, vat_cents, gross_cents, created_at, updated_at
  from invoices`;

export class PostgresStore {
  constructor(pool) {
    if (!pool || typeof pool.query !== 'function') throw new TypeError('A pg-compatible pool is required');
    this.pool = pool;
  }

  async listClients(organizationId) {
    const { rows } = await this.pool.query(
      `select id, organization_id, name, email, vat_number, address, created_at, updated_at
       from clients where organization_id=$1 order by created_at desc`, [organizationId]);
    return rows.map(mapClient);
  }
  async getClient(organizationId, id) {
    const { rows } = await this.pool.query(
      `select id, organization_id, name, email, vat_number, address, created_at, updated_at
       from clients where organization_id=$1 and id=$2 limit 1`, [organizationId, id]);
    return rows[0] ? mapClient(rows[0]) : null;
  }
  async createClient(organizationId, input) {
    const { rows } = await this.pool.query(
      `insert into clients (organization_id,name,email,vat_number,address)
       values ($1,$2,$3,$4,$5)
       returning id, organization_id, name, email, vat_number, address, created_at, updated_at`,
      [organizationId, String(input.name || '').trim(), String(input.email || '').trim(), String(input.vatNumber || '').trim(), String(input.address || '').trim()]);
    return mapClient(rows[0]);
  }
  async updateClient(organizationId, id, patch) {
    const current = await this.getClient(organizationId, id);
    if (!current) return null;
    const { rows } = await this.pool.query(
      `update clients set name=$3,email=$4,vat_number=$5,address=$6,updated_at=now()
       where organization_id=$1 and id=$2
       returning id, organization_id, name, email, vat_number, address, created_at, updated_at`,
      [organizationId, id,
        patch.name !== undefined ? String(patch.name).trim() : current.name,
        patch.email !== undefined ? String(patch.email).trim() : current.email,
        patch.vatNumber !== undefined ? String(patch.vatNumber).trim() : current.vatNumber,
        patch.address !== undefined ? String(patch.address).trim() : current.address]);
    return rows[0] ? mapClient(rows[0]) : null;
  }
  async deleteClient(organizationId, id) {
    const linked = await this.pool.query('select 1 from invoices where organization_id=$1 and client_id=$2 limit 1', [organizationId, id]);
    if (linked.rowCount) return { deleted: false, reason: 'client_has_invoices' };
    const result = await this.pool.query('delete from clients where organization_id=$1 and id=$2', [organizationId, id]);
    return { deleted: result.rowCount > 0 };
  }

  async _withLines(headers) {
    if (!headers.length) return [];
    const ids = headers.map(row => row.id);
    const { rows } = await this.pool.query(
      `select invoice_id, position, description, quantity, unit_price_cents, discount_percent, vat_rate
       from invoice_lines where invoice_id = any($1::uuid[]) order by invoice_id, position`, [ids]);
    const grouped = new Map();
    for (const row of rows) {
      if (!grouped.has(row.invoice_id)) grouped.set(row.invoice_id, []);
      grouped.get(row.invoice_id).push(mapLine(row));
    }
    return headers.map(row => ({ ...mapInvoiceHeader(row), lines: grouped.get(row.id) || [] }));
  }
  async listInvoices(organizationId) {
    const { rows } = await this.pool.query(`${invoiceSelect} where organization_id=$1 order by created_at desc`, [organizationId]);
    return this._withLines(rows);
  }
  async getInvoice(organizationId, id) {
    const { rows } = await this.pool.query(`${invoiceSelect} where organization_id=$1 and id=$2 limit 1`, [organizationId, id]);
    const result = await this._withLines(rows);
    return result[0] || null;
  }
  async createInvoice(organizationId, input) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const totals = input.totals || {};
      const { rows } = await client.query(
        `insert into invoices
         (organization_id,client_id,number,status,issue_date,due_date,currency,net_cents,vat_cents,gross_cents)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         returning id, organization_id, client_id, number, status, issue_date, due_date,
                   currency, net_cents, vat_cents, gross_cents, created_at, updated_at`,
        [organizationId, input.clientId, input.number, input.status || 'draft', input.issueDate || new Date().toISOString().slice(0,10), input.dueDate || null, totals.currency || 'EUR', cents(totals.net), cents(totals.vat ?? totals.vatAmount), cents(totals.gross)]);
      const invoice = rows[0];
      for (const [index, line] of (input.lines || []).entries()) {
        await client.query(
          `insert into invoice_lines
           (invoice_id,position,description,quantity,unit_price_cents,discount_percent,vat_rate)
           values ($1,$2,$3,$4,$5,$6,$7)`,
          [invoice.id, index + 1, line.description, Number(line.quantity), cents(line.unitPrice), Number(line.discount || 0), Number(line.vat)]);
      }
      await client.query('commit');
      return { ...mapInvoiceHeader(invoice), lines: structuredClone(input.lines || []) };
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }
  async updateInvoiceStatus(organizationId, id, status) {
    const { rows } = await this.pool.query(
      `update invoices set status=$3,updated_at=now()
       where organization_id=$1 and id=$2
       returning id, organization_id, client_id, number, status, issue_date, due_date,
                 currency, net_cents, vat_cents, gross_cents, created_at, updated_at`,
      [organizationId, id, status]);
    if (!rows[0]) return null;
    const result = await this._withLines(rows);
    return result[0] || null;
  }
}
