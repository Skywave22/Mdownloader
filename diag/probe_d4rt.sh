#!/usr/bin/env bash
# TEMPORARY: can d4rt (the bridge's Dart interpreter) compile against the
# analyzer this app resolves (14.4.0)? Only 7 of its 110 files touch analyzer.
set +e
OUT="$GITHUB_WORKSPACE/diag/results"
mkdir -p "$OUT"
P="$RUNNER_TEMP/d4rt_probe"
rm -rf "$P" && mkdir -p "$P" && cd "$P" || exit 0
git clone --quiet https://github.com/kodjodevf/d4rt.git d4rt || exit 0
cd d4rt
for pair in "6867b56:0.1.7" "c12c44f:0.2.4"; do
  ref="${pair%%:*}"; ver="${pair##*:}"
  git checkout --quiet -f "$ref"
  sed -i -E 's/^(\s*analyzer:).*/\1 14.4.0/' pubspec.yaml
  {
    echo "##### d4rt $ver  (analyzer forced to 14.4.0)"
    dart pub get 2>&1 | tail -15
    echo "----- dart analyze lib"
    dart analyze lib 2>&1
  } > "$OUT/d4rt_${ver}_vs_analyzer14.txt"
  n=$(grep -c " error - " "$OUT/d4rt_${ver}_vs_analyzer14.txt")
  echo "d4rt $ver vs analyzer 14.4.0: $n errors"
  git checkout --quiet -f . 
done
exit 0
