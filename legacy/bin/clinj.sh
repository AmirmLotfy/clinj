#!/bin/bash
# Clinj — lightweight, safe Mac cleaner + RAM booster
# Cleans caches/logs/temp/dev-artifacts only. Never touches your documents.
#
# Usage:
#   clinj.sh                 Standard-safe cleanup (interactive summary)
#   clinj.sh --aggressive    Also reclaim big-ticket caches (Chrome ML models, Xcode archives…)
#   clinj.sh --ram           Cleanup, then RAM boost (purge inactive/cached memory)
#   clinj.sh --ram-only      Only RAM boost, no disk cleaning
#   clinj.sh --scan          Show large safe-to-clean targets (no deletion)
#   clinj.sh --dry-run       Preview what would be cleaned (no deletion)
#   clinj.sh --quiet         Minimal output (for scheduled runs)
#   clinj.sh --report        Machine mode: one summary line + writes JSON (for the GUI apps)
#   clinj.sh --mem           Print current free memory in MB and exit
#
# Combine freely, e.g.:  clinj.sh --aggressive --ram --report

set -uo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONF_FILE="${CLINJ_CONF:-${ROOT_DIR}/etc/clinj.conf}"
LOG_FILE="${HOME}/Library/Logs/clinj.log"
JSON_FILE="${HOME}/Library/Logs/clinj-last.json"

DRY_RUN=false
QUIET=false
SCAN_ONLY=false
AGGRESSIVE=false
DO_RAM=false
RAM_ONLY=false
REPORT=false
MEM_ONLY=false
SPACE_FREED=0          # MB
RAM_FREED=0            # MB

# Defaults (overridable via etc/clinj.conf) ───────────────────────────────────
CLEAN_NPM=1
CLEAN_PNPM=1
CLEAN_YARN=1
CLEAN_PIP=1
CLEAN_HOMEBREW=1
CLEAN_GRADLE=1
CLEAN_COCOAPODS=1
CLEAN_PLAYWRIGHT=1
CLEAN_BUILD_CACHES=1
CLEAN_USER_CACHE=1
CLEAN_DOCKER=1
CLEAN_SIMULATORS=1
CLEAN_XCODE_DERIVED=1
CLEAN_ELECTRON=1
CLEAN_CHROME=1
CLEAN_SYS_CACHES=1
CLEAN_LOGS=1
CLEAN_TEMP=1
CLEAN_TRASH=1
# Aggressive items (only act when --aggressive is passed)
AGG_CHROME_MODELS=1
AGG_XCODE_ARCHIVES=1
AGG_XCODE_DEVICESUPPORT=1
AGG_CLAUDE_VM_BUNDLES=0   # 13GB+ on this Mac; heavy re-download — opt-in only

# Electron / Chromium-based apps on this Mac
ELECTRON_APPS=(
    Cursor Windsurf Qoder Kiro Trae Claude Codex
    "Antigravity" "Antigravity IDE" Figma "zoom.us" Adobe
    "Windsurf - Next" Airtable ClickUp Rave Anghami
)

# Load user config if present (can override any of the above) ──────────────────
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE" 2>/dev/null || true
fi

# ── output helpers ────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    if [[ "$QUIET" == false && "$REPORT" == false ]]; then
        echo "$*"
    fi
}
log_quiet() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

get_size_mb() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sm "$path" 2>/dev/null | awk '{print $1}' || echo 0
    else
        echo 0
    fi
}

# ── SAFETY GUARD ──────────────────────────────────────────────────────────────
# Every deletion routes through assert_safe_path(). It refuses to delete:
#  - empty/unset targets (guards against `rm -rf $unset/*`)
#  - the home dir, /, or any protected user-data root
#  - anything outside the known cache/log/temp/dev-artifact zones
PROTECTED=(
    "${HOME}/Documents" "${HOME}/Desktop" "${HOME}/Downloads"
    "${HOME}/Pictures" "${HOME}/Movies" "${HOME}/Music"
    "${HOME}/Library/Mobile Documents" "${HOME}/Library/Keychains"
    "${HOME}/Library/Messages" "${HOME}/Library/Mail"
)

assert_safe_path() {
    local p="$1"
    # 1. reject empty / whitespace-only
    [[ -z "${p// /}" ]] && { log_quiet "BLOCKED empty path"; return 1; }
    # 2. reject filesystem root and the home dir itself
    [[ "$p" == "/" || "$p" == "$HOME" || "$p" == "$HOME/" ]] && { log_quiet "BLOCKED root/home: $p"; return 1; }
    # 3. must live under $HOME or the system temp area — nothing else
    case "$p" in
        "$HOME"/*|/private/var/folders/*|/tmp/*) ;;
        *) log_quiet "BLOCKED outside-allowed: $p"; return 1 ;;
    esac
    # 4. reject anything inside a protected user-data root
    local prot
    for prot in "${PROTECTED[@]}"; do
        if [[ "$p" == "$prot" || "$p" == "$prot/"* ]]; then
            log_quiet "BLOCKED protected: $p"; return 1
        fi
    done
    return 0
}

safe_rm_contents() {
    local target="$1"
    [[ -d "$target" ]] || return 0
    assert_safe_path "$target" || return 0
    [[ "$DRY_RUN" == true ]] && return 0
    rm -rf "${target:?}"/* 2>/dev/null || true
}

safe_rm_path() {
    local target="$1"
    [[ -e "$target" ]] || return 0
    assert_safe_path "$target" || return 0
    [[ "$DRY_RUN" == true ]] && return 0
    rm -rf "${target:?}" 2>/dev/null || true
}

clean_dir() {
    local label="$1" path="$2" size
    size=$(get_size_mb "$path")
    [[ "$size" -gt 0 ]] || return 0
    safe_rm_contents "$path"
    log "✅ ${label} (~${size}MB)"
    SPACE_FREED=$((SPACE_FREED + size))
}

clean_electron_app() {
    local app="$1" base="${HOME}/Library/Application Support/${app}"
    [[ -d "$base" ]] || return 0
    local sub size total=0
    for sub in Cache "Code Cache" GPUCache CachedData blob_storage "Service Worker/CacheStorage" logs; do
        size=$(get_size_mb "${base}/${sub}")
        total=$((total + size))
        safe_rm_contents "${base}/${sub}"
    done
    [[ "$total" -gt 0 ]] && log_quiet "Electron ${app}: ~${total}MB"
    SPACE_FREED=$((SPACE_FREED + total))
}

clean_chrome_profile_caches() {
    local chrome_base="${HOME}/Library/Application Support/Google/Chrome"
    [[ -d "$chrome_base" ]] || return 0
    local profile size total=0
    for profile in "${chrome_base}"/*/; do
        [[ -d "$profile" ]] || continue
        for sub in Cache "Code Cache" GPUCache; do
            size=$(get_size_mb "${profile}${sub}")
            total=$((total + size))
            safe_rm_contents "${profile}${sub}"
        done
    done
    for sub in component_crx_cache screen_ai GrShaderCache ShaderCache; do
        size=$(get_size_mb "${chrome_base}/${sub}")
        total=$((total + size))
        safe_rm_contents "${chrome_base}/${sub}"
    done
    log "✅ Chrome profile caches (~${total}MB)"
    SPACE_FREED=$((SPACE_FREED + total))
}

# ── memory helpers ──────────────────────────────────────────────────────────

mem_free_mb() {
    # free + inactive + speculative + purgeable pages → MB (no root needed)
    local pagesize
    pagesize=$(vm_stat | sed -n '1s/.*page size of \([0-9]*\).*/\1/p')
    [[ -z "$pagesize" ]] && pagesize=16384
    vm_stat | awk -v ps="$pagesize" '
        /Pages free/        {gsub(/\./,"",$3); f=$3}
        /Pages inactive/    {gsub(/\./,"",$3); i=$3}
        /Pages speculative/ {gsub(/\./,"",$3); s=$3}
        /Pages purgeable/   {gsub(/\./,"",$3); p=$3}
        END {printf "%d", ((f+i+s+p)*ps)/1048576}'
}

mem_pressure() {
    case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
        1) echo "normal" ;; 2) echo "warning" ;; 4) echo "critical" ;; *) echo "normal" ;;
    esac
}

ram_boost() {
    local before after
    before=$(mem_free_mb)
    log "🧠 RAM boost (purge inactive/cached memory)..."
    if [[ "$DRY_RUN" == false ]]; then
        if [[ "$(id -u)" == "0" ]]; then
            /usr/sbin/purge 2>/dev/null || true
        else
            # works non-interactively only if the optional sudoers rule is installed;
            # the GUI runs purge itself via a Touch ID prompt instead.
            sudo -n /usr/sbin/purge 2>/dev/null || log_quiet "purge skipped (needs privilege)"
        fi
    fi
    after=$(mem_free_mb)
    RAM_FREED=$((after - before))
    [[ "$RAM_FREED" -lt 0 ]] && RAM_FREED=0
    log "✅ RAM boost — free memory ${before}MB → ${after}MB (pressure: $(mem_pressure))"
}

df_avail_human() { df -h / | tail -1 | awk '{print $4}'; }
df_avail_mb()    { df -m / | tail -1 | awk '{print $4}'; }

# ── argparse ─────────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=true ;;
        --quiet)      QUIET=true ;;
        --scan)       SCAN_ONLY=true ;;
        --aggressive) AGGRESSIVE=true ;;
        --vm-bundles) AGGRESSIVE=true; AGG_CLAUDE_VM_BUNDLES=1 ;;
        --ram)        DO_RAM=true ;;
        --ram-only)   RAM_ONLY=true; DO_RAM=true ;;
        --report)     REPORT=true; QUIET=true ;;
        --mem)        MEM_ONLY=true ;;
        -h|--help)    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    esac
done

mkdir -p "$(dirname "$LOG_FILE")"

# ── --mem: print free memory and exit ────────────────────────────────────────
if [[ "$MEM_ONLY" == true ]]; then echo "$(mem_free_mb)"; exit 0; fi

# ── --scan: report large targets, no deletion ────────────────────────────────
if [[ "$SCAN_ONLY" == true ]]; then
    echo "📡 Scanning for large safe-to-clean areas..."
    echo ""; echo "── ~/Library/Caches (top 20) ──"
    du -sh "${HOME}/Library/Caches"/* 2>/dev/null | sort -hr | head -20
    echo ""; echo "── Dev tool caches ──"
    for d in "${HOME}/.npm" "${HOME}/.gradle" "${HOME}/.cocoapods" "${HOME}/.cache" \
        "${HOME}/Library/Caches/pnpm" "${HOME}/Library/Caches/ms-playwright" \
        "${HOME}/Library/Developer/Xcode/DerivedData" \
        "${HOME}/Library/Developer/Xcode/Archives" \
        "${HOME}/Library/Developer/Xcode/iOS DeviceSupport" \
        "${HOME}/Library/Developer/CoreSimulator"; do
        [[ -e "$d" ]] && du -sh "$d" 2>/dev/null
    done
    echo ""; echo "── Aggressive-mode targets (--aggressive) ──"
    for variant in "Chrome" "Chrome Canary" "Chrome Dev"; do
        for m in optimization_guide_model_store OptGuideOnDeviceClassifierModel OnDeviceHeadSuggestModel GraphiteDawnCache; do
            du -sh "${HOME}/Library/Application Support/Google/${variant}/${m}" 2>/dev/null
        done
    done
    du -sh "${HOME}/Library/Developer/Xcode/Archives" 2>/dev/null
    du -sh "${HOME}/Library/Developer/Xcode/iOS DeviceSupport" 2>/dev/null
    echo ""; echo "── Biggest opt-in win (--vm-bundles, off by default) ──"
    VMB=$(du -sh "${HOME}/Library/Application Support/Claude/vm_bundles" 2>/dev/null | awk '{print $1}')
    [[ -n "$VMB" ]] && echo "  ${VMB}  Claude sandbox VM bundles → re-downloads when you next use Claude's sandbox"
    echo ""; echo "── Manual review (Clinj never auto-deletes these) ──"
    du -sh "${HOME}/Downloads" 2>/dev/null && echo "  → review ~/Downloads yourself"
    du -sh "${HOME}/Library/Application Support/MobileSync/Backup" 2>/dev/null && echo "  → iOS device backups (your data)"
    echo ""; echo "Run without --scan to clean. --dry-run previews. --aggressive reclaims more. --vm-bundles adds the 13GB Claude win."
    exit 0
fi

# ── --ram-only: just boost memory ────────────────────────────────────────────
if [[ "$RAM_ONLY" == true ]]; then
    log_quiet "─── clinj v${VERSION} RAM-only ───"
    ram_boost
    if [[ "$REPORT" == true ]]; then
        printf '{"mode":"ram-only","ram_freed_mb":%d,"ram_free_mb":%d,"ram_pressure":"%s"}\n' \
            "$RAM_FREED" "$(mem_free_mb)" "$(mem_pressure)" > "$JSON_FILE"
        echo "RAM freed: ~${RAM_FREED} MB · free: $(mem_free_mb) MB · pressure: $(mem_pressure)"
    fi
    exit 0
fi

# ── main cleanup ─────────────────────────────────────────────────────────────
log_quiet "─── clinj v${VERSION} started (dry_run=${DRY_RUN} aggressive=${AGGRESSIVE}) ───"
DISK_BEFORE_H=$(df_avail_human); DISK_BEFORE_MB=$(df_avail_mb)

if [[ "$QUIET" == false && "$REPORT" == false ]]; then
    echo "🧼 Clinj v${VERSION}"
    [[ "$DRY_RUN" == true ]]    && echo "🔍 DRY RUN — nothing will be deleted"
    [[ "$AGGRESSIVE" == true ]] && echo "⚡ AGGRESSIVE — reclaiming big-ticket caches too"
    echo "⚠️  Caches/logs/temp only. Your Documents, Desktop & Downloads are never touched."
    echo ""; echo "📊 Disk free before: ${DISK_BEFORE_H}"; echo ""
fi

# 1. npm
if [[ "$CLEAN_NPM" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/.npm/_cacache")
    [[ "$DRY_RUN" == false ]] && npm cache clean --force 2>/dev/null || true
    log "✅ npm cache (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 2. pnpm
if [[ "$CLEAN_PNPM" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/Library/Caches/pnpm")
    [[ "$DRY_RUN" == false ]] && pnpm store prune 2>/dev/null || true
    safe_rm_contents "${HOME}/Library/Caches/pnpm"
    log "✅ pnpm cache (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 3. yarn
if [[ "$CLEAN_YARN" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/Library/Caches/Yarn")
    [[ "$DRY_RUN" == false ]] && yarn cache clean 2>/dev/null || true
    safe_rm_contents "${HOME}/Library/Caches/Yarn"
    log "✅ Yarn cache (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 4. pip
if [[ "$CLEAN_PIP" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/Library/Caches/pip")
    [[ "$DRY_RUN" == false ]] && pip3 cache purge 2>/dev/null || true
    safe_rm_contents "${HOME}/Library/Caches/pip"
    log "✅ pip cache (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 5. Homebrew
if [[ "$CLEAN_HOMEBREW" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/Library/Caches/Homebrew")
    if [[ "$DRY_RUN" == false ]]; then brew cleanup -s 2>/dev/null || true; brew autoremove 2>/dev/null || true; fi
    safe_rm_contents "${HOME}/Library/Caches/Homebrew/downloads"
    log "✅ Homebrew (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 6. Gradle
if [[ "$CLEAN_GRADLE" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/.gradle/caches")
    safe_rm_contents "${HOME}/.gradle/caches"; safe_rm_contents "${HOME}/.gradle/daemon"
    log "✅ Gradle (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 7. CocoaPods
if [[ "$CLEAN_COCOAPODS" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/.cocoapods/repos")
    safe_rm_contents "${HOME}/.cocoapods/repos"
    log "✅ CocoaPods (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 8. Playwright
if [[ "$CLEAN_PLAYWRIGHT" == 1 ]]; then
    SIZE=0
    for pw in "${HOME}/Library/Caches/ms-playwright" "${HOME}/Library/Caches/ms-playwright-go"; do
        SIZE=$((SIZE + $(get_size_mb "$pw"))); safe_rm_contents "$pw"
    done
    log "✅ Playwright caches (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 9. Build caches
if [[ "$CLEAN_BUILD_CACHES" == 1 ]]; then
    for entry in \
        "next-swc|${HOME}/Library/Caches/next-swc" \
        "node-gyp|${HOME}/Library/Caches/node-gyp" \
        "TypeScript|${HOME}/Library/Caches/typescript" \
        "go-build|${HOME}/Library/Caches/go-build" \
        "dotslash|${HOME}/Library/Caches/dotslash"; do
        clean_dir "${entry%%|*}" "${entry#*|}"
    done
fi
# 10. User ~/.cache
if [[ "$CLEAN_USER_CACHE" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/.cache")
    for sub in node deno firebase codex-runtimes huggingface uv; do safe_rm_contents "${HOME}/.cache/${sub}"; done
    log "✅ User ~/.cache (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 11. Docker
if [[ "$CLEAN_DOCKER" == 1 ]] && command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    if [[ "$DRY_RUN" == false ]]; then
        docker system prune -f --filter "until=72h" 2>/dev/null || true
        docker builder prune -f --filter "until=72h" 2>/dev/null || true
    fi
    log "✅ Docker pruned (dangling >72h)"
fi
# 12. iOS Simulators
if [[ "$CLEAN_SIMULATORS" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/Library/Developer/CoreSimulator/Caches")
    [[ "$DRY_RUN" == false ]] && xcrun simctl delete unavailable 2>/dev/null || true
    safe_rm_contents "${HOME}/Library/Developer/CoreSimulator/Caches"
    safe_rm_contents "${HOME}/Library/Developer/CoreSimulator/Temp"
    log "✅ iOS Simulator caches (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 13. Xcode DerivedData
if [[ "$CLEAN_XCODE_DERIVED" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/Library/Developer/Xcode/DerivedData")
    safe_rm_contents "${HOME}/Library/Developer/Xcode/DerivedData"
    log "✅ Xcode Derived Data (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi
# 14. Electron apps
if [[ "$CLEAN_ELECTRON" == 1 ]]; then
    for app in "${ELECTRON_APPS[@]}"; do clean_electron_app "$app"; done
    for cache in "${HOME}/Library/Caches"/com.todesktop.*; do
        [[ -d "$cache" ]] || continue
        s=$(get_size_mb "$cache"); safe_rm_contents "$cache"; SPACE_FREED=$((SPACE_FREED + s))
    done
    log "✅ Electron app caches"
fi
# 15. Chrome profile caches
if [[ "$CLEAN_CHROME" == 1 ]]; then
    clean_chrome_profile_caches
    safe_rm_contents "${HOME}/Library/Caches/Google/Chrome"
fi
# 16. System app caches
if [[ "$CLEAN_SYS_CACHES" == 1 ]]; then
    for entry in \
        "OpenAI Codex|${HOME}/Library/Caches/com.openai.codex" \
        "OpenAI Sky|${HOME}/Library/Caches/com.openai.sky.CUAService" \
        "Codex|${HOME}/Library/Caches/Codex" \
        "Figma|${HOME}/Library/Caches/com.figma.Desktop" \
        "Spotify|${HOME}/Library/Caches/com.spotify.client" \
        "Apple Python|${HOME}/Library/Caches/com.apple.python"; do
        clean_dir "${entry%%|*}" "${entry#*|}"
    done
    SIZE=0
    for cache in "${HOME}/Library/Caches"/*.ShipIt; do
        [[ -d "$cache" ]] || continue
        SIZE=$((SIZE + $(get_size_mb "$cache"))); safe_rm_contents "$cache"
    done
    [[ "$SIZE" -gt 0 ]] && { log "✅ ShipIt caches (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE)); }
fi
# 17. Logs
if [[ "$CLEAN_LOGS" == 1 ]]; then
    LOG_SIZE=0
    while IFS= read -r -d '' f; do
        LOG_SIZE=$((LOG_SIZE + $(get_size_mb "$f")))
        [[ "$DRY_RUN" == false ]] && rm -f "$f" 2>/dev/null || true
    done < <(find "${HOME}/Library/Logs" \( -name "*.log" -o -name "*.old" \) -type f -print0 2>/dev/null)
    safe_rm_contents "${HOME}/Library/Logs/DiagnosticReports"
    log "✅ Old logs (~${LOG_SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + LOG_SIZE))
fi
# 18. Temp files
if [[ "$CLEAN_TEMP" == 1 ]]; then
    safe_rm_contents "${HOME}/Library/Caches/TemporaryItems"
    if [[ "$DRY_RUN" == false ]]; then rm -rf /private/var/folders/*/T/TemporaryItems/* 2>/dev/null || true; fi
    log "✅ Temporary files"
fi
# 19. Trash
if [[ "$CLEAN_TRASH" == 1 ]]; then
    SIZE=$(get_size_mb "${HOME}/.Trash")
    safe_rm_contents "${HOME}/.Trash"
    log "✅ Trash (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
fi

# ── aggressive extras ────────────────────────────────────────────────────────
if [[ "$AGGRESSIVE" == true ]]; then
    if [[ "$AGG_CHROME_MODELS" == 1 ]]; then
        SIZE=0
        for variant in "Chrome" "Chrome Canary" "Chrome Dev"; do
            cbase="${HOME}/Library/Application Support/Google/${variant}"
            [[ -d "$cbase" ]] || continue
            for m in optimization_guide_model_store OptGuideOnDeviceClassifierModel OnDeviceHeadSuggestModel GraphiteDawnCache; do
                SIZE=$((SIZE + $(get_size_mb "${cbase}/${m}")))
                safe_rm_path "${cbase}/${m}"
            done
        done
        log "⚡ Chrome on-device ML models (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE))
    fi
    if [[ "$AGG_XCODE_ARCHIVES" == 1 ]]; then
        SIZE=$(get_size_mb "${HOME}/Library/Developer/Xcode/Archives")
        safe_rm_contents "${HOME}/Library/Developer/Xcode/Archives"
        [[ "$SIZE" -gt 0 ]] && { log "⚡ Xcode Archives (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE)); }
    fi
    if [[ "$AGG_XCODE_DEVICESUPPORT" == 1 ]]; then
        SIZE=$(get_size_mb "${HOME}/Library/Developer/Xcode/iOS DeviceSupport")
        safe_rm_contents "${HOME}/Library/Developer/Xcode/iOS DeviceSupport"
        [[ "$SIZE" -gt 0 ]] && { log "⚡ Xcode iOS DeviceSupport (~${SIZE}MB)"; SPACE_FREED=$((SPACE_FREED + SIZE)); }
    fi
    # Claude sandbox VM bundles — biggest single win but a heavy re-download.
    # Off by default; enabled only via --vm-bundles or AGG_CLAUDE_VM_BUNDLES=1.
    if [[ "$AGG_CLAUDE_VM_BUNDLES" == 1 ]]; then
        SIZE=$(get_size_mb "${HOME}/Library/Application Support/Claude/vm_bundles")
        safe_rm_contents "${HOME}/Library/Application Support/Claude/vm_bundles"
        [[ "$SIZE" -gt 0 ]] && { log "⚡ Claude VM bundles (~${SIZE}MB — re-downloads on next sandbox use)"; SPACE_FREED=$((SPACE_FREED + SIZE)); }
    fi
fi

# ── optional RAM boost after cleaning ────────────────────────────────────────
[[ "$DO_RAM" == true ]] && ram_boost

# ── summary ──────────────────────────────────────────────────────────────────
DISK_AFTER_H=$(df_avail_human); DISK_AFTER_MB=$(df_avail_mb)

if [[ "$REPORT" == true ]]; then
    printf '{"mode":"%s","dry_run":%s,"freed_mb":%d,"disk_before_mb":%s,"disk_after_mb":%s,"ram_freed_mb":%d,"ram_pressure":"%s","log":"%s"}\n' \
        "$([[ $AGGRESSIVE == true ]] && echo aggressive || echo standard)" \
        "$DRY_RUN" "$SPACE_FREED" "$DISK_BEFORE_MB" "$DISK_AFTER_MB" "$RAM_FREED" "$(mem_pressure)" "$LOG_FILE" \
        > "$JSON_FILE"
    LINE="Freed ~${SPACE_FREED} MB · Disk free: ${DISK_BEFORE_H} → ${DISK_AFTER_H}"
    [[ "$DO_RAM" == true ]] && LINE="${LINE} · RAM freed: ~${RAM_FREED} MB (pressure: $(mem_pressure))"
    [[ "$DRY_RUN" == true ]] && LINE="DRY RUN — would free ~${SPACE_FREED} MB (disk free: ${DISK_BEFORE_H})"
    echo "$LINE"
elif [[ "$QUIET" == false ]]; then
    echo ""; echo "📊 Disk free after: ${DISK_AFTER_H}"
    echo ""; echo "✅ Done — freed ~${SPACE_FREED} MB"
    [[ "$DO_RAM" == true ]] && echo "🧠 RAM freed ~${RAM_FREED} MB (pressure: $(mem_pressure))"
    echo "📋 Log: ${LOG_FILE}"
fi

log_quiet "─── clinj finished (~${SPACE_FREED}MB disk, ~${RAM_FREED}MB ram) ───"
