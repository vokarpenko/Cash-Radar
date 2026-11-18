#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo 'Usage: scripts/test_android_notifications.sh DEVICE_ID' >&2
  exit 2
fi
serial=$1
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/app"
if [[ ! -f config/local-supabase.json ]]; then
  echo 'Missing app/config/local-supabase.json; configure local Supabase first.' >&2
  exit 1
fi
adb -s "$serial" get-state >/dev/null
adb -s "$serial" reverse tcp:54321 tcp:54321
flutter build apk --debug --no-pub --dart-define-from-file=config/local-supabase.json
(cd android && ./gradlew :app:assembleDebugAndroidTest --no-daemon)
# Do not use connectedDebugAndroidTest: Gradle can uninstall the target app.
# -r retains app data and notification access; a conflicting signature fails safely.
adb -s "$serial" install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s "$serial" install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
printf '\nEnable Android notification access and collection in CashRadar before continuing.\n'
read -r -p 'Press Enter when ready... '
out=$(mktemp "${TMPDIR:-/tmp}/cashradar-test.XXXXXX")
trap 'rm -f "$out"' EXIT
adb -s "$serial" shell am instrument -w -r -e class com.example.cash_radar.NotificationDeliveryTest com.example.cash_radar.test/androidx.test.runner.AndroidJUnitRunner | tee "$out"
if ! grep -Eq '^OK \([0-9]+ tests?\)' "$out"; then
  echo 'Notification integration test failed; see the output above.' >&2
  exit 1
fi
