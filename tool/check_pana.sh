#!/usr/bin/env bash
# Scores packages with `pana`, pub.dev's own scorer, and fails unless each gets every point.
# pana needs `cwebp` (brew install webp, apt install webp) to process screenshots; without it a package that lists
# screenshots scores 10 points short, which is the tool missing, not the package.
# Usage: tool/check_pana.sh --all    every package (pana's pub get needs each Sinew dependency on pub.dev, so this works
#                                    from 1.0.0 on; CI uses it)
#        tool/check_pana.sh          only the packages with no Sinew dependency, for a checkout whose dependencies are
#                                    not on pub.dev yet
set -euo pipefail

cd "$(dirname "$0")/.."
dart pub global activate pana > /dev/null

failed=0
for dir in packages/*/; do
  name="$(basename "$dir")"
  if [[ "${1:-}" != "--all" ]] && sed -n '/^dependencies:/,/^dev_dependencies:/p' "$dir/pubspec.yaml" | grep -q '^  sinew_'; then
    continue
  fi
  report="$(mktemp)"
  log="$(mktemp)"
  # pana streams its progress to stderr as JSON lines: keep it for a failure, and show only the verdict otherwise.
  if ! (cd "$dir" && dart pub global run pana --no-warning --json --source path . > "$report" 2> "$log"); then
    echo "$name: pana failed to run"
    tail -n 5 "$log"
    failed=1
    continue
  fi
  python3 - "$name" "$report" <<'PY' || failed=1
import json, sys
name, path = sys.argv[1:]
data = json.load(open(path))
scores = data['scores']
print(f"{name}: {scores['grantedPoints']} of {scores['maxPoints']}")
for section in data['report']['sections']:
    if section['grantedPoints'] < section['maxPoints']:
        print(f"  {section['grantedPoints']}/{section['maxPoints']} {section['title']}: {section['summary'].strip().splitlines()[0]}")
sys.exit(0 if scores['grantedPoints'] == scores['maxPoints'] else 1)
PY
done
exit "$failed"
