#!/usr/bin/env bash
# Runs the NetworkChecker integration test on an Android emulator, switching its Wi-Fi and data off and on
# when the test asks (a Flutter app can't switch them itself). Usage: tool/network_checker_device_test.sh [device-id]
set -euo pipefail

device="${1:-emulator-5554}"
adb=(adb -s "$device")
radios() { "${adb[@]}" shell svc wifi "$1"; "${adb[@]}" shell svc data "$1"; }
trap 'radios enable' EXIT

cd "$(dirname "$0")/../example"
flutter test integration_test/network_checker_test.dart -d "$device" \
  --dart-define=SINEW_SWITCH_RADIOS=true 2>&1 |
  while IFS= read -r line; do
    printf '%s\n' "$line"
    case "$line" in
      *SINEW_RADIOS_OFF*) radios disable ;;
      *SINEW_RADIOS_ON*) radios enable ;;
    esac
  done
exit "${PIPESTATUS[0]}"
