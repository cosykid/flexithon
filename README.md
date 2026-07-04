# AccessMap

Crowdsourced accessibility-barrier reporting for wheelchair users and people with
walking-centric disabilities. Report an inaccessible place with a photo; an AI
pipeline verifies the photo, investigates the venue's public accessibility claims
online, and classifies the report. Verified reports appear as clustered pins on a map.

## Substantiation tiers

| Tier | Meaning | On map |
|---|---|---|
| Unsubstantiated | Description only — no confirming photo, no online corroboration | No |
| Partially substantiated (amber) | Photo confirms the barrier, but the venue claims accessibility online | Yes |
| Substantiated (red) | Photo confirms the barrier and the venue claims nothing / inaccessibility — or ≥5 partial reports at one location (auto-promoted) | Yes |

The AI reports facts (what the photo shows, what the venue claims); the tier rules
are deterministic code (`supabase/functions/classify-report/classify.ts` + the
rollup trigger in `supabase/migrations/004_trigger.sql`).

## Stack

- **Flutter** — `google_maps_flutter` (custom canvas-drawn pins + zoom-based clustering), Riverpod, `supabase_flutter`
- **Supabase** — Postgres + PostGIS, anonymous auth, Storage (photos), Edge Function (Deno) for verification
- **AI** — any OpenAI-compatible `/chat/completions` endpoint with vision + tool calling
- **Tools the AI can call** — Tavily web search, Google Places (New) `accessibilityOptions.wheelchairAccessibleEntrance`
- **Maps** — Google Maps Platform: Maps SDK (Android/iOS/JS) with a Kerb-styled basemap, Places API for venue tagging

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

```bash
supabase secrets set \
  AI_BASE_URL=https://api.openai.com/v1 \
  AI_API_KEY=sk-... \
  AI_MODEL=gpt-4o-mini \
  TAVILY_API_KEY=tvly-... \
  GOOGLE_PLACES_KEY=AIza...
supabase functions deploy classify-report
```

The model must support **vision and tool calling**. Test both on day 1:
`supabase functions serve classify-report` and curl it with a seeded report id.

Unit tests for the tier rules and geometry parsing (no keys needed):

```bash
cd supabase/functions/classify-report && deno test classify_test.ts
```

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
