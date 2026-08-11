import { MemoryStore } from './memory-store.js';
import { PostgresStore } from './postgres-store.js';

export async function createStore(env = process.env) {
  if (!env.DATABASE_URL) return new MemoryStore();

  let pg;
  try {
    pg = await import('pg');
  } catch {
    throw new Error('PostgreSQL requested but package "pg" is not installed. Run npm install.');
  }

  const pool = new pg.Pool({
    connectionString: env.DATABASE_URL,
    ssl: env.PGSSL === 'disable' ? false : env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    max: Number(env.PGPOOL_MAX || 10),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000
  });

  await pool.query('select 1');
  return new PostgresStore(pool);
}
