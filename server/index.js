import express from 'express';
import { randomUUID } from 'node:crypto';
import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import {
  root, photosDir, insertReport, getReport, listReports, setStatus,
  addConfirmation, findDuplicate, statsData,
} from './db.js';
import { ISSUE_CATEGORIES, FEATURE_CATEGORIES, STATUSES, categoryLabel } from './categories.js';
import { reverseGeocode } from './geocode.js';
import { verifyReport, aiForcedMock } from './ai.js';

// Minimal .env loader (no dependency; --env-file-if-missing isn't in all Node versions)
const envFile = path.join(root, '.env');
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}

const PORT = Number(process.env.PORT) || 4141;
const app = express();

app.use(express.json({ limit: '20mb' }));
app.use('/vendor/leaflet', express.static(path.join(root, 'node_modules', 'leaflet', 'dist')));
app.use('/photos', express.static(photosDir));
app.use(express.static(path.join(root, 'web')));

const wrap = (fn) => (req, res) => {
  Promise.resolve(fn(req, res)).catch((err) => {
    console.error(err);
    res.status(500).json({ error: 'Internal error' });
  });
};

app.get('/api/meta', (req, res) => {
  res.json({
    issueCategories: ISSUE_CATEGORIES,
    featureCategories: FEATURE_CATEGORIES,
    statuses: STATUSES,
    aiMode: aiForcedMock() ? 'demo' : 'auto',
  });
});

app.get('/api/reports', (req, res) => res.json({ reports: listReports() }));

app.get('/api/reports/:id', (req, res) => {
  const report = getReport(req.params.id);
  if (!report) return res.status(404).json({ error: 'Not found' });
  res.json({ report });
});

const DATA_URL_RE = /^data:image\/(jpeg|jpg|png|webp|gif);base64,([A-Za-z0-9+/=]+)$/;

app.post('/api/reports', wrap(async (req, res) => {
  const { photo, lat, lng, kind, category, description = '', reporter = '' } = req.body || {};

  if (kind !== 'issue' && kind !== 'feature') {
    return res.status(400).json({ error: 'kind must be "issue" or "feature"' });
  }
  const categories = kind === 'feature' ? FEATURE_CATEGORIES : ISSUE_CATEGORIES;
  if (!categories[category]) return res.status(400).json({ error: 'Unknown category' });

  const nLat = Number(lat);
  const nLng = Number(lng);
  if (!Number.isFinite(nLat) || !Number.isFinite(nLng) || Math.abs(nLat) > 90 || Math.abs(nLng) > 180) {
    return res.status(400).json({ error: 'Invalid coordinates' });
  }

  const m = typeof photo === 'string' ? photo.match(DATA_URL_RE) : null;
  if (!m) return res.status(400).json({ error: 'photo must be a base64 image data URL' });
  const ext = m[1] === 'jpeg' || m[1] === 'jpg' ? 'jpg' : m[1];
  const mediaType = `image/${m[1] === 'jpg' ? 'jpeg' : m[1]}`;
  const imageBase64 = m[2];
  if (imageBase64.length > 14_000_000) return res.status(400).json({ error: 'Photo too large' });

  // Nearby open report of the same kind+category → confirmation, not a new pin.
  const duplicate = findDuplicate(nLat, nLng, kind, category);
  if (duplicate) {
    const report = addConfirmation(duplicate.id);
    return res.json({ duplicate: true, report });
  }

  const id = randomUUID();
  writeFileSync(path.join(photosDir, `${id}.${ext}`), Buffer.from(imageBase64, 'base64'));

  const { address, country } = await reverseGeocode(nLat, nLng);
  const cLabel = categoryLabel(kind, category);
  const cleanDescription = String(description).slice(0, 2000);
  const cleanReporter = String(reporter).slice(0, 60);

  const ai = await verifyReport({
    id, kind, category, categoryLabel: cLabel,
    description: cleanDescription, reporter: cleanReporter,
    lat: nLat, lng: nLng, address, country, imageBase64, mediaType,
  });

  const now = new Date().toISOString();
  const report = insertReport({
    id, kind, category,
    description: cleanDescription, reporter: cleanReporter,
    lat: nLat, lng: nLng, address, country,
    photo: `/photos/${id}.${ext}`,
    status: ai.verified ? 'verified' : 'reported',
    severity: ai.severity, confidence: ai.confidence,
    affected: ai.affected, hazards: ai.hazards, fixes: ai.fixes,
    summary: ai.summary, letter: ai.letter, ai_mock: ai.mock,
    confirmations: 0, created_at: now, updated_at: now,
  });

  res.json({ report });
}));

app.post('/api/reports/:id/confirm', (req, res) => {
  if (!getReport(req.params.id)) return res.status(404).json({ error: 'Not found' });
  res.json({ report: addConfirmation(req.params.id) });
});

app.post('/api/reports/:id/status', (req, res) => {
  const { status } = req.body || {};
  if (!STATUSES.includes(status)) return res.status(400).json({ error: 'Invalid status' });
  if (!getReport(req.params.id)) return res.status(404).json({ error: 'Not found' });
  res.json({ report: setStatus(req.params.id, status) });
});

app.get('/api/stats', (req, res) => res.json(statsData()));

app.listen(PORT, () => {
  const ai = aiForcedMock()
    ? 'demo mode (forced via CURBCUT_AI=mock)'
    : process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN
      ? `live (${process.env.ANTHROPIC_MODEL || 'claude-opus-4-8'})`
      : 'auto (falls back to demo mode if no Claude credentials)';
  console.log('CurbCut is running');
  console.log(`  Map      → http://localhost:${PORT}`);
  console.log(`  Council  → http://localhost:${PORT}/council.html`);
  console.log(`  AI       → ${ai}`);
});
