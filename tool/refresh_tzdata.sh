#!/bin/sh
# Rebuilds packages/dzcalendar_core/lib/src/zone/tzdata.g.dart from IANA's
# current release (or the one named: tool/refresh_tzdata.sh 2026f), compiled
# by that release's own zic, then checked against that release's own zdump
# (packages/dzcalendar_core/tool/check_tzdata.dart): any difference fails.
# Needs curl, make, a C compiler and shasum.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
release=${1:-latest}
work=$(mktemp -d "${TMPDIR:-/tmp}/dz-tzdata.XXXXXX")
trap 'rm -rf "$work"' EXIT

if [ "$release" = latest ]; then
  data=https://data.iana.org/time-zones/tzdata-latest.tar.gz
  code=https://data.iana.org/time-zones/tzcode-latest.tar.gz
else
  data=https://data.iana.org/time-zones/releases/tzdata$release.tar.gz
  code=https://data.iana.org/time-zones/releases/tzcode$release.tar.gz
fi

mkdir "$work/src" "$work/zoneinfo"
curl -sSfL "$data" -o "$work/tzdata.tar.gz"
curl -sSfL "$code" -o "$work/tzcode.tar.gz"
sums=$(cd "$work" && shasum -a 256 tzdata.tar.gz tzcode.tar.gz | awk '{print $2 " sha256 " $1}' | paste -sd ';' -)
tar -xzf "$work/tzdata.tar.gz" -C "$work/src"
tar -xzf "$work/tzcode.tar.gz" -C "$work/src"
(cd "$work/src" && make -s zic zdump >/dev/null)
# slim: no transitions precomputed to 2037; the POSIX footer carries the rule.
(cd "$work/src" && ./zic -b slim -d "$work/zoneinfo" \
  africa antarctica asia australasia europe northamerica southamerica etcetera backward)

cd "$root"
out=packages/dzcalendar_core/lib/src/zone/tzdata.g.dart
dart run tool/encode_tzdata.dart "$work/src" "$work/zoneinfo" "$out" "$sums"
# As CI checks it.
dart format "$out" >/dev/null
(cd packages/dzcalendar_core && dart run tool/check_tzdata.dart "$work/src/zdump" "$work/zoneinfo")
