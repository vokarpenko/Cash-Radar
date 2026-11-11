#!/usr/bin/env bash
# Cloudflare Pages Git build: only public configuration reaches the Web bundle.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
python3 scripts/validate_web_config.py

flutter_revision='6b182d2c7585eba26d4edce0f97630effd256c33'
flutter_root="${CASH_RADAR_FLUTTER_ROOT:-${TMPDIR:-/tmp}/cash-radar-flutter-3.44.9}"
if [ ! -x "$flutter_root/bin/flutter" ]; then
  git clone --depth 1 --branch 3.44.9 https://github.com/flutter/flutter.git "$flutter_root"
fi
if [ "$(git -C "$flutter_root" rev-parse HEAD)" != "$flutter_revision" ]; then
  printf '%s\n' 'Flutter SDK does not match the pinned revision.' >&2
  exit 1
fi

export FLUTTER_SUPPRESS_ANALYTICS=true
export DASH__SUPPRESS_ANALYTICS=true
cd app
"$flutter_root/bin/flutter" --version
"$flutter_root/bin/flutter" pub get --enforce-lockfile
"$flutter_root/bin/flutter" build web --release --no-pub \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
