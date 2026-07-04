#!/usr/bin/env bash
# Copy to run.sh (gitignored), fill in your keys, then:
#   ./run.sh            # default device (e.g. USB phone)
#   ./run.sh chrome     # browser trial in the phone frame
# Google Maps keys per platform:
#   Android — MAPS_API_KEY below (exported for gradle)
#   iOS     — GMSApiKey in ios/Runner/Info.plist
#   Web     — GOOGLE_MAPS_WEB_KEY below (injected at startup)
set -euo pipefail
cd "$(dirname "$0")"

SUPABASE_URL="https://YOUR-REF.supabase.co"
SUPABASE_ANON_KEY="YOUR-ANON-KEY"
GOOGLE_PLACES_KEY=""     # optional — venue tagging disabled if empty
GOOGLE_MAPS_WEB_KEY=""   # Maps JavaScript API key (web builds)
export MAPS_API_KEY=""   # Android Maps SDK key (picked up by gradle)

DEVICE_ARG=()
[ $# -ge 1 ] && DEVICE_ARG=(-d "$1")

exec flutter run "${DEVICE_ARG[@]}" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_PLACES_KEY="$GOOGLE_PLACES_KEY" \
  --dart-define=GOOGLE_MAPS_WEB_KEY="$GOOGLE_MAPS_WEB_KEY"
