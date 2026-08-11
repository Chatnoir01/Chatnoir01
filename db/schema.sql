-- Pilot PostgreSQL schema
-- Production-oriented baseline with strict organization ownership.

create extension if not exists pgcrypto;

create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  vat_number text,
  address text,
  iban text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists memberships (
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  role text not null check (role in ('owner','admin','member','accountant')),
  primary key (organization_id, user_id)
);
create index if not exists memberships_user_idx on memberships(user_id);

create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash char(64) not null unique,
  user_id uuid not null references users(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists sessions_user_idx on sessions(user_id);
create index if not exists sessions_expires_idx on sessions(expires_at);

create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  email text,
  vat_number text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists clients_org_idx on clients(organization_id);

create table if not exists invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  client_id uuid not null references clients(id),
  number text not null,
  status text not null check (status in ('draft','issued','paid','overdue','cancelled')),
  issue_date date,
  due_date date,
  currency char(3) not null default 'EUR',
  net_cents bigint not null default 0,
  vat_cents bigint not null default 0,
  gross_cents bigint not null default 0,
  issued_snapshot jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, number)
);
create index if not exists invoices_org_idx on invoices(organization_id);
create index if not exists invoices_client_idx on invoices(client_id);

create table if not exists invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  position integer not null,
  description text not null,
  quantity numeric(18,4) not null check (quantity > 0),
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  discount_percent numeric(5,2) not null default 0 check (discount_percent between 0 and 100),
  vat_rate numeric(5,2) not null check (vat_rate in (0,6,12,21))
);
create unique index if not exists invoice_lines_position_idx on invoice_lines(invoice_id, position);

create table if not exists quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  client_id uuid not null references clients(id),
  number text not null,
  status text not null check (status in ('draft','sent','accepted','rejected','expired')),
  issue_date date,
  valid_until date,
  total_cents bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, number)
);

create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  invoice_id uuid not null references invoices(id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  paid_at timestamptz not null,
  method text,
  reference text,
  created_at timestamptz not null default now()
);

create table if not exists audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  actor_user_id uuid references users(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_org_created_idx on audit_events(organization_id, created_at desc);
