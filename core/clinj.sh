#!/usr/bin/env bash
# clinj — an honest, open-source disk reclaimer for macOS.
# Dynamic discovery + classification + recoverable quarantine + profiles.
#
#   clinj scan    [--profile P] [--all] [--json]
#   clinj clean   [--profile P] [--dry-run] [--aggressive] [--include-review] [--category C]
#   clinj restore [batch]            # undo the last quarantined clean
#   clinj sweep   [--older-than N]   # permanently empty quarantine (>N days, default 7)
#   clinj profiles                   # list profiles
#   clinj ram                        # free inactive memory (purge; needs privilege)
#
# Cleans caches/build-artifacts/temp only. Never your documents, code, or settings.
set -uo pipefail

CLINJ_VERSION="2.0.0-dev"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SELF_DIR}/lib"
PROFILES_DIR="${SELF_DIR}/profiles"
# shellcheck source=/dev/null
source "${LIB}/util.sh"; source "${LIB}/safety.sh"; source "${LIB}/quarantine.sh"
source "${LIB}/rules.sh"; source "${LIB}/discover.sh"

# ── options ───────────────────────────────────────────────────────────────────
CMD="${1:-scan}"; shift || true
PROFILE="general"; JSON=false; ALL=false; CLINJ_DRY_RUN=false
AGG_OVERRIDE=""; INCLUDE_REVIEW=false; ONLY_CAT=""; SWEEP_DAYS=7; ONLY_IDS=""; STREAM=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --json) JSON=true; shift ;;
        --stream) STREAM=true; shift ;;
        --all) ALL=true; shift ;;
        --dry-run) CLINJ_DRY_RUN=true; shift ;;
        --aggressive) AGG_OVERRIDE="yes"; shift ;;
        --include-review) INCLUDE_REVIEW=true; shift ;;
        --category) ONLY_CAT="$2"; shift 2 ;;
        --ids) ONLY_IDS=" ${2//,/ } "; shift 2 ;;
        --older-than) SWEEP_DAYS="$2"; shift 2 ;;
        *) shift ;;
    esac
done
export CLINJ_DRY_RUN

load_profile() {
    local f="${PROFILES_DIR}/${PROFILE}.conf"
    [[ -f "$f" ]] || { echo "Unknown profile: ${PROFILE} (try: clinj profiles)" >&2; exit 1; }
    # shellcheck source=/dev/null
    source "$f"
    [[ -n "$AGG_OVERRIDE" ]] && AGGRESSIVE="$AGG_OVERRIDE"
}

# include test for an item given profile + flags
included() { # category safe
    local cat="$1" safe="$2"
    if [[ "$ALL" == true ]]; then return 0; fi
    if [[ -n "$ONLY_CAT" ]]; then [[ "$cat" == "$ONLY_CAT" ]] || return 1
    else case " $CATEGORIES " in *" $cat "*) ;; *) return 1 ;; esac; fi
    case "$safe" in
        safe) return 0 ;;
        aggressive) [[ "${AGGRESSIVE:-no}" == "yes" ]] && return 0 || return 1 ;;
        review) [[ "$INCLUDE_REVIEW" == true ]] && return 0 || return 1 ;;
    esac
    return 1
}

build_catalog() { CATALOG="$(clinj_discover)"; }

# ── scan ──────────────────────────────────────────────────────────────────────
cmd_scan() {
    # streaming mode: emit raw TSV item-by-item (for the GUI's live scan view)
    if [[ "$STREAM" == true ]]; then clinj_discover; return; fi
    load_profile; build_catalog
    if [[ "$JSON" == true ]]; then
        printf '['; local first=1 id cat safe mode regen kb label path
        while IFS=$'\t' read -r id cat safe mode regen kb label path; do
            [[ -z "$id" ]] && continue
            included "$cat" "$safe" || [[ "$ALL" == true ]] || continue
            [[ $first -eq 1 ]] && first=0 || printf ','
            printf '{"id":"%s","category":"%s","safe":"%s","mode":"%s","size_kb":%s,"regen":"%s","label":"%s","path":"%s"}' \
                "$(json_escape "$id")" "$cat" "$safe" "$mode" "$kb" "$(json_escape "$regen")" "$(json_escape "$label")" "$(json_escape "$path")"
        done <<< "$CATALOG"
        printf ']\n'; return
    fi
    local alltag=""; [[ "$ALL" == true ]] && alltag="  (all items)"
    echo "🧼 Clinj scan — profile: ${PROFILE_NAME}${alltag}"
    echo "   ${PROFILE_DESC}"; echo ""
    local cur="" total=0 rev_kb=0 rev_n=0 cat_kb=0
    # sort by category then size desc
    local sorted; sorted="$(printf '%s\n' "$CATALOG" | sort -t$'\t' -k2,2 -k6,6nr)"
    local id cat safe mode regen kb label path
    while IFS=$'\t' read -r id cat safe mode regen kb label path; do
        [[ -z "$id" ]] && continue
        if [[ "$safe" == review ]]; then rev_kb=$((rev_kb+kb)); rev_n=$((rev_n+1)); fi
        included "$cat" "$safe" || continue
        if [[ "$cat" != "$cur" ]]; then
            [[ -n "$cur" ]] && printf "    %s\n" "── subtotal: $(human_kb "$cat_kb") ──"
            cur="$cat"; cat_kb=0; printf "\n  ▸ %s\n" "$cat"
        fi
        local tag=""; [[ "$safe" == aggressive ]] && tag=" ⚡"; [[ "$safe" == review ]] && tag=" ❓"
        printf "    %8s  %s%s\n" "$(human_kb "$kb")" "$label" "$tag"
        cat_kb=$((cat_kb+kb)); total=$((total+kb))
    done <<< "$sorted"
    [[ -n "$cur" ]] && printf "    %s\n" "── subtotal: $(human_kb "$cat_kb") ──"
    echo ""; echo "  ════════════════════════════════════"
    printf "  Reclaimable now (this profile): %s\n" "$(human_kb "$total")"
    [[ "$INCLUDE_REVIEW" == false && "$rev_n" -gt 0 ]] && \
        printf "  Plus %s in %d unrecognized caches → run with --include-review (recoverable)\n" "$(human_kb "$rev_kb")" "$rev_n"
    echo "  Preview a clean: clinj clean --profile ${PROFILE} --dry-run"
}

# ── clean ─────────────────────────────────────────────────────────────────────
cmd_clean() {
    load_profile; build_catalog
    local ts; ts="$(date '+%Y%m%d-%H%M%S')"
    local batch=""; local freed=0 quar=0 idx=0 n=0
    [[ "$CLINJ_DRY_RUN" == true ]] && echo "🔍 DRY RUN — nothing will be deleted (profile: ${PROFILE_NAME})" \
                                   || echo "🧼 Cleaning — profile: ${PROFILE_NAME}"
    local id cat safe mode regen kb label path
    while IFS=$'\t' read -r id cat safe mode regen kb label path; do
        [[ -z "$id" ]] && continue
        if [[ -n "$ONLY_IDS" ]]; then
            case "$ONLY_IDS" in *" $id "*) ;; *) continue ;; esac
        else
            included "$cat" "$safe" || continue
        fi
        n=$((n+1))
        case "$mode" in
            cmd) [[ "$CLINJ_DRY_RUN" == true ]] || bash -c "$path" >/dev/null 2>&1 || true
                 freed=$((freed+kb)); log "cmd ${id}: ${path}" ;;
            contents) local child
                 for child in "$path"/* "$path"/.[!.]*; do [[ -e "$child" ]] && dispose "$child"; done
                 freed=$((freed+kb)) ;;
            tree|*)
                 if [[ "$safe" == review ]]; then
                     [[ -z "$batch" ]] && batch="$(quarantine_new_batch "$ts")"
                     idx=$((idx+1)); quarantine_move "$path" "$batch" "$idx"; quar=$((quar+kb))
                 else
                     dispose "$path"; freed=$((freed+kb))
                 fi ;;
        esac
        printf "  • %-46s %8s\n" "$label" "$(human_kb "$kb")"
    done <<< "$CATALOG"
    echo "  ────────────────────────────────────"
    printf "  Items: %d   Freed: %s" "$n" "$(human_kb "$freed")"
    [[ "$quar" -gt 0 ]] && printf "   Quarantined (recoverable): %s" "$(human_kb "$quar")"
    echo ""
    [[ "$quar" -gt 0 ]] && echo "  Undo quarantined items: clinj restore"
    log "clean profile=${PROFILE} freed_kb=${freed} quar_kb=${quar} dry=${CLINJ_DRY_RUN}"
}

cmd_profiles() {
    echo "Available profiles:"
    local f
    for f in "$PROFILES_DIR"/*.conf; do
        ( source "$f"; printf "  %-10s %s\n" "$(basename "$f" .conf)" "$PROFILE_DESC" )
    done
}

cmd_doctor() {
    echo "🩺 Clinj doctor"
    echo "   clinj    ${CLINJ_VERSION}"
    echo "   bash     ${BASH_VERSION}"
    echo "   macOS    $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"
    echo "   disk /   $(df -h / | awk 'NR==2{print $4" free of "$2}')"
    local qkb qn
    qkb=$(size_kb "$QUARANTINE_ROOT"); qn=$(find "$QUARANTINE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    echo "   quarant. $(human_kb "$qkb") in ${qn:-0} batch(es)  ($QUARANTINE_ROOT)"
    printf "   tools   "; local t
    for t in node npm pnpm yarn bun pip3 uv go cargo gradle pod xcodebuild docker brew swift; do have "$t" && printf " %s" "$t"; done; echo ""
    echo "   safety self-check:"
    assert_safe_path "$HOME/Documents" 2>/dev/null && echo "     ✗ FAIL: ~/Documents not blocked" || echo "     ✓ blocks ~/Documents"
    assert_safe_path "$HOME/Library/Caches/x" 2>/dev/null && echo "     ✓ allows caches" || echo "     ✗ FAIL: caches blocked"
}

cmd_ram() {
    have_purge() { [[ -x /usr/sbin/purge ]]; }
    have_purge || { echo "purge not available"; exit 1; }
    echo "Freeing inactive memory (you may be asked for your password)…"
    if [[ "$(id -u)" == 0 ]]; then /usr/sbin/purge
    else sudo /usr/sbin/purge; fi
    echo "Done. (macOS reclaims memory automatically too — gains are usually modest.)"
}

case "$CMD" in
    scan)     cmd_scan ;;
    clean)    cmd_clean ;;
    restore)  quarantine_restore "${1:-}" ;;
    sweep)    quarantine_sweep "$SWEEP_DAYS" ;;
    profiles) cmd_profiles ;;
    doctor)   cmd_doctor ;;
    ram)      cmd_ram ;;
    -v|--version) echo "clinj ${CLINJ_VERSION}" ;;
    -h|--help|help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "Unknown command: ${CMD}. Try: clinj help" >&2; exit 1 ;;
esac
