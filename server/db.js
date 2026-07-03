import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
export const dataDir = path.join(root, 'data');
export const photosDir = path.join(dataDir, 'photos');
mkdirSync(photosDir, { recursive: true });

const db = new DatabaseSync(path.join(dataDir, 'curbcut.db'));

db.exec(`
CREATE TABLE IF NOT EXISTS reports (
  id            TEXT PRIMARY KEY,
  kind          TEXT NOT NULL,
  category      TEXT NOT NULL,
  description   TEXT NOT NULL DEFAULT '',
  reporter      TEXT NOT NULL DEFAULT '',
  lat           REAL NOT NULL,
  lng           REAL NOT NULL,
  address       TEXT NOT NULL DEFAULT '',
  country       TEXT NOT NULL DEFAULT '',
  photo         TEXT NOT NULL DEFAULT '',
  status        TEXT NOT NULL DEFAULT 'reported',
  severity      INTEGER,
  confidence    REAL,
  affected      TEXT NOT NULL DEFAULT '[]',
  hazards       TEXT NOT NULL DEFAULT '',
  fixes         TEXT NOT NULL DEFAULT '[]',
  summary       TEXT NOT NULL DEFAULT '',
  letter        TEXT NOT NULL DEFAULT '',
  ai_mock       INTEGER NOT NULL DEFAULT 0,
  confirmations INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
`);

function toReport(row) {
  if (!row) return null;
  return {
    ...row,
    severity: row.severity ?? null,
    confidence: row.confidence ?? null,
    affected: JSON.parse(row.affected || '[]'),
    fixes: JSON.parse(row.fixes || '[]'),
    ai_mock: Boolean(row.ai_mock),
  };
}

const insertStmt = db.prepare(`
  INSERT INTO reports (
    id, kind, category, description, reporter, lat, lng, address, country, photo,
    status, severity, confidence, affected, hazards, fixes, summary, letter,
    ai_mock, confirmations, created_at, updated_at
  ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
`);

export function insertReport(r) {
  insertStmt.run(
    r.id, r.kind, r.category, r.description, r.reporter, r.lat, r.lng,
    r.address, r.country, r.photo, r.status, r.severity ?? null,
    r.confidence ?? null, JSON.stringify(r.affected || []), r.hazards || '',
    JSON.stringify(r.fixes || []), r.summary || '', r.letter || '',
    r.ai_mock ? 1 : 0, r.confirmations || 0, r.created_at, r.updated_at,
  );
  return getReport(r.id);
}

export function getReport(id) {
  return toReport(db.prepare('SELECT * FROM reports WHERE id = ?').get(id));
}

export function listReports() {
  return db.prepare('SELECT * FROM reports ORDER BY created_at DESC').all().map(toReport);
}

export function setStatus(id, status) {
  db.prepare('UPDATE reports SET status = ?, updated_at = ? WHERE id = ?')
    .run(status, new Date().toISOString(), id);
  return getReport(id);
}

export function addConfirmation(id) {
  db.prepare('UPDATE reports SET confirmations = confirmations + 1, updated_at = ? WHERE id = ?')
    .run(new Date().toISOString(), id);
  return getReport(id);
}

export function countReports() {
  return db.prepare('SELECT COUNT(*) AS n FROM reports').get().n;
}

export function clearReports() {
  db.prepare('DELETE FROM reports').run();
}

function haversineMeters(aLat, aLng, bLat, bLng) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

// Same kind + category, still open, within `radiusM` metres → treated as the
// same real-world report (deduplication → confirmation instead of a new pin).
export function findDuplicate(lat, lng, kind, category, radiusM = 30) {
  const candidates = db
    .prepare(
      "SELECT * FROM reports WHERE kind = ? AND category = ? AND status NOT IN ('fixed','rejected')",
    )
    .all(kind, category);
  for (const row of candidates) {
    if (haversineMeters(lat, lng, row.lat, row.lng) <= radiusM) return toReport(row);
  }
  return null;
}

const OPEN_STATUSES = new Set(['reported', 'verified', 'sent', 'acknowledged']);

export function statsData() {
  const all = listReports();
  const issues = all.filter((r) => r.kind === 'issue');
  const features = all.filter((r) => r.kind === 'feature');
  const openIssues = issues.filter((r) => OPEN_STATUSES.has(r.status));
  const fixed = issues.filter((r) => r.status === 'fixed');

  const now = Date.now();
  const openAges = openIssues
    .map((r) => (now - Date.parse(r.created_at)) / 86400000)
    .sort((a, b) => a - b);
  const medianDaysOpen = openAges.length
    ? Math.round(openAges[Math.floor(openAges.length / 2)])
    : 0;

  const byCategory = {};
  for (const r of openIssues) byCategory[r.category] = (byCategory[r.category] || 0) + 1;

  const acted = issues.filter((r) =>
    ['verified', 'sent', 'acknowledged', 'fixed'].includes(r.status),
  );
  const verificationRate = issues.length ? Math.round((acted.length / issues.length) * 100) : 0;

  const points = {};
  for (const r of all) {
    const name = (r.reporter || '').trim();
    if (!name) continue;
    let p = 0;
    if (r.kind === 'feature') p += 8;
    else if (r.status !== 'rejected') p += r.status === 'reported' ? 4 : 10;
    p += (r.confirmations || 0) * 2;
    points[name] = (points[name] || 0) + p;
  }
  const leaderboard = Object.entries(points)
    .map(([name, pts]) => ({ name, points: pts }))
    .sort((a, b) => b.points - a.points)
    .slice(0, 5);

  return {
    total: all.length,
    openIssues: openIssues.length,
    fixed: fixed.length,
    features: features.length,
    pending: issues.filter((r) => r.status === 'reported').length,
    confirmations: all.reduce((s, r) => s + (r.confirmations || 0), 0),
    medianDaysOpen,
    verificationRate,
    byCategory,
    leaderboard,
  };
}
