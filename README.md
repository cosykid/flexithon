# AccessMap

Crowdsourced accessibility-barrier reporting for wheelchair users and people with
walking-centric disabilities. Report an inaccessible place with a photo; an AI
pipeline verifies the photo, investigates the venue's public accessibility claims
online, and classifies the report. Verified reports appear as clustered pins on a map.

## Substantiation tiers

| Tier | Meaning | On map |
|---|---|---|
| `web_search` | Tavily | Search for the venue's accessibility online; returns title/URL/snippet results |
| `get_place_accessibility` | Google Places (New) | Read the venue's own `accessibilityOptions.wheelchairAccessibleEntrance` claim |
| `submit_verdict` | (terminal) | Report facts: does the image confirm the barrier, barrier type, venue claim, corroboration, contradiction, confidence, reasoning, and a source link per verified claim |

Guardrails: a **60-second deadline** and **5-iteration cap**; a **vision-less fallback** that retries once without the image on HTTP 400 (so text-only endpoints degrade to *unsubstantiated* rather than hanging); and on any thrown error the report is left `pending` with `retry_count` incremented, so the sweep can retry up to 3 times.

The Google Places claim is treated as **ground truth** — whatever `wheelchairAccessibleEntrance` returns overrides the model's echoed value. For untagged reports (no `place_id`, so the Places tool can't fire), the function falls back to a `venue_claims_accessible` value cached on the location from earlier reports or seed data.

### 3. Deterministic classification

`classify.ts` maps the verdict's facts to a `{status, tier}` with these rules, in order:

1. Photo **contradicts** the report (or is unrelated/spam) → `rejected`.
2. No **confirming** photo (`image_confirms_barrier !== true`, i.e. false *or* null) → `classified` / **unsubstantiated**. A confirming photo is the prerequisite for any map-visible tier.
3. Photo confirms **and** the venue claims accessible → `classified` / **partially substantiated** (conflicting evidence).
4. Photo confirms **and** the venue is silent or admits inaccessibility → `classified` / **substantiated**.

`web_corroboration_found` (stored in its own boolean column) and `confidence` (stored inside the `ai_reasoning` JSON) are recorded but do **not** affect the tier. The full reasoning trail — model name, reasoning text, confidence, and the log of tool calls — is stored in `ai_reasoning` on the report for display in the detail sheet.

Every verified claim carries a citation back to where the information was found, so users can independently check the source. The model must cite `{url, title, claim}` entries in `submit_verdict`; the server only keeps URLs that actually appeared in a tool result during that run (web-search results or the venue's Google Maps link), so a hallucinated link can never reach the database. Because the Places claim is ground truth, its Google Maps link is attached automatically whenever the tool fired — even if the model forgot to cite it. Sanitized citations are stored as rows in the **`report_sources`** table; the app lists their titles alongside the AI summary but fetches the destination URL from Supabase only when the user taps a link.

### 4. Rollup & auto-promotion (Postgres trigger)

The per-location rollup lives in the database, not the edge function, so it stays atomic under concurrent classifications and also fires for seed data. On every `reports` insert or update of `tier`/`status`, `refresh_location_rollup` recomputes the affected location's counts (over **classified** reports only) and sets `effective_tier`:

- `substantiated` if there's ≥1 substantiated report **or** ≥5 partial reports (`PROMOTION_THRESHOLD = 5`);
- `partially_substantiated` if 1–4 partials and no substantiated;
- `null` otherwise (no classified evidence → invisible on the map).

### 5. Rendering pins

The map (`flutter_map` + `flutter_map_marker_cluster`) fetches only the visible viewport. Map movement is debounced 300 ms and written into a structural-equality `Bbox` record; `points_in_bbox` returns up to 500 locations with a non-null `effective_tier` inside the envelope. Pins are tier-coloured pucks with a notch that lands on the exact point; clusters draw a white circle with a proportional ring — red for the substantiated fraction, amber for everything else.

## Data model

Two tables: individual **`reports`** roll up into **`locations`** (the map pins). Clients never write counts or tiers directly — those flow only through the `SECURITY DEFINER` trigger and the service role.

### Tables

**`locations`** — one row per place, one map pin.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `geog` | `geography(point,4326)` | WGS84; GIST-indexed |
| `place_ref` | text UNIQUE | Google `place_id`, null for untagged spots |
| `name`, `address` | text | |
| `venue_claims_accessible` | boolean | cached from Google Places, used as a fallback for untagged reports |
| `partial_count`, `substantiated_count` | int | maintained by the trigger |
| `effective_tier` | `report_tier` | pin colour source; null hides the pin |
| `created_at` | timestamptz | |

**`reports`** — one crowdsourced observation.
| Unsubstantiated | Description only — no confirming photo, no online corroboration | No |
| Partially substantiated (amber) | Photo confirms the barrier, but the venue claims accessibility online | Yes |
| Substantiated (red) | Photo confirms the barrier and the venue claims nothing / inaccessibility — or ≥5 partial reports at one location (auto-promoted) | Yes |

The AI reports facts (what the photo shows, what the venue claims); the tier rules
are deterministic code (`supabase/functions/classify-report/classify.ts` + the
rollup trigger in `supabase/migrations/004_trigger.sql`).

**`report_sources`** — one row per source link the AI verifier cited (migration `005_sources.sql`).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `report_id` | uuid → `reports` | cascade delete |
| `url` | text NOT NULL | fetched by the app at click time, never in list queries |
| `title`, `claim` | text | display label and which verified claim the link supports |
| `position` | int | citation order from the verdict |
| `created_at` | timestamptz | |

RLS mirrors the parent report's visibility (own reports, or classified partial/substantiated); only the service role writes rows.

**Enums**: `report_tier` = `unsubstantiated | partially_substantiated | substantiated` (the `unsubstantiated` value exists but the pipeline leaves `effective_tier` null instead); `report_status` = `pending | classified | rejected`.
## Stack

- **Flutter** — `google_maps_flutter` (custom canvas-drawn pins + zoom-based clustering), Riverpod, `supabase_flutter`
- **Supabase** — Postgres + PostGIS, anonymous auth, Storage (photos), Edge Function (Deno) for verification
- **AI** — any OpenAI-compatible `/chat/completions` endpoint with vision + tool calling
- **Tools the AI can call** — Tavily web search, Google Places (New) `accessibilityOptions.wheelchairAccessibleEntrance`
- **Maps** — Google Maps Platform: Maps SDK (Android/iOS/JS) with a Kerb-styled basemap, Places API for venue tagging and inline map location search

## Setup

### 1. Supabase

```bash
# Create a project at supabase.com, then:
supabase link --project-ref <ref>
supabase db push                      # runs migrations 001-004
# Seed demo data (Sydney): paste supabase/seed.sql into the dashboard
# SQL editor, or:
psql "$(supabase db url 2>/dev/null || echo postgresql://postgres:<db-pass>@db.<ref>.supabase.co:5432/postgres)" -f supabase/seed.sql
```

(Local stack instead: `supabase start` then `supabase db reset` — it applies
migrations and `seed.sql` automatically.)

Dashboard steps:
- **Auth → Providers → enable Anonymous sign-ins**
- **Storage → create private bucket `report-photos`** (policies are in `002_rls.sql`)

### 2. Edge function

```
flexithon/
├─ README.md
├─ SETUP.md                     ← full go-live walkthrough (start here to run it)
├─ app/                         Flutter client ("accessmap")
│  ├─ pubspec.yaml
│  ├─ android/ ios/ web/        committed platform targets (permissions already wired)
│  ├─ macos/ windows/ linux/    committed desktop targets
│  ├─ run.example.sh            copy → run.sh, fill keys, launch
│  ├─ test/
│  └─ lib/
│     ├─ main.dart              bootstrap: Supabase init + anon auth, Riverpod scope,
│     │                         MaterialApp, two-tab shell, desktop phone-frame
│     ├─ core/
│     │  ├─ env.dart            compile-time --dart-define config (+ USE_FAKE)
│     │  ├─ supabase.dart       global `supa` client getter
│     │  ├─ theme.dart          "Kerb" design system: colours, type, TierStyle
│     │  └─ ui.dart             shared widgets: tiles, pins, clusters, badges
│     ├─ models/
│     │  ├─ venue.dart          Venue (+ fromPlacesJson)
│     │  ├─ map_point.dart      one points_in_bbox row
│     │  └─ report.dart         Report + ReportTier/ReportStatus enums
│     ├─ data/
│     │  ├─ reports_repository.dart          abstract interface + ReportDraft
│     │  ├─ supabase_reports_repository.dart real backend (RPCs, storage, edge fn)
│     │  ├─ fake_reports_repository.dart     in-memory demo backend
│     │  └─ places_api.dart                  Google Places (New) Text Search (report tagging + map search)
│     └─ features/
│        ├─ map/                map_providers.dart, map_screen.dart, map_search_bar.dart, tier_filter_chips.dart
│        ├─ new_report/         new_report_controller.dart, new_report_flow.dart, venue_search_page.dart
│        ├─ report_detail/      report_detail_sheet.dart
│        └─ my_reports/         my_reports_screen.dart
└─ supabase/
   ├─ migrations/
   │  ├─ 001_schema.sql         PostGIS, enums, locations + reports, indexes
   │  ├─ 002_rls.sql            RLS + storage.objects policies
   │  ├─ 003_rpc.sql            points_in_bbox, upsert_location
   │  ├─ 004_trigger.sql        refresh_location_rollup + reports_rollup trigger
   │  └─ 005_sources.sql        report_sources (per-claim citation links) + RLS
   ├─ functions/classify-report/   Deno AI verification pipeline
   │  ├─ index.ts               HTTP entry: dispatch, load, classify, write, retry
   │  ├─ aiClient.ts            OpenAI-compatible vision + tool-use loop
   │  ├─ tools.ts               web_search / get_place_accessibility / submit_verdict
   │  ├─ classify.ts            deterministic Verdict → {status, tier}
   │  ├─ geo.ts                 EWKB/GeoJSON PostGIS point parsing
   │  └─ classify_test.ts       Deno unit tests (no keys needed)
   └─ seed.sql                  ~31 Sydney locations / ~47 reports + Rosie's Cafe prop
```

The model must support **vision and tool calling**. Test both on day 1:
`supabase functions serve classify-report` and curl it with a seeded report id.

Unit tests for the tier rules and geometry parsing (no keys needed):

The app is mobile-first and portrait-first, built around a two-tab shell (**Map** and **My reports**) with a custom floating pill nav bar; the map runs edge-to-edge beneath it. It isn't orientation-locked — mobile devices are free to rotate (the iOS plist permits landscape). Only the desktop build is constrained: on non-web Linux/macOS/Windows the whole app renders inside a fixed 412×892 rounded phone frame so the mobile layout displays as designed. There is a single light theme — the **"Kerb"** design system (named after the kerb cut): warm paper surfaces, deep petrol ink, a teal brand, Sora display + Inter body fonts, Material 3, and 56 dp touch targets.

### Screens

- **Map** — Google Maps with a Kerb-styled basemap, viewport-debounced fetching, tier-coloured clustered pins, a my-location button, a *Report barrier* FAB, and tier filter chips for the two visible tiers. A **location search** control sits top-left: tap the round search button to expand an inline pill search bar; debounced Google Places Text Search (biased to the map centre, 30 km radius) shows results in a dropdown — tap one to fly the map there (zoom 16). Requires `GOOGLE_PLACES_KEY`. Tapping a pin opens the report-detail sheet.
- **New report** — the four-step flow (photo, location mini-map you can tap to fine-tune, optional venue search, description) with a sticky submit bar. On success it invalidates the map and My Reports providers so both refresh.
- **Report detail** — a draggable bottom sheet showing a location's **classified** reports: tier badge, report count, per-report photo (via 1-hour signed URLs), a barrier-type tag, date, description, and an expandable AI-verification summary with tappable **source links** — each verified claim cites the page or Google Maps listing where the information was found. Partially-substantiated locations get a "venue claims accessible online, but photos say otherwise" callout.
- **My reports** — your own submissions (any status) with pull-to-refresh; status-driven cards — pending shows *Verifying…* with an hourglass, rejected shows a block icon, classified adopts the tier's colour/icon/label.

### Repository abstraction & the USE_FAKE parachute

If a report gets stuck pending (app killed mid-submit, endpoint down), sweep:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/classify-report" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -d '{"sweep": true}'
```

### 3. Flutter app

```bash
cd app
flutter create . --org com.hackathon --project-name accessmap   # generates android/ios
flutter pub get
MAPS_API_KEY=<android-maps-key> flutter run \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=GOOGLE_PLACES_KEY=<places-key>
```

Google Maps SDK keys are platform-side (not dart-defines):
- **Android** — `MAPS_API_KEY` env var / gradle property (wired in `android/app/build.gradle.kts`)
- **iOS** — `GMSApiKey` entry in `ios/Runner/Info.plist`
- **Web** — key in the maps `<script>` tag in `web/index.html`

Platform permissions (after `flutter create`):
- **Android** `android/app/src/main/AndroidManifest.xml`: `ACCESS_FINE_LOCATION`, `CAMERA`, `INTERNET`
- **iOS** `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`

Demo parachute — full UI on fake in-memory data, zero network:

```bash
flutter run --dart-define=USE_FAKE=true
```

### API keys needed (all free tiers)

| Key | Where | Card? |
|---|---|---|
| Supabase URL + anon key | supabase.com project settings | No |
| Google Maps SDK | GCP console, enable Maps SDK for Android / iOS and Maps JavaScript API — mobile map loads are unlimited free, JS gets $200/mo credit | **Yes** (billing enabled) |
| Tavily | app.tavily.com (1,000 credits/mo) | No |
| Google Places | GCP console, enable Places API (New) — 5k Pro calls/mo | **Yes** (billing must be enabled; can share the GCP project/key with the Maps SDK) |
| OpenAI-compatible AI | your provider of choice | Depends |

## Demo script

1. Open the map — Sydney seeded with ~30 locations; clusters split as you zoom.
   Tap the top-left search button to find an address, suburb, or venue; selecting a
   result flies the map there.
2. Tap a pin — detail sheet with photo, tier badge, AI reasoning; amber pins show
   the "venue claims accessible, photos say otherwise" callout.
3. Submit a live report (photo of stairs) — watch it flip from *Verifying…* to a tier.
4. **The promotion moment**: "Rosie's Cafe (demo)" is seeded with exactly 4
   partially-substantiated reports. Submit a 5th against it — the rollup trigger
   promotes the location and the pin turns red on the next map refresh.
   How the 5th report attaches: untagged reports reuse the nearest existing
   location within 30 m (`upsert_location`), and the venue's cached
   "claims accessible" flag makes the new report classify as partial.
   **Before the demo, edit Rosie's coordinates in `seed.sql` to the venue
   you'll be standing in** so your live GPS lands within 30 m.

## Repo layout

```
app/         Flutter app (lib/ only — run `flutter create .` inside for platforms)
supabase/
  migrations/  schema, RLS, RPCs, rollup/promotion trigger
  functions/classify-report/  AI verification pipeline (Deno)
  seed.sql     ~30 Sydney demo locations + the 4-partial promotion prop
```
