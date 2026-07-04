# AccessMap

Crowdsourced accessibility-barrier reporting for wheelchair users and people with walking-centric disabilities. Snap a photo of an inaccessible place — a stepped entrance, a missing ramp, a doorway too narrow for a chair, a broken lift — and an AI verification pipeline checks the photo, investigates the venue's public accessibility claims online, and classifies the report. Verified reports surface as clustered, colour-coded pins on a map so others can route around barriers before they hit them. The AI only *reports facts*; the decision about whether a report is trustworthy enough to show, and at what confidence, is made by deterministic code and a database trigger.

AccessMap is an open-source hackathon project: a Flutter client on top of a Supabase (Postgres + PostGIS) backend, with a Deno edge function driving the verification.

## Features

- **One-tap barrier reporting** — photo + GPS + optional venue tag + a short description; only a location pin and a description are required.
- **Server-side AI verification** — a vision-and-tool-calling model examines the photo, searches the web (Tavily), and looks up the venue's declared wheelchair accessibility (Google Places New) before a verdict is committed.
- **Trust tiers, not just dots** — every pin is coloured *and* shaped by a substantiation tier so meaning never rides on colour alone.
- **Live map with viewport clustering** — pins are fetched per-viewport from a PostGIS bounding-box query and clustered client-side; cluster rings show severity proportionally.
- **Auto-promotion of repeat reports** — five or more partially-substantiated reports at one spot promote the location to fully substantiated, computed atomically in the database.
- **Anonymous by default** — device-scoped anonymous auth; no account or PII required to contribute.
- **Demo parachute** — the entire UI runs against in-memory fake data with zero network via a single compile-time flag.

## Substantiation tiers

Each report is classified into one of three tiers. The tier drives every pin colour, badge, and filter chip in the app — and colour is always paired with a distinct icon **shape** for accessibility (an octagon, a triangle, a question mark).

| Tier | Icon | Meaning | On map |
|---|---|---|---|
| **Unsubstantiated** (grey) | ❔ help | Description only — no confirming photo, or the photo doesn't confirm the barrier | No |
| **Partially substantiated** (amber) | ⚠️ triangle | Photo confirms the barrier, **but** the venue claims wheelchair accessibility online | Yes |
| **Substantiated** (red) | 🛑 octagon | Photo confirms the barrier and the venue claims nothing / admits inaccessibility — **or** ≥5 partial reports at one location (auto-promoted) | Yes |

The AI reports facts (what the photo shows, what the venue claims); the tier rules are deterministic code in [`supabase/functions/classify-report/classify.ts`](supabase/functions/classify-report/classify.ts), and the ≥5-partial auto-promotion is the rollup trigger in [`supabase/migrations/004_trigger.sql`](supabase/migrations/004_trigger.sql).

> The map only ever shows substantiated + partially-substantiated locations. The default tier filter excludes unsubstantiated, and the map RPC filters out any location whose tier hasn't been computed. Unsubstantiated reports still appear in your own **My Reports**.

## How it works

### End-to-end flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│  FLUTTER APP                                                              │
│                                                                           │
│  Map screen  ──(points_in_bbox RPC, 300ms debounced viewport)──►  pins    │
│                                                                           │
│  New-report flow: photo → GPS → optional venue → description              │
│        │ compress ~1024px / q80 JPEG (client-side, mobile)                │
│        ▼                                                                   │
│    submitReport(draft)                                                     │
│        │                                                                   │
│        ├─► upsert_location RPC  (find-or-create; 30 m nearest reuse)       │
│        ├─► upload photo → private bucket  report-photos/<uid>/<uuid>.jpg   │
│        ├─► insert reports row (status='pending', PostGIS geog point)      │
│        └─► fire-and-forget invoke  classify-report  {report_id}           │
└───────────────────────────────────────────┬───────────────────────────────┘
                                             │
┌────────────────────────────────────────────▼──────────────────────────────┐
│  EDGE FUNCTION  classify-report  (Deno, service role)                       │
│                                                                             │
│  load report + joined location + photo (data URI)                           │
│      │                                                                       │
│      ▼   OpenAI-compatible /chat/completions loop (vision + tools)          │
│   ┌────────────────────────────────────────────────────────────┐           │
│   │  model may call:  web_search (Tavily)                        │           │
│   │                   get_place_accessibility (Google Places New)│  ≤5 iters │
│   │  then MUST call:  submit_verdict  (facts only)               │  60s cap  │
│   └────────────────────────────────────────────────────────────┘           │
│      │  normalizeVerdict → Places-claim override → location-cache fallback  │
│      ▼                                                                       │
│   classify()  ── deterministic rules ──►  {status, tier}                    │
│      │                                                                       │
│      └─► UPDATE reports.{status,tier,barrier_type,...,ai_reasoning}         │
│          + cache locations.venue_claims_accessible                          │
└───────────────────────────────────────────┬────────────────────────────────┘
                                             │  AFTER INSERT/UPDATE OF tier,status
┌────────────────────────────────────────────▼──────────────────────────────┐
│  POSTGRES TRIGGER  refresh_location_rollup                                  │
│    recompute partial_count / substantiated_count (classified only)          │
│    effective_tier = substantiated           if sc>0 OR pc>=5                │
│                   = partially_substantiated  if pc>0                        │
│                   = null                     otherwise (invisible on map)   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1. Submitting a report

The new-report flow is a four-step form managed by a `NewReportController` (`StateNotifier`): **photo → location → optional venue → description**. Photos are downscaled client-side to ~1024 px / JPEG quality 80 via `flutter_image_compress` (roughly 150–300 KB) so the verifier's vision request body stays small; on platforms without a compressor (e.g. desktop) it silently uploads the original bytes.

Location handling has three paths: in `USE_FAKE` mode the pin defaults to a Sydney coordinate; if the live GPS read throws (desktop trial, airplane mode) it drops that same **movable** default pin plus a "tap the map to adjust" hint; and if location permission is explicitly **denied**, it surfaces an error and leaves the (required) location step unset. Only a location pin and a non-empty description are required — photo and venue are optional, though a photoless report can never become map-visible.

`submitReport` runs a multi-step server sequence:

1. **`upsert_location` RPC** returns a location id — reusing an existing venue (matched on Google `place_id`) or the nearest location within **30 metres** for untagged spots, else creating a new one.
2. If a photo is present, it's uploaded to the private `report-photos` Storage bucket at `<user_id>/<uuid>.jpg`.
3. A `reports` row is inserted with `status='pending'` and a PostGIS `geog` point built from the **raw GPS pin** (`SRID=4326;POINT(lng lat)` — longitude first).
4. The `classify-report` edge function is invoked **fire-and-forget** with the new report id. Failures are swallowed; the on-demand sweep endpoint is the safety net.

The report shows as *Verifying…* in **My Reports** immediately, but won't appear on the map until the server assigns it a visible tier.

### 2. AI verification (the `classify-report` edge function)

The edge function is a Deno `Deno.serve` handler with two invocation modes:

- `{ "report_id": "<uuid>" }` — classify one report right after insert.
- `{ "sweep": true }` — batch-retry up to 10 pending reports older than 2 minutes with `retry_count < 3`. Nothing in the repo schedules this; it's an operator-invoked recovery endpoint (curl it, or wire it to an external scheduler).

It runs as the **service role** (bypassing RLS) and is **idempotent** — any report whose status is no longer `pending` returns `already processed` without re-running.

For each report it loads the row (joined with its location) and, if present, downloads the photo (dropped if over 4 MiB) as a base64 `data:image/jpeg` URI. The PostGIS `geog` value — which PostgREST returns as an **EWKB hex string**, not GeoJSON — is decoded by `geo.ts` (both formats supported; unparseable geometry degrades to `0,0`).

It then drives an **OpenAI-compatible `/chat/completions`** loop (configurable endpoint/model, default `gpt-4o-mini`) with vision and tool calling. The model is told to examine the photo and, when a venue is tagged, gather facts using tools — then call `submit_verdict` exactly once:

| Tool | Backend | Purpose |
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

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid → `auth.users` | |
| `location_id` | uuid → `locations` | |
| `geog` | `geography(point,4326)` | exact GPS of the report (raw pin, not the venue) |
| `photo_path` | text | path in `report-photos` bucket |
| `description` | text NOT NULL | |
| `barrier_type` | text | AI-set: `stairs` \| `no_ramp` \| `narrow_entrance` \| `broken_lift` \| `other` |
| `status` | `report_status` | `pending` \| `classified` \| `rejected` (default `pending`) |
| `tier` | `report_tier` | null until classified |
| `image_confirms_barrier`, `venue_claims_accessible`, `web_corroboration_found` | boolean | AI-recorded facts |
| `ai_reasoning` | jsonb | `{model, reasoning, confidence, tool_calls}` |
| `retry_count` | int | incremented by the sweep on failure |
| `created_at` | timestamptz | |

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

PostGIS points are stored as `geography(point,4326)` and constructed with `st_makepoint(lng, lat)` — **longitude first**. Distances use geography semantics, so the `30` in `upsert_location` means 30 metres.

### RPCs

- **`points_in_bbox(min_lng, min_lat, max_lng, max_lat)`** — the viewport pin query. Returns up to 500 locations with a non-null `effective_tier` intersecting the envelope. `report_count` is `partial_count + substantiated_count` — so a pin's number counts only *classified* partial/substantiated reports and can be lower than the true number of reports at that spot (unsubstantiated and pending/rejected are excluded, as are locations with no visible tier).
- **`upsert_location(p_lat, p_lng, p_place_ref, p_name, p_address)`** — find-or-create. Tagged venues upsert on `place_ref` (keeping the existing name if set); untagged reports reuse the nearest existing location within **30 m** so repeat reports at one spot pile onto a single pin — which is what lets the ≥5-partial promotion fire.

### Row-level security

RLS is enabled on both tables. Anonymous-authenticated clients (role `authenticated`) can only **insert** reports (attributed to themselves) and locations, and **read** all locations, their own reports (any status), plus any classified partial/substantiated reports. There are **no UPDATE/DELETE policies** — every count/tier mutation goes through the service role or the `SECURITY DEFINER` trigger.

Photos live in the `report-photos` bucket (created as private). Users may only upload into a folder named after their own uid — but the SELECT policy is `bucket_id = 'report-photos'`, so **any** authenticated user can read any photo in the bucket; reads are not owner-scoped. The app displays photos through short-lived (1-hour) signed URLs.

## Project structure

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
│     │  └─ places_api.dart                  Google Places (New) Text Search
│     └─ features/
│        ├─ map/                map_providers.dart, map_screen.dart, tier_filter_chips.dart
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

> The platform folders (`android/`, `ios/`, `web/`, `macos/`, `windows/`, `linux/`) are **already committed** — camera/location permissions are declared in the Android manifest and iOS usage strings, so no `flutter create` is needed to run.

## The Flutter client

The app is mobile-first and portrait-first, built around a two-tab shell (**Map** and **My reports**) with a custom floating pill nav bar; the map runs edge-to-edge beneath it. It isn't orientation-locked — mobile devices are free to rotate (the iOS plist permits landscape). Only the desktop build is constrained: on non-web Linux/macOS/Windows the whole app renders inside a fixed 412×892 rounded phone frame so the mobile layout displays as designed. There is a single light theme — the **"Kerb"** design system (named after the kerb cut): warm paper surfaces, deep petrol ink, a teal brand, Sora display + Inter body fonts, Material 3, and 56 dp touch targets.

### Screens

- **Map** — `flutter_map` with a Stadia/CARTO basemap, viewport-debounced fetching, tier-coloured clustered pins, a my-location button, a *Report barrier* FAB, and tier filter chips for the two visible tiers. Tapping a pin opens the report-detail sheet.
- **New report** — the four-step flow (photo, location mini-map you can tap to fine-tune, optional venue search, description) with a sticky submit bar. On success it invalidates the map and My Reports providers so both refresh.
- **Report detail** — a draggable bottom sheet showing a location's **classified** reports: tier badge, report count, per-report photo (via 1-hour signed URLs), a barrier-type tag, date, description, and an expandable AI-verification summary with tappable **source links** — each verified claim cites the page or Google Maps listing where the information was found. Partially-substantiated locations get a "venue claims accessible online, but photos say otherwise" callout.
- **My reports** — your own submissions (any status) with pull-to-refresh; status-driven cards — pending shows *Verifying…* with an hourglass, rejected shows a block icon, classified adopts the tier's colour/icon/label.

### Repository abstraction & the USE_FAKE parachute

All data access funnels through one `ReportsRepository` interface behind a Riverpod `repositoryProvider`. It has two implementations, selected at **build time**:

- **`SupabaseReportsRepository`** (production) — the RPCs, storage upload, edge-function trigger, and signed URLs described above.
- **`FakeReportsRepository`** (`--dart-define=USE_FAKE=true`) — deterministic in-memory data seeded around Sydney (RNG seed 42, 30 points), synthetic classified reports, and a pending-report submit. When `USE_FAKE` is on, Supabase is never initialised (the global `supa` getter must not be touched) — the entire UI runs with **zero network**, the demo-day parachute.

Configuration is entirely compile-time via `--dart-define`; there is no runtime `.env`. Basemap tiles come from **Stadia** *Alidade Smooth* when `STADIA_API_KEY` is set, and fall back to **CARTO** *light_all* (over OpenStreetMap) for keyless local dev.

## Setup

The full, copy-pasteable, zero-to-running walkthrough — CLI install, dashboard toggles, schema push, secrets, smoke tests — lives in **[SETUP.md](SETUP.md)**. The short version:

1. **Supabase** — create a project, `supabase link` + `supabase db push` (migrations 001–004), enable **Anonymous sign-ins**, create the private `report-photos` bucket, and seed `supabase/seed.sql`. (Local instead: `supabase start` → `supabase db reset` applies migrations and the seed automatically.)
2. **Edge function** — `supabase secrets set` the server keys, then `supabase functions deploy classify-report`. The model must support **vision + tool calling**.
3. **Flutter app** — the platform folders are already committed (with camera/location permissions declared), so just `flutter pub get` then `flutter run` with the client `--dart-define`s (or copy `app/run.example.sh` → `app/run.sh`, fill in keys, and run it).

Offline / no-backend demo:

```bash
flutter run --dart-define=USE_FAKE=true
```

### Keys go to two destinations

| Destination | Keys | Set via |
|---|---|---|
| **Server** (edge function) | `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL`, `TAVILY_API_KEY`, `GOOGLE_PLACES_KEY` | `supabase secrets set` |
| **App** (client) | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `STADIA_API_KEY`, `GOOGLE_PLACES_KEY` | `--dart-define` on `flutter run` |

`GOOGLE_PLACES_KEY` appears in both — the server uses it for the verifier's `get_place_accessibility` tool, the app uses it for venue-tagging search. `STADIA_API_KEY` is optional (CARTO fallback without it). The edge function additionally reads `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`, which Supabase injects into the function environment automatically — the service-role key is what lets the function bypass RLS to update reports and locations.

### API keys needed (all free tiers)

| Key | Where | Card? |
|---|---|---|
| Supabase URL + anon key | supabase.com project settings | No |
| Stadia Maps | client.stadiamaps.com | No |
| Tavily | app.tavily.com (1,000 credits/mo) | No |
| Google Places | GCP console → enable **Places API (New)** — ~5k Pro calls/mo | **Yes** (billing required; only Places REST is used, not mobile map SDK loads) |
| OpenAI-compatible AI | your provider of choice (e.g. OpenAI, OpenRouter) | Depends |

### Tests & recovery

Tier rules and geometry parsing have unit tests (no keys required):

```bash
cd supabase/functions/classify-report && deno test classify_test.ts
```

If a report is stuck pending (app killed mid-submit, endpoint down), run the sweep by hand:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/classify-report" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -d '{"sweep": true}'
```

## Demo script

1. **Open the map** — Sydney is seeded with ~30 locations; clusters split apart as you zoom in.
2. **Tap a pin** — the detail sheet shows the photo, tier badge, and AI reasoning; amber pins carry the "venue claims accessible, photos say otherwise" callout.
3. **Submit a live report** (photo of stairs) — watch it flip from *Verifying…* to a tier once the edge function classifies it.
4. **The promotion moment** — *"Rosie's Cafe (demo)"* is seeded with exactly **4** partially-substantiated reports. Submit a **5th** against it: the rollup trigger crosses the threshold, promotes the location, and the pin turns **red** on the next map refresh.
   - *How the 5th report attaches:* untagged reports reuse the nearest existing location within 30 m (`upsert_location`), and the venue's cached "claims accessible" flag makes the new report classify as partial.
   - **Before the demo, edit Rosie's coordinates in `supabase/seed.sql` to the venue you'll be standing in** and re-seed, so your live GPS lands within 30 m of the seeded pin.

## Tech stack

**Client — Flutter** (Dart SDK `>=3.4.0 <4.0.0`)

| Package | Version | Role |
|---|---|---|
| `flutter_riverpod` | ^2.6.1 | state management / DI |
| `supabase_flutter` | ^2.8.0 | Postgres, auth, storage, edge functions |
| `flutter_map` | ^8.1.1 | map rendering |
| `flutter_map_marker_cluster` | ^8.2.2 | animated zoom-based clustering |
| `latlong2` | ^0.9.1 | coordinates |
| `geolocator` | ^13.0.1 | GPS capture |
| `image_picker` | ^1.1.2 | camera / gallery |
| `flutter_image_compress` | ^2.3.0 | client-side photo downscale |
| `cached_network_image` | ^3.4.1 | signed-URL photo display |
| `google_fonts` | ^6.2.1 | Sora + Inter |
| `http` | ^1.2.2 | Google Places REST |
| `uuid` | ^4.4.2 | photo path ids |
| `intl` | ^0.19.0 | date formatting |

**Backend — Supabase**

- Postgres + **PostGIS**, anonymous auth, a private Storage bucket for photos, and a **Deno** edge function (`classify-report`) using `jsr:@supabase/supabase-js@2`.
- **AI**: any OpenAI-compatible `/chat/completions` endpoint with **vision + tool calling** (default `gpt-4o-mini`).
- **Tools the AI can call**: Tavily web search, Google Places (New) `accessibilityOptions.wheelchairAccessibleEntrance`.
- **Tiles**: Stadia Maps free tier, falling back to CARTO / OpenStreetMap for quick local dev (don't ship the fallback).
