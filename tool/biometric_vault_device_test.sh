#!/usr/bin/env bash
# Runs the BiometricVault integration test, answering the prompts the test asks for (lines `SINEW_BIOMETRIC …`).
#   TOUCH <n>   Android: touch the sensor with finger n once the prompt shows (1 is enrolled, 2 isn't)
#   BACK        Android: press Back once the prompt shows, dismissing it
#   ENROLL      Android: enroll another finger in Settings (only with --enroll); restored to one finger after
#   FACE match  iOS simulator: a matching face
# On an Android emulator (a PIN of 1111 and finger 1 enrolled) the script answers itself; on a phone (--device) it tells
# you what to do, and never touches the lock screen or your fingerprints. An iOS simulator (its UDID as the device) gets
# Face ID enrolled and matched through notifyutil.
# One-time emulator setup: `adb shell locksettings set-pin 1111`, then enroll finger 1 (Settings > Security >
# Fingerprint, touching with `adb emu finger touch 1`). The Settings taps assume a 1080x2400 screen (Medium Phone).
# Usage: tool/biometric_vault_device_test.sh [--enroll] [--device] [device-id] [flutter test arguments…]
#   e.g. --plain-name 'enrolling another finger'
set -euo pipefail

enroll=false
phone=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --enroll) enroll=true ;;
    --device) phone=true ;;
  esac
  shift
done
device="${1:-emulator-5554}"
shift || true
cd "$(dirname "$0")/../example"

say() { printf '\n>>> %s\n' "$*"; }

if [[ "$device" =~ ^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$ ]]; then
  ios=true
else
  ios=false
fi

# --- iOS simulator ---------------------------------------------------------------------------------------------------
notify() { xcrun simctl spawn "$device" notifyutil "$@" >/dev/null; }
enrolled() { notify -s com.apple.BiometricKit.enrollmentChanged "$1"; notify -p com.apple.BiometricKit.enrollmentChanged; }

# --- Android ---------------------------------------------------------------------------------------------------------
adb=(adb -s "$device")
touch_finger() { "${adb[@]}" emu finger touch "$1" >/dev/null; }

# The focused prompt window's id (Window{<id> …}), empty when no prompt has focus.
prompt_window() { "${adb[@]}" shell dumpsys window | sed -n 's/.*mCurrentFocus=Window{\([0-9a-f]*\) .*BiometricPrompt.*/\1/p' | head -1; }

# Prompts come one after another, and a closing one keeps focus for a moment: each action waits (up to 60 s) for a
# prompt window other than the last one answered. A touch before a prompt shows is lost.
answered=""

await_new_prompt() {
  local window=""
  for _ in $(seq 1 120); do
    window="$(prompt_window)"
    [[ -n "$window" && "$window" != "$answered" ]] && break
    sleep 0.5
  done
  sleep 0.5
  printf '%s' "$window"
}

# An enrolled finger: touch until this prompt is gone, then count it answered.
answer_with_finger() {
  local window
  window="$(await_new_prompt)"
  for _ in $(seq 1 5); do
    touch_finger "$1"
    sleep 1.5
    [[ "$(prompt_window)" == "$window" ]] || break
  done
  answered="$window"
}

# A finger that isn't enrolled: the prompt stays up, still unanswered.
touch_unknown_finger() {
  await_new_prompt >/dev/null
  touch_finger "$1"
  sleep 1
}

answer_with_back() {
  answered="$(await_new_prompt)"
  "${adb[@]}" shell input keyevent 4
  sleep 1
}

# grep reads everything: with -q it would stop at the match, and pipefail would count dumpsys's broken pipe as a miss.
focused() { "${adb[@]}" shell dumpsys window | grep -E "mCurrentFocus=.*($1)" >/dev/null; }

# Waits up to $2 seconds (default 60) for a window whose name matches $1 (an extended regex).
await_focus() { for _ in $(seq 1 "${2:-60}"); do focused "$1" && return 0; sleep 1; done; return 1; }

prints() { "${adb[@]}" shell dumpsys fingerprint | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2; }

# Fingerprint enrollment in Settings: confirm the PIN, accept the intro, touch until the print count goes up, then
# come back to the app.
enroll_finger() {
  local before
  before="$(prints)"
  # A Settings task left in the background would be brought to the front instead of a new enrollment.
  "${adb[@]}" shell am force-stop com.android.settings
  "${adb[@]}" shell am start -a android.settings.FINGERPRINT_ENROLL >/dev/null
  # Under a running test the emulator can take a minute to show each screen.
  await_focus ConfirmLockPassword 180
  "${adb[@]}" shell input text 1111
  "${adb[@]}" shell input keyevent 66
  await_focus FingerprintEnrollment 180
  # "I agree" first scrolls the terms to the end, then accepts; a touch before the sensor screen shows is lost.
  for _ in $(seq 1 30); do
    focused 'FingerprintEnrollFindSensor|FingerprintEnrollEnrolling' && break
    "${adb[@]}" shell input tap 912 2242
    sleep 4
  done
  sleep 1
  for _ in $(seq 1 40); do
    touch_finger "$1"
    sleep 1.5
    [[ "$(prints)" -gt "$before" ]] && break
  done
  # Back to the test app; after the run (restoring the emulator) it's uninstalled, which is fine.
  "${adb[@]}" shell am start -n com.srctool.sinew.sinew_example/.MainActivity >/dev/null 2>&1 || true
}

# Back to one enrolled finger: removing the PIN deletes every print, then the PIN and finger 1 are set up again.
restore_single_finger() {
  "${adb[@]}" shell locksettings clear --old 1111 >/dev/null
  "${adb[@]}" shell locksettings set-pin 1111 >/dev/null
  enroll_finger 1
}

answer() {
  local action="$1"
  if [[ "$ios" == true ]]; then
    case "$action" in
      "FACE match") sleep 1.5; notify -p com.apple.BiometricKit_Sim.pearl.match ;;
    esac
  elif [[ "$phone" == true ]]; then
    # A person reacts to the prompt itself, and OEM prompt windows aren't all named BiometricPrompt.
    case "$action" in
      "TOUCH 1") say "When the prompt shows, touch the sensor with an ENROLLED finger" ;;
      "TOUCH "*) say "When the prompt shows, touch ONCE with a finger that is NOT enrolled, then wait"; sleep 10 ;;
      BACK) "${adb[@]}" shell input keyevent 4 ;;
      ENROLL) say "Now add ANOTHER fingerprint in Settings (you have 3 minutes), then come back to the app. You can delete it after the run." ;;
    esac
  else
    case "$action" in
      "TOUCH 1") answer_with_finger 1 ;;
      "TOUCH "*) touch_unknown_finger "${action#TOUCH }" ;;
      BACK) answer_with_back ;;
      ENROLL) enroll_finger 2 ;;
    esac
  fi
}

if [[ "$ios" == true ]]; then
  enrolled 1
  trap 'enrolled 1' EXIT
elif [[ "$phone" == true ]]; then
  say "Keep the phone unlocked with its screen on until the run ends."
else
  # The PIN turns on the lock screen: keep the screen on and unlocked, or the prompt can't show. "Stay on" only holds
  # while charging, so the emulator is told it's on AC, and the screen timeout is made as long as possible.
  "${adb[@]}" shell dumpsys battery set ac 1
  "${adb[@]}" shell settings put system screen_off_timeout 2147483647
  "${adb[@]}" shell svc power stayon true
  "${adb[@]}" shell input keyevent 224      # wake up
  "${adb[@]}" shell wm dismiss-keyguard
  sleep 1
  if "${adb[@]}" shell dumpsys window | grep -E "mDreamingLockscreen=true|isKeyguardShowing=true|mShowingLockscreen=true" >/dev/null; then
    "${adb[@]}" shell input text 1111
    "${adb[@]}" shell input keyevent 66
    sleep 1
  fi
fi

status=0
flutter test integration_test/biometric_vault_test.dart -d "$device" \
  --dart-define=SINEW_BIOMETRICS=true --dart-define=SINEW_ENROLL="$enroll" "$@" 2>&1 |
  while IFS= read -r line; do
    line="${line%$'\r'}"
    printf '%s\n' "$line"
    case "$line" in
      *"SINEW_BIOMETRIC "*) answer "${line##*SINEW_BIOMETRIC }" </dev/null ;;   # adb would read the test's output
    esac
  done || status=$?

if [[ "$ios" == false && "$phone" == false && "$enroll" == true && "$(prints)" != "1" ]]; then restore_single_finger; fi
exit "$status"
