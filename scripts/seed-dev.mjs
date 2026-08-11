import { readFile } from 'node:fs/promises';
import pg from 'pg';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}

const sql = await readFile(new URL('../db/dev-seed.sql', import.meta.url), 'utf8');
const pool = new pg.Pool({
  connectionString: url,
  ssl: process.env.PGSSL === 'disable' ? false : process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

try {
  await pool.query(sql);
  console.log('Pilot development seed completed');
} finally {
  await pool.end();
}
