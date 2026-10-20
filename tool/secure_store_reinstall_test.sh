#!/usr/bin/env bash
# Shows that a reinstall starts with an empty SecureStore: stores a secret, uninstalls and reinstalls the example app,
# then finds no secret. On iOS the cipher's key survives in the Keychain, but the values went with the app.
# Usage: tool/secure_store_reinstall_test.sh <device-id>   (an Android device or emulator, or an iOS simulator's UDID)
set -euo pipefail

device="${1:?usage: $0 <device-id>}"
cd "$(dirname "$0")/../example"

phase() {
  flutter test integration_test/secure_store_test.dart -d "$device" --dart-define=SINEW_REINSTALL_PHASE="$1"
}

phase before
# flutter test may already have uninstalled the app (it does on Android); either way it's gone before the next phase.
if [[ "$device" =~ ^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$ ]]; then
  xcrun simctl uninstall "$device" com.srctool.sinew.sinewExample || true
else
  adb -s "$device" uninstall com.srctool.sinew.sinew_example >/dev/null 2>&1 || true
fi
phase after
