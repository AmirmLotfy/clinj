#!/usr/bin/env bash
# util.sh — shared helpers (sizing, formatting, JSON escaping, logging).
# Sourced by the other libs; defines no side effects on load.

CLINJ_LOG="${CLINJ_LOG:-${HOME}/Library/Logs/clinj.log}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$CLINJ_LOG" 2>/dev/null || true; }

# size of a path in KB (0 if missing). Fast, no follow-symlinks surprises.
size_kb() {
    local p="$1"
    [[ -e "$p" ]] || { echo 0; return; }
    du -sk "$p" 2>/dev/null | awk '{print $1; exit}' || echo 0
}

# human-readable from KB
human_kb() {
    awk -v k="${1:-0}" 'BEGIN{
        split("KB MB GB TB", u, " "); i=1; v=k;
        while (v>=1024 && i<4){v/=1024; i++}
        printf (v>=10 || v==int(v)) ? "%.0f %s" : "%.1f %s", v, u[i]
    }'
}

# JSON-escape a string (minimal: quotes, backslashes, control chars)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/\\t}"; s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# true if a command exists
have() { command -v "$1" >/dev/null 2>&1; }

# emit a catalog record (TSV). Fields must never contain raw tabs/newlines.
# id  category  safe  mode  regen  size_kb  label  path
#   safe ∈ {safe, aggressive, review}   mode ∈ {tree, contents, cmd}
emit_item() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}
