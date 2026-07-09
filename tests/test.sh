#!/usr/bin/env bash
# Plain-bash tests for guardian's pure helpers — no extra tools needed.
#   bash tests/test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the script without running main().
# shellcheck source=/dev/null
source "${DIR}/guardian"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

echo "syntax"
bash -n "${DIR}/guardian"      && ok "guardian parses"     || bad "guardian parse"
bash -n "${DIR}/install.sh"    && ok "install.sh parses"   || bad "install.sh parse"

echo "version"
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then ok "VERSION is semver ($VERSION)"; else bad "VERSION not semver ($VERSION)"; fi

echo "parse_duration"
eq "blank"  "$(parse_duration '')"     ""
eq "secs"   "$(parse_duration '90')"   "90"
eq "90s"    "$(parse_duration '90s')"  "90"
eq "30m"    "$(parse_duration '30m')"  "1800"
eq "2h"     "$(parse_duration '2h')"   "7200"
eq "1d"     "$(parse_duration '1d')"   "86400"
if parse_duration 'xx' >/dev/null 2>&1; then bad "bad input rejected"; else ok "bad input rejected"; fi

echo "off_active"
tmp="$(mktemp -d)"
NOW=1000000000   # fixed clock for deterministic tests

f="${tmp}/missing"; if off_active "$f"; then bad "missing -> inactive"; else ok "missing -> inactive"; fi

f="${tmp}/indef"; echo 0 > "$f"
if off_active "$f"; then ok "zero -> active (indefinite)"; else bad "zero -> active"; fi

f="${tmp}/future"; echo $((NOW+100)) > "$f"
if off_active "$f"; then ok "future expiry -> active"; else bad "future expiry -> active"; fi

f="${tmp}/past"; echo $((NOW-100)) > "$f"
if off_active "$f"; then bad "past expiry -> inactive"; else ok "past expiry -> inactive"; fi
[[ -f "$f" ]] && bad "expired file removed" || ok "expired file removed"

echo "off_marker"
eq "all marker"   "$(off_marker all)"   "/etc/guardian/off"
eq "empty marker" "$(off_marker '')"    "/etc/guardian/off"
eq "svc marker"   "$(off_marker mysql)" "/etc/guardian/off.mysql"

echo "human_dur"
eq "seconds" "$(human_dur 45)"    "45s"
eq "minutes" "$(human_dur 90)"    "1m"
eq "hours"   "$(human_dur 7200)"  "2h"
eq "mixed"   "$(human_dur 4830)"  "1h20m"
eq "day"     "$(human_dur 90000)" "1d1h"
eq "zero"    "$(human_dur 0)"     "0s"

echo "off_detail"
f="${tmp}/od_off"; echo 0 > "$f"
eq "indefinite" "$(off_detail "$f")" " (off)"
f="${tmp}/od_none"
eq "not off"    "$(off_detail "$f")" ""

echo "resolve_service"
# 'all' and unknown names are resolvable without systemctl (safe on any box).
eq "all passes through" "$(resolve_service all)" "all"
if resolve_service bogus-xyz >/dev/null 2>&1; then bad "unknown service -> rc 1"; else ok "unknown service -> rc 1"; fi
eq "unknown echoes input" "$(resolve_service bogus-xyz 2>/dev/null)" "bogus-xyz"

rm -rf "$tmp"
echo
echo "passed=${pass} failed=${fail}"
[[ $fail -eq 0 ]]
