function mapClient(row) {
  return {
    id: row.id,
    organizationId: row.organization_id,
    name: row.name,
    email: row.email || '',
    vatNumber: row.vat_number || '',
    address: row.address || '',
    createdAt: row.created_at?.toISOString?.() || row.created_at,
    updatedAt: row.updated_at?.toISOString?.() || row.updated_at
  };
}

function mapInvoice(row) {
  return {
    id: row.id,
    organizationId: row.organization_id,
    clientId: row.client_id,
    number: row.number,
    status: row.status,
    issueDate: row.issue_date,
    dueDate: row.due_date,
    lines: row.lines || [],
    totals: row.totals || null,
    createdAt: row.created_at?.toISOString?.() || row.created_at,
    updatedAt: row.updated_at?.toISOString?.() || row.updated_at
  };
}

export class PostgresStore {
  constructor(pool) {
    if (!pool || typeof pool.query !== 'function') throw new TypeError('A pg-compatible pool is required');
    this.pool = pool;
  }

  async listClients(organizationId) {
    const { rows } = await this.pool.query(
      `select id, organization_id, name, email, vat_number, address, created_at, updated_at
       from clients where organization_id = $1 order by created_at desc`,
      [organizationId]
    );
    return rows.map(mapClient);
  }

  async getClient(organizationId, id) {
    const { rows } = await this.pool.query(
      `select id, organization_id, name, email, vat_number, address, created_at, updated_at
       from clients where organization_id = $1 and id = $2 limit 1`,
      [organizationId, id]
    );
    return rows[0] ? mapClient(rows[0]) : null;
  }

  async createClient(organizationId, input) {
    const { rows } = await this.pool.query(
      `insert into clients (organization_id, name, email, vat_number, address)
       values ($1,$2,$3,$4,$5)
       returning id, organization_id, name, email, vat_number, address, created_at, updated_at`,
      [organizationId, String(input.name || '').trim(), String(input.email || '').trim(), String(input.vatNumber || '').trim(), String(input.address || '').trim()]
    );
    return mapClient(rows[0]);
  }

  async updateClient(organizationId, id, patch) {
    const current = await this.getClient(organizationId, id);
    if (!current) return null;
    const next = {
      name: patch.name !== undefined ? String(patch.name).trim() : current.name,
      email: patch.email !== undefined ? String(patch.email).trim() : current.email,
      vatNumber: patch.vatNumber !== undefined ? String(patch.vatNumber).trim() : current.vatNumber,
      address: patch.address !== undefined ? String(patch.address).trim() : current.address
    };
    const { rows } = await this.pool.query(
      `update clients set name=$3, email=$4, vat_number=$5, address=$6, updated_at=now()
       where organization_id=$1 and id=$2
       returning id, organization_id, name, email, vat_number, address, created_at, updated_at`,
      [organizationId, id, next.name, next.email, next.vatNumber, next.address]
    );
    return rows[0] ? mapClient(rows[0]) : null;
  }

  async deleteClient(organizationId, id) {
    const linked = await this.pool.query(
      'select 1 from invoices where organization_id=$1 and client_id=$2 limit 1',
      [organizationId, id]
    );
    if (linked.rowCount) return { deleted: false, reason: 'client_has_invoices' };
    const result = await this.pool.query('delete from clients where organization_id=$1 and id=$2', [organizationId, id]);
    return { deleted: result.rowCount > 0 };
  }

  async listInvoices(organizationId) {
    const { rows } = await this.pool.query(
      `select id, organization_id, client_id, number, status, issue_date, due_date,
              lines, totals, created_at, updated_at
       from invoices where organization_id=$1 order by created_at desc`,
      [organizationId]
    );
    return rows.map(mapInvoice);
  }

  async getInvoice(organizationId, id) {
    const { rows } = await this.pool.query(
      `select id, organization_id, client_id, number, status, issue_date, due_date,
              lines, totals, created_at, updated_at
       from invoices where organization_id=$1 and id=$2 limit 1`,
      [organizationId, id]
    );
    return rows[0] ? mapInvoice(rows[0]) : null;
  }

  async createInvoice(organizationId, input) {
    const { rows } = await this.pool.query(
      `insert into invoices
       (organization_id, client_id, number, status, issue_date, due_date, lines, totals)
       values ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb)
       returning id, organization_id, client_id, number, status, issue_date, due_date,
                 lines, totals, created_at, updated_at`,
      [organizationId, input.clientId, input.number, input.status || 'draft', input.issueDate || new Date().toISOString().slice(0,10), input.dueDate || null, JSON.stringify(input.lines || []), JSON.stringify(input.totals || null)]
    );
    return mapInvoice(rows[0]);
  }

  async updateInvoiceStatus(organizationId, id, status) {
    const { rows } = await this.pool.query(
      `update invoices set status=$3, updated_at=now()
       where organization_id=$1 and id=$2
       returning id, organization_id, client_id, number, status, issue_date, due_date,
                 lines, totals, created_at, updated_at`,
      [organizationId, id, status]
    );
    return rows[0] ? mapInvoice(rows[0]) : null;
  }
}
