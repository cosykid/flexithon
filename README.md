# CurbCut

**See the barriers. Fix the city.**

Photograph an accessibility barrier with your phone → Claude verifies the photo, rates the severity, and drafts a formal report letter to the council or facility owner → the barrier lands on a live community map that also records verified *accessible* places (the knowledge layer over the street map).

Named after the [curb-cut effect](https://en.wikipedia.org/wiki/Curb_cut_effect): accessibility fixes help everyone.

## What it does

- **Phone-camera reporting** — the Report button opens the camera on mobile (`capture="environment"`), grabs GPS automatically, and compresses the photo client-side. No account needed.
- **AI verification (Claude vision)** — every photo is checked against the reported category and description: is this a real barrier? How severe (1–5)? Who does it affect? What are the concrete fixes? Unverifiable photos stay in "awaiting verification" instead of polluting the map.
- **Auto-drafted council letters** — for verified barriers Claude writes a formal, courteous letter citing the correct legislation for the country (Equality Act 2010, ADA, AS 1428, …) with evidence, GPS coordinates and requested remediation. Copy it or open it straight in your email client.
- **Accessibility knowledge map** — barriers colored by severity, green pins for verified accessible features (step-free entrances, Changing Places toilets, working lifts…), blue for fixed, dashed grey for pending. Filterable.
- **Duplicate detection** — a report within 30 m of an open report of the same type becomes a "+1 confirmation" instead of a duplicate pin, so councils see *demand*, not noise.
- **Status lifecycle** — reported → verified → sent → acknowledged → fixed, visible as a timeline on every report.
- **Council dashboard** (`/council.html`) — open barriers, median days open, category breakdown, and one-click status updates that reporters see instantly.
- **Community layer** — "still there" confirmations, optional reporter names, and a street-champions leaderboard.
- **Accessible by design** — Atkinson Hyperlegible type (designed by the Braille Institute), WCAG-minded contrast, keyboard/focus support, color-blind-safe status palette with shape + size + label secondary encoding.

## Quickstart

```bash
npm install
npm run seed     # optional: demo data around London Southbank
npm start        # → http://localhost:4141
```

Works out of the box with **no API key** (demo mode: deterministic mock verification + template letters).

### Enable real AI verification

```bash
cp .env.example .env    # put your ANTHROPIC_API_KEY in it
npm start
```

Uses `claude-opus-4-8` vision with strict JSON-schema output. Override with `ANTHROPIC_MODEL`, force demo mode with `CURBCUT_AI=mock`. An `ant auth login` profile also works — no env var needed.

### Phone demo

Run the server, then open `http://<your-laptop-ip>:4141` on a phone on the same Wi-Fi. The Report button opens the camera directly. (Geolocation on non-localhost HTTP is blocked by some browsers — tap the map to place the pin instead, or tunnel with HTTPS.)

## Architecture

```
web/            no-build vanilla JS frontend
  index.html    map app (Leaflet + OpenStreetMap tiles)
  council.html  council dashboard
server/
  index.js      Express 5 API + static hosting
  ai.js         Claude vision verification + letter drafting (mock fallback)
  db.js         node:sqlite (zero native deps), haversine dedupe, stats
  geocode.js    Nominatim reverse geocoding + per-country standards
  seed.js       demo data generator
data/           runtime: sqlite db + photos (gitignored)
```

| Endpoint | Purpose |
|---|---|
| `POST /api/reports` | photo (data URL) + GPS + category → dedupe → geocode → AI verify → pin |
| `GET /api/reports` | all reports for the map |
| `POST /api/reports/:id/confirm` | community "+1 still there" |
| `POST /api/reports/:id/status` | council status updates |
| `GET /api/stats` | dashboard tiles, category counts, leaderboard |

## Roadmap ideas

- Council contact directory (auto-address the letter by boundary lookup) + one-click send with tracking
- Re-verification prompts ("is this still broken?") and photo-proof of fixes
- Accessible routing: penalise paths through open barriers, prefer verified features
- Overpass/OSM POI context passed to the AI verifier; write verified features back to OSM
- Offline queue (PWA service worker) for reporting without signal
- Council authentication + per-authority scoping; public response-time league table
- Exports for councils: GeoJSON / CSV / monthly digest email

---
Prototype built for a hackathon — no auth, single sqlite file, trusts geolocation input.
