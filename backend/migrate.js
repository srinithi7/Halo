// One-time schema setup — run with `npm run migrate` after DATABASE_URL is
// set in .env. Safe to re-run (IF NOT EXISTS).
require('dotenv').config();
const { Pool } = require('@neondatabase/serverless');

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  await pool.query(`
    CREATE TABLE IF NOT EXISTS recognition_photos (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      uid TEXT NOT NULL,
      content_type TEXT NOT NULL,
      data BYTEA NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  console.log('recognition_photos table ready.');
  await pool.end();
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
