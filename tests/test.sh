#!/usr/bin/env bash
# Smoke + safety tests. Runs in CI (macOS) and locally. Exits non-zero on failure.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0
ok() { printf "  ok   %s\n" "$1"; }
no() { printf "  FAIL %s\n" "$1"; fail=1; }

# shellcheck source=/dev/null
source core/lib/util.sh; source core/lib/safety.sh; source core/lib/quarantine.sh

echo "safety guard:"
assert_safe_path "$HOME/Documents"        && no "allowed ~/Documents"     || ok "blocks ~/Documents"
assert_safe_path "$HOME/Desktop/x"        && no "allowed ~/Desktop"       || ok "blocks ~/Desktop"
assert_safe_path "/"                       && no "allowed /"               || ok "blocks /"
assert_safe_path ""                        && no "allowed empty"           || ok "blocks empty path"
assert_safe_path "$HOME/Library/Caches/x" || no "blocked a cache path"     ; [[ $? -eq 0 ]] && ok "allows cache path"

echo "human_kb formatting:"
[[ "$(human_kb 0)" == "0 KB" ]]            && ok "0 KB"            || no "human_kb 0"
[[ "$(human_kb 2048)" == "2 MB" ]]         && ok "2 MB"           || no "human_kb 2048"

echo "quarantine round-trip:"
CLINJ_HOME="$(mktemp -d)"; export CLINJ_HOME
SRC="$HOME/Library/Caches/clinj-citest-$$"; mkdir -p "$SRC"; echo marker > "$SRC/m.txt"
B="$(quarantine_new_batch citest)"
quarantine_move "$SRC" "$B" 1
[[ -e "$SRC" ]] && no "source still present after move" || ok "moved to quarantine"
quarantine_restore "$B" >/dev/null
[[ -f "$SRC/m.txt" && "$(cat "$SRC/m.txt")" == marker ]] && ok "restored intact" || no "restore failed"
rm -rf "$SRC" "$CLINJ_HOME"

echo "discovery + scan run:"
core/clinj.sh scan --all --json >/dev/null 2>&1 && ok "scan --json runs" || no "scan --json failed"
core/clinj.sh profiles >/dev/null 2>&1          && ok "profiles runs"   || no "profiles failed"

[[ $fail -eq 0 ]] && { echo "ALL PASSED"; exit 0; } || { echo "FAILURES"; exit 1; }
