# AccessMap — Go-Live Setup

Every command needed to go from zero to running app. Run everything from the
repo root unless stated otherwise.

## Where each key goes (the two destinations)

| Destination | Keys | Set via |
|---|---|---|
| **Server** (edge function) | `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL`, `TAVILY_API_KEY`, `GOOGLE_PLACES_KEY` | `supabase secrets set` (§5) |
| **App** (client) | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_PLACES_KEY`, `GOOGLE_MAPS_WEB_KEY` (web builds) | `--dart-define` on `flutter run` (§7) |
| **App** (platform config) | Google Maps SDK key | Android: `MAPS_API_KEY` env var / gradle property · iOS: `GMSApiKey` in `ios/Runner/Info.plist` |

`GOOGLE_PLACES_KEY` appears in both: server uses it for the verifier's
`get_place_accessibility` tool, app uses it for venue-tagging search.
The Maps SDK key can be the same GCP key with the Maps SDKs enabled.

---

## 0. Install Supabase CLI (one-time)

macOS:

```bash
brew install supabase/tap/supabase
```

WSL / Debian-based Linux:

```bash
curl -L https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.deb -o /tmp/supabase.deb
sudo dpkg -i /tmp/supabase.deb
```

Either platform, no install (works anywhere Node is): prefix every
`supabase` command below with `npx`, e.g. `npx supabase login`.

```bash
supabase --version
```

## 1. Create the Supabase project

- [supabase.com](https://supabase.com) → New project, region `ap-southeast-2`
- Save the **database password**
- Project Settings → API: copy **Project URL** and **anon key**

## 2. Dashboard toggles

- Authentication → Sign In / Up → **Anonymous sign-ins: ON**
- Storage → New bucket → `report-photos`, **Public: OFF**

## 3. Push schema + seed

```bash
supabase login
supabase link --project-ref <ref>       # <ref> from the project URL
supabase db push                        # all migrations in supabase/migrations/
```

If push prints `storage.objects policies skipped`: dashboard → Storage →
`report-photos` → Policies → add authenticated INSERT (own folder) +
authenticated SELECT.

Seed: dashboard **SQL Editor** → paste `supabase/seed.sql` → Run.
Check: `select count(*) from reports;` → ~45.

## 4. Collect keys (all free tiers)

| Key | Where | Card? |
|---|---|---|
| Tavily | app.tavily.com → API key | no |
| Google Maps + Places | console.cloud.google.com → enable billing → enable **Places API (New)**, **Maps SDK for Android**, **Maps SDK for iOS**, **Maps JavaScript API** → Credentials → API key | **yes** |
| AI endpoint | any OpenAI-compatible with **vision + tool calling** (e.g. `gpt-4o-mini`) | varies |

## 5. Server secrets + deploy edge function

```bash
supabase secrets set \
  AI_BASE_URL=https://api.openai.com/v1 \
  AI_API_KEY=sk-YOUR-OPENAI-KEY \
  AI_MODEL=gpt-4o-mini \
  TAVILY_API_KEY=tvly-YOUR-TAVILY-KEY \
  GOOGLE_PLACES_KEY=AIzaYOUR-PLACES-KEY

supabase secrets list                   # confirm all 5
supabase functions deploy classify-report
```

OpenRouter instead of OpenAI: `AI_BASE_URL=https://openrouter.ai/api/v1`,
`AI_MODEL=openai/gpt-4o-mini`, `AI_API_KEY=sk-or-...`.

NanoGPT: `AI_BASE_URL=https://nano-gpt.com/api/v1` (the `/api/v1` suffix is
required — the bare domain serves HTML 404s), `AI_MODEL=alibaba/qwen3.6-27b`
(vision + tool calling, subscription-included), `AI_API_KEY=sk-nano-...`.

## 6. Smoke test the pipeline

Create a pending report (SQL Editor):

```sql
insert into reports (user_id, location_id, geog, description)
select '00000000-0000-0000-0000-000000000001', id, geog,
       'Test: entrance has stairs and no ramp.'
from locations limit 1
returning id;
```

Classify it (service role key: Project Settings → API):

```bash
curl -X POST "https://<ref>.supabase.co/functions/v1/classify-report" \
  -H "Authorization: Bearer <service-role-key>" \
  -H "Content-Type: application/json" \
  -d '{"report_id": "<id-from-above>"}'
```

Expect `{"ok":true,"detail":"classified: unsubstantiated"}` (no photo →
correct). Errors: dashboard → Edge Functions → classify-report → Logs.

Stuck pending reports (app killed mid-submit, endpoint down):

```bash
curl -X POST "https://<ref>.supabase.co/functions/v1/classify-report" \
  -H "Authorization: Bearer <service-role-key>" \
  -H "Content-Type: application/json" \
  -d '{"sweep": true}'
```

## 7. Run the app

Copy the template, fill in keys, run:

```bash
cp app/run.example.sh app/run.sh        # run.sh is gitignored
# edit app/run.sh with your keys
./app/run.sh chrome                     # browser trial in the phone frame
./app/run.sh                            # default device (phone via USB)
```

Or by hand:

```bash
cd app
MAPS_API_KEY=<android-maps-key> flutter run \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=GOOGLE_PLACES_KEY=<places-key> \
  --dart-define=GOOGLE_MAPS_WEB_KEY=<web-maps-key>
```

`GOOGLE_MAPS_WEB_KEY` is injected at startup on web builds (needs "Maps
JavaScript API" enabled); iOS needs `GMSApiKey` in `ios/Runner/Info.plist`.
Native desktop targets have no Google Maps runtime — use Chrome for trials.

No backend? Demo parachute: `flutter run -d chrome --dart-define=USE_FAKE=true`

## 8. Demo prep

- Edit Rosie's Cafe coords in `supabase/seed.sql` to the demo venue, re-seed —
  live 5th report must land within 30 m to auto-promote the pin to red.
- Edge function unit tests (no keys needed):
  `cd supabase/functions/classify-report && deno test classify_test.ts`
