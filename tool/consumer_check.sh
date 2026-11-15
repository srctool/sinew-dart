#!/usr/bin/env bash
# Proves a release from the consumer's side: the example app, copied out of the workspace so that every Sinew package
# comes from pub.dev, resolves all 14 packages at one version and runs its list screen.
# Usage: tool/consumer_check.sh [version] [resolve|test <device>]
#   version      the release to check (default: the workspace's version, from sinew_models)
#   resolve      only `flutter pub get` and the version check (works anywhere)
#   test DEVICE  also runs integration_test/order_list_test.dart on DEVICE (e.g. linux, under xvfb-run in CI)
# Nothing in the repository changes: the app is copied to a temporary directory first.
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
version="${1:-$(sed -n 's/^version:[[:space:]]*//p' packages/sinew_models/pubspec.yaml | tr -d '[:space:]')}"
mode="${2:-resolve}"
device="${3:-}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/app"
tar -C example --exclude=build --exclude=.dart_tool --exclude=pubspec.lock -cf - . | tar -C "$work/app" -xf -
cd "$work/app"

# Out of the workspace: no `resolution: workspace`, and every Sinew package from pub.dev at exactly the release version.
python3 - "$version" <<'PY'
import re, sys
version = sys.argv[1]
text = open('pubspec.yaml').read()
text = re.sub(r'(?m)^resolution:.*\n', '', text)
text = re.sub(r'(?m)^(\s+sinew_[a-z_]+:)\s*\^[0-9][0-9.]*', rf'\1 {version}', text)
open('pubspec.yaml', 'w').write(text)
PY
# The example doesn't use these two, but a consumer can: the check covers every package.
flutter pub add "sinew_riverpod_providers:$version" > /dev/null
flutter pub add --dev "sinew_testing:$version" > /dev/null

packages=(camouflage devtools devtools_ui exception l10n models network paging presentation riverpod riverpod_providers security storage testing)
expected="${#packages[@]}"
found=0
for package in "${packages[@]}"; do
  resolved="$(python3 - "sinew_$package" <<'PY'
import re, sys
lock = open('pubspec.lock').read()
m = re.search(rf'(?m)^  {sys.argv[1]}:\n(?:    .*\n)*?    version: "([^"]+)"', lock)
print(m.group(1) if m else '')
PY
)"
  if [[ "$resolved" != "$version" ]]; then
    echo "sinew_$package resolved to '${resolved:-nothing}', not $version"
    exit 1
  fi
  found=$((found + 1))
done
echo "A fresh app resolves $found of $expected Sinew packages at $version from pub.dev."

if [[ "$mode" == "test" ]]; then
  flutter test integration_test/order_list_test.dart -d "$device"
fi
