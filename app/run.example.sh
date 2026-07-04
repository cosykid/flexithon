#!/usr/bin/env bash
# Copy to run.sh (gitignored), fill in your keys, then:
#   ./run.sh            # default device (e.g. USB phone)
#   ./run.sh linux      # desktop trial in the phone frame
set -euo pipefail
cd "$(dirname "$0")"

SUPABASE_URL="https://YOUR-REF.supabase.co"
SUPABASE_ANON_KEY="YOUR-ANON-KEY"
STADIA_API_KEY=""        # optional — CARTO tile fallback if empty
GOOGLE_PLACES_KEY=""     # optional — venue tagging disabled if empty

DEVICE_ARG=()
[ $# -ge 1 ] && DEVICE_ARG=(-d "$1")

exec flutter run "${DEVICE_ARG[@]}" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=STADIA_API_KEY="$STADIA_API_KEY" \
  --dart-define=GOOGLE_PLACES_KEY="$GOOGLE_PLACES_KEY"
