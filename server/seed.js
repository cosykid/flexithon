// Seeds the map with demo reports around London's Southbank so the app has
// something to show. Photos are generated SVG placeholders (never sent to the
// AI). Run: npm run seed   (add --force to wipe and re-seed)

import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { insertReport, countReports, clearReports, photosDir } from './db.js';
import { categoryLabel } from './categories.js';
import { templateLetter } from './letters.js';
import { standardsFor } from './geocode.js';

if (countReports() > 0) {
  if (process.argv.includes('--force')) {
    clearReports();
    console.log('Cleared existing reports.');
  } else {
    console.log('Database already has reports — run "npm run seed -- --force" to wipe and re-seed.');
    process.exit(0);
  }
}

function placeholderSvg(label, sub) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600" viewBox="0 0 800 600">
  <rect width="800" height="600" fill="#FAF7F1"/>
  <rect width="800" height="26" fill="#1A1712"/>
  ${Array.from({ length: 25 }, (_, i) => `<circle cx="${16 + i * 32}" cy="13" r="5" fill="#F2B800"/>`).join('')}
  <rect x="40" y="470" width="720" height="4" fill="#1A1712"/>
  <text x="60" y="300" font-family="Arial, sans-serif" font-size="52" font-weight="800" fill="#1A1712">${label}</text>
  <text x="60" y="350" font-family="Arial, sans-serif" font-size="24" fill="#575043">${sub}</text>
  <text x="60" y="530" font-family="Arial, sans-serif" font-size="18" fill="#8A8272">Demo placeholder — real reports carry the reporter's photo</text>
</svg>`;
}

const daysAgo = (n) => new Date(Date.now() - n * 86400000).toISOString();

const SEEDS = [
  {
    kind: 'issue', category: 'no-dropped-kerb', status: 'sent', severity: 4, days: 21,
    reporter: 'Maya', confirmations: 6,
    lat: 51.50395, lng: -0.11425,
    address: 'Belvedere Road, South Bank, London SE1, United Kingdom',
    description: 'No dropped kerb on the east side of the crossing — wheelchair users have to detour 150m or roll on the road.',
    hazards: 'People are forced into the carriageway alongside moving traffic.',
    affected: ['wheelchair users', 'people with limited mobility', 'people with prams or strollers'],
    fixes: ['Install a dropped kerb with tactile paving on both sides of the crossing', 'Add a temporary ramped edge while works are scheduled'],
  },
  {
    kind: 'issue', category: 'broken-lift', status: 'acknowledged', severity: 5, days: 34,
    reporter: 'Sam', confirmations: 11,
    lat: 51.50331, lng: -0.11957,
    address: 'Waterloo Station, York Road entrance, London SE1, United Kingdom',
    description: 'Street-to-concourse lift out of order for over a month. Step-free access signposted but not usable.',
    hazards: 'No step-free route between street and concourse at this entrance.',
    affected: ['wheelchair users', 'people with limited mobility', 'older people'],
    fixes: ['Repair the lift and publish a maintenance schedule', 'Provide staffed assistance and clear signage to the nearest working lift'],
  },
  {
    kind: 'issue', category: 'blocked-path', status: 'verified', severity: 3, days: 5,
    reporter: 'Priya', confirmations: 3,
    lat: 51.50722, lng: -0.11035,
    address: 'Upper Ground, South Bank, London SE1, United Kingdom',
    description: 'Café A-boards and rental bikes block the footway to under a metre wide.',
    hazards: '',
    affected: ['wheelchair users', 'blind and low-vision people', 'people with prams or strollers'],
    fixes: ['Remove or relocate the obstructions', 'Mark and enforce a minimum 1.5m clear footway corridor'],
  },
  {
    kind: 'issue', category: 'no-ramp', status: 'verified', severity: 5, days: 12,
    reporter: 'Jordan', confirmations: 4,
    lat: 51.5057, lng: -0.10727,
    address: 'Blackfriars Road, Southwark, London SE1, United Kingdom',
    description: 'Entrance to the community hall has three steps and no ramp — no step-free entrance anywhere on the block.',
    hazards: '',
    affected: ['wheelchair users', 'people with limited mobility'],
    fixes: ['Install a compliant permanent ramp (gradient 1:14 or gentler) with handrails', 'Offer a portable ramp and doorbell at the entrance in the interim'],
  },
  {
    kind: 'issue', category: 'no-tactile', status: 'reported', severity: 3, days: 2,
    reporter: 'Maya', confirmations: 0,
    lat: 51.50085, lng: -0.11655,
    address: 'Chicheley Street, Waterloo, London SE1, United Kingdom',
    description: 'Signalised crossing has no tactile paving on either side.',
    hazards: 'Blind pedestrians get no underfoot warning of the carriageway edge.',
    affected: ['blind and low-vision people'],
    fixes: ['Install blister tactile paving at both crossing points'],
  },
  {
    kind: 'issue', category: 'poor-surface', status: 'fixed', severity: 3, days: 60,
    reporter: 'Sam', confirmations: 2,
    lat: 51.50589, lng: -0.11633,
    address: 'Queen’s Walk, South Bank, London SE1, United Kingdom',
    description: 'Broken paving slabs with 5cm trip edges along the riverside walk.',
    hazards: '',
    affected: ['people with limited mobility', 'older people', 'blind and low-vision people'],
    fixes: ['Resurface the damaged section to a firm, level finish'],
  },
  {
    kind: 'issue', category: 'bad-parking', status: 'fixed', severity: 3, days: 75,
    reporter: 'Priya', confirmations: 1,
    lat: 51.49882, lng: -0.11217,
    address: 'Lambeth Road, Lambeth, London SE1, United Kingdom',
    description: 'Accessible bay markings worn away; bay constantly used by delivery vans.',
    hazards: '',
    affected: ['wheelchair users', 'people with limited mobility'],
    fixes: ['Repaint and enforce the accessible bay to standard dimensions'],
  },
  {
    kind: 'feature', category: 'step-free', status: 'verified', severity: null, days: 9,
    reporter: 'Jordan', confirmations: 5,
    lat: 51.50624, lng: -0.11477,
    address: 'Royal Festival Hall, Southbank Centre, London SE1, United Kingdom',
    description: 'Level entrance from the riverside terrace, automatic doors, lifts to all floors.',
    hazards: '', affected: [],
    fixes: ['Step-free from street to all public floors — reliable route for wheelchair users.'],
  },
  {
    kind: 'feature', category: 'accessible-toilet', status: 'verified', severity: null, days: 15,
    reporter: 'Maya', confirmations: 2,
    lat: 51.50497, lng: -0.11312,
    address: 'Jubilee Gardens, South Bank, London SE1, United Kingdom',
    description: 'Changing Places toilet, RADAR key, open 8am-10pm.',
    hazards: '', affected: [],
    fixes: ['Full Changing Places facility — hoist, adult changing bench and space for two assistants.'],
  },
  {
    kind: 'feature', category: 'ramp', status: 'verified', severity: null, days: 30,
    reporter: 'Alex', confirmations: 1,
    lat: 51.50776, lng: -0.0994,
    address: 'Tate Modern, Bankside, London SE1, United Kingdom',
    description: 'Long gentle ramp into the Turbine Hall — the nicest entrance in London.',
    hazards: '', affected: [],
    fixes: ['Gentle-gradient main entrance usable by everyone, no separate "accessible door".'],
  },
];

for (const s of SEEDS) {
  const id = randomUUID();
  const cLabel = categoryLabel(s.kind, s.category);
  const svgName = `${id}.svg`;
  writeFileSync(
    path.join(photosDir, svgName),
    placeholderSvg(cLabel.toUpperCase(), s.address.split(',')[0]),
  );

  const letter = s.kind === 'issue'
    ? templateLetter({
        id, categoryLabel: cLabel, description: s.description,
        address: s.address, lat: s.lat, lng: s.lng, severity: s.severity,
        affected: s.affected, fixes: s.fixes,
        standards: standardsFor('GB'), reporter: s.reporter,
      })
    : '';

  insertReport({
    id, kind: s.kind, category: s.category,
    description: s.description, reporter: s.reporter,
    lat: s.lat, lng: s.lng, address: s.address, country: 'GB',
    photo: `/photos/${svgName}`,
    status: s.status, severity: s.severity, confidence: 0.5,
    affected: s.affected, hazards: s.hazards, fixes: s.fixes,
    summary: `Demo verification: recorded as "${cLabel}" from the reporter's photo and description.`,
    letter, ai_mock: true, confirmations: s.confirmations,
    created_at: daysAgo(s.days), updated_at: daysAgo(Math.max(0, s.days - 1)),
  });
}

console.log(`Seeded ${SEEDS.length} demo reports around London Southbank.`);
