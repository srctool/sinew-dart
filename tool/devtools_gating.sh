#!/usr/bin/env bash
# The devtools gating proof (see the docs: DevTools, Gating): builds the example for one target, mode and flavor, then
# searches the compiled output for sinew_devtools_ui's marker string. A production build must not contain it (devtools
# code would have survived tree-shaking); a staging build must, which shows the search can see it.
# Usage: tool/devtools_gating.sh <apk|ios|web|wasm> <release|profile> <production|staging>
set -euo pipefail

target="${1:?usage: $0 <apk|ios|web|wasm> <release|profile> <production|staging>}"
mode="${2:?usage: $0 <target> <release|profile> <production|staging>}"
flavor="${3:?usage: $0 <target> <mode> <production|staging>}"
cd "$(dirname "$0")/../example"

# The marker's value, read from the source so the two can't drift apart.
marker="$(sed -n "s/^const devToolsMarker = '\(.*\)';$/\1/p" ../packages/sinew_devtools_ui/lib/src/sinew_dev_tools.dart)"
[[ -n "$marker" ]] || { echo "devToolsMarker not found in sinew_devtools_ui" >&2; exit 2; }

define="--dart-define=SINEW_FLAVOR=$flavor"
case "$target" in
  apk)
    flutter build apk "--$mode" --target-platform android-arm64 "$define"
    outputs=(build/app/outputs/flutter-apk/app-"$mode".apk) ;;   # libapp.so, searched inside the APK below
  ios)
    flutter build ios "--$mode" --no-codesign "$define"
    outputs=(build/ios/iphoneos/Runner.app/Frameworks/App.framework/App) ;;
  web)
    flutter build web "--$mode" "$define"
    outputs=(build/web/main.dart.js) ;;
  wasm)
    flutter build web --wasm "--$mode" "$define"
    outputs=(build/web/main.dart.wasm) ;;
  *) echo "unknown target: $target" >&2; exit 2 ;;
esac

# Counts the marker in a file, or in each libapp.so inside an APK.
count() {
  if [[ "$1" == *.apk ]]; then
    local libs; libs="$(unzip -Z1 "$1" 'lib/*/libapp.so')"
    [[ -n "$libs" ]] || { echo "no libapp.so in $1" >&2; exit 2; }
    unzip -p "$1" $libs | LC_ALL=C grep -c -a -o -F "$marker" || true
  else
    LC_ALL=C grep -c -a -o -F "$marker" "$1" || true
  fi
}

found=0
for output in "${outputs[@]}"; do
  [[ -f "$output" ]] || { echo "missing build output: $output" >&2; exit 2; }
  n="$(count "$output")"
  echo "$output: $n marker(s)"
  found=$((found + n))
done

label="$target $mode, SINEW_FLAVOR=$flavor"
if [[ "$flavor" == production && "$found" -ne 0 ]]; then
  echo "FAIL: the $label build contains devtools code (marker \"$marker\" found)" >&2; exit 1
elif [[ "$flavor" != production && "$found" -eq 0 ]]; then
  echo "FAIL: the $label build has no devtools marker; the search can't see devtools code" >&2; exit 1
fi
echo "OK: $label"
