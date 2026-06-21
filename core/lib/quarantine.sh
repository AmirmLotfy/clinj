#!/usr/bin/env bash
# quarantine.sh — two disposal modes:
#   dispose()         hard-delete (for items classified "safe"; frees space now)
#   quarantine_move() move to a restorable batch (for "review"/uncertain items)
# Restore + sweep let users recover or finally reclaim quarantined items.

CLINJ_HOME="${CLINJ_HOME:-${HOME}/.clinj}"
QUARANTINE_ROOT="${CLINJ_HOME}/quarantine"

# Hard-delete a path (must pass safety + not be dry-run).
dispose() {
    local p="$1"
    assert_safe_path "$p" || return 1
    [[ "${CLINJ_DRY_RUN:-false}" == true ]] && return 0
    rm -rf "${p:?}" 2>/dev/null || true
}

# Begin a batch; echoes the batch dir path.
quarantine_new_batch() {
    local ts="$1"
    local dir="${QUARANTINE_ROOT}/${ts}"
    [[ "${CLINJ_DRY_RUN:-false}" == true ]] && { echo "$dir"; return 0; }
    mkdir -p "$dir"
    : > "${dir}/manifest.tsv"
    echo "$dir"
}

# Move a path into a batch, recording its origin for restore.
# args: <path> <batch_dir> <index>
quarantine_move() {
    local p="$1" batch="$2" idx="$3"
    assert_safe_path "$p" || return 1
    [[ -e "$p" ]] || return 0
    [[ "${CLINJ_DRY_RUN:-false}" == true ]] && return 0
    local base dest
    base="$(basename "$p")"
    dest="${batch}/${idx}__${base}"
    if mv "$p" "$dest" 2>/dev/null; then
        printf '%s\t%s\n' "$dest" "$p" >> "${batch}/manifest.tsv"
    fi
}

# Latest batch dir (empty string if none).
quarantine_latest() {
    ls -1dt "${QUARANTINE_ROOT}"/*/ 2>/dev/null | head -1
}

# Restore a batch (default: latest). Moves items back to their origins.
quarantine_restore() {
    local batch="${1:-$(quarantine_latest)}"
    [[ -n "$batch" && -f "${batch%/}/manifest.tsv" ]] || { echo "Nothing to restore."; return 1; }
    local dest orig restored=0
    while IFS=$'\t' read -r dest orig; do
        [[ -e "$dest" ]] || continue
        mkdir -p "$(dirname "$orig")" 2>/dev/null
        mv "$dest" "$orig" 2>/dev/null && restored=$((restored+1))
    done < "${batch%/}/manifest.tsv"
    rm -rf "$batch"
    echo "Restored ${restored} item(s) from $(basename "${batch%/}")."
}

# Permanently empty quarantine batches older than N days (default 7).
quarantine_sweep() {
    local days="${1:-7}" freed=0 b
    [[ -d "$QUARANTINE_ROOT" ]] || { echo "Quarantine empty."; return 0; }
    while IFS= read -r b; do
        [[ -n "$b" ]] || continue
        freed=$((freed + $(size_kb "$b")))
        rm -rf "$b"
    done < <(find "$QUARANTINE_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$days" 2>/dev/null)
    echo "Swept quarantine (>${days}d): freed ~$(human_kb "$freed")."
}
