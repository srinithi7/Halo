// Mediating API for optional recognition photos.
//
// Why this exists at all: the Flutter app can't talk to Neon directly —
// that would mean shipping the database connection string (a full-access
// credential) inside the app binary, decompilable by anyone. This server
// holds that secret instead, and the app talks to it over HTTPS.
//
// Every request must carry a valid Firebase ID token (the same one the
// app already has from signing in) so this stays scoped to real HALO
// users, not an open endpoint anyone on the internet can write to.
require('dotenv').config();
const express = require('express');
const { Pool } = require('@neondatabase/serverless');
const admin = require('firebase-admin');

admin.initializeApp({ projectId: process.env.FIREBASE_PROJECT_ID });

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const app = express();
// 5 MB cap matches storage.rules' would-be limit for the Firebase Storage
// path this replaces — keeps a phone photo well within bounds without
// needing client-side compression as a hard requirement.
app.use(express.json({ limit: '6mb' }));

async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing Authorization header' });

  try {
    req.uid = (await admin.auth().verifyIdToken(token)).uid;
    next();
  } catch (err) {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Body: { contentType: 'image/jpeg', dataBase64: '...' }
app.post('/photos', requireAuth, async (req, res) => {
  const { contentType, dataBase64 } = req.body || {};
  if (!contentType || !contentType.startsWith('image/')) {
    return res.status(400).json({ error: 'contentType must be an image/* type' });
  }
  if (!dataBase64) {
    return res.status(400).json({ error: 'dataBase64 is required' });
  }

  const buffer = Buffer.from(dataBase64, 'base64');
  if (buffer.length > 5 * 1024 * 1024) {
    return res.status(413).json({ error: 'Photo exceeds 5MB limit' });
  }

  const result = await pool.query(
    'INSERT INTO recognition_photos (uid, content_type, data) VALUES ($1, $2, $3) RETURNING id',
    [req.uid, contentType, buffer],
  );
  res.json({ id: result.rows[0].id });
});

// Publicly readable by id (no auth) — matches storage.rules' original
// intent (any signed-in HALO user could read a photo URL handed to them
// by a Firestore read that already enforced recognition visibility).
// Anyone with the id can fetch it, same as a Firebase Storage download
// URL would allow.
app.get('/photos/:id', async (req, res) => {
  const result = await pool.query(
    'SELECT content_type, data FROM recognition_photos WHERE id = $1',
    [req.params.id],
  );
  if (result.rows.length === 0) return res.status(404).send('Not found');

  const { content_type: contentType, data } = result.rows[0];
  res.set('Content-Type', contentType);
  res.set('Cache-Control', 'public, max-age=31536000, immutable');
  res.send(data);
});

app.get('/health', (_req, res) => res.json({ ok: true }));

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`halo-photo-api listening on :${port}`));
