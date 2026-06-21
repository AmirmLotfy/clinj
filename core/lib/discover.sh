#!/usr/bin/env bash
# discover.sh — builds the catalog of cleanable items for THIS machine.
# Combines the known-rule catalog with live, structural detection so Clinj
# works on a Mac it has never seen: it finds Electron apps and browsers by
# their on-disk shape, and treats unknown caches as recoverable ("review").

# Electron/Chromium cache subdirs worth clearing inside an app's data dir.
CLINJ_CHROMIUM_CACHE_SUBDIRS=(
    "Cache" "Code Cache" "GPUCache" "CachedData" "blob_storage"
    "Service Worker/CacheStorage" "DawnGraphiteCache" "DawnWebGPUCache"
    "GrShaderCache" "ShaderCache" "Crashpad/completed"
)
# Chromium ML/model dirs — bigger, regenerable, but heavier to refetch.
CLINJ_CHROMIUM_MODEL_SUBDIRS=(
    "optimization_guide_model_store" "OptGuideOnDeviceClassifierModel" "OnDeviceHeadSuggestModel"
)

_expand() { printf '%s' "${1/#\~/$HOME}"; }
_slug()   { printf '%s' "$1" | tr ' /' '__' | tr -cd '[:alnum:]_.-'; }

# main entry: prints catalog TSV to stdout. (bash 3.2 compatible — no assoc arrays)
clinj_discover() {
    local EMITTED_FILE; EMITTED_FILE="$(mktemp -t clinj_emit.XXXXXX)"
    _emit_path() { # id cat safe mode regen label path
        local path="$7"
        grep -qxF -- "$path" "$EMITTED_FILE" 2>/dev/null && return 0
        local kb; kb=$(size_kb "$path"); [[ "$kb" -gt 0 ]] || return 0
        printf '%s\n' "$path" >> "$EMITTED_FILE"
        emit_item "$1" "$2" "$3" "$4" "$5" "$kb" "$6" "$path"
    }

    # ── 1. known rules ────────────────────────────────────────────────────────
    local line id cat safe mode regen label target
    while IFS='|' read -r id cat safe mode regen label target; do
        [[ -z "$id" || "$id" == \#* ]] && continue
        if [[ "$mode" == cmd ]]; then
            local sizepath cmd tool
            sizepath="$(_expand "${target%%::*}")"; cmd="${target##*::}"; tool="${cmd%% *}"
            have "$tool" || continue
            local kb; kb=$(size_kb "$sizepath")
            emit_item "$id" "$cat" "$safe" "cmd" "$regen" "$kb" "$label" "$cmd"
        else
            _emit_path "$id" "$cat" "$safe" "$mode" "$regen" "$label" "$(_expand "$target")"
        fi
    done < <(clinj_known_rules)

    # ── 2. Electron apps (structural detection) ───────────────────────────────
    local appdir base name sub
    while IFS= read -r appdir; do
        [[ -d "$appdir" ]] || continue
        name="$(basename "$appdir")"
        # browsers handled separately; skip their container dirs
        case "$name" in Google|Microsoft\ Edge|BraveSoftware|Arc|Vivaldi|Chromium|Firefox) continue ;; esac
        # Electron/Chromium signature: has a Code Cache or GPUCache dir
        if [[ -d "$appdir/Code Cache" || -d "$appdir/GPUCache" ]]; then
            for sub in "${CLINJ_CHROMIUM_CACHE_SUBDIRS[@]}"; do
                _emit_path "electron:$(_slug "$name"):$(_slug "$sub")" "apps" "safe" "tree" \
                    "rebuilt by ${name}" "${name} — ${sub}" "$appdir/$sub"
            done
        fi
    done < <(find "${HOME}/Library/Application Support" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    # ── 3. Browsers (Chromium family + Firefox) ───────────────────────────────
    local bbase profile
    for bbase in \
        "Google/Chrome" "Google/Chrome Canary" "Google/Chrome Dev" "Google/Chrome Beta" \
        "Microsoft Edge" "BraveSoftware/Brave-Browser" "Arc" "Vivaldi" "Chromium"; do
        base="${HOME}/Library/Application Support/${bbase}"
        [[ -d "$base" ]] || continue
        local bname; bname="$(_slug "$bbase")"
        # per-profile caches
        while IFS= read -r profile; do
            for sub in "Cache" "Code Cache" "GPUCache" "Service Worker/CacheStorage"; do
                _emit_path "browser:${bname}:$(_slug "$(basename "$profile")"):$(_slug "$sub")" "browsers" "safe" "tree" \
                    "rebuilt by browser" "${bbase} $(basename "$profile") — ${sub}" "$profile/$sub"
            done
        done < <(find "$base" -maxdepth 1 -type d \( -name "Default" -o -name "Profile *" -o -name "Guest Profile" \) 2>/dev/null)
        # shared shader caches
        for sub in "GrShaderCache" "ShaderCache" "GraphiteDawnCache" "component_crx_cache"; do
            _emit_path "browser:${bname}:shared:$(_slug "$sub")" "browsers" "safe" "tree" \
                "rebuilt by browser" "${bbase} — ${sub}" "$base/$sub"
        done
        # on-device ML models (aggressive)
        for sub in "${CLINJ_CHROMIUM_MODEL_SUBDIRS[@]}"; do
            _emit_path "browser:${bname}:model:$(_slug "$sub")" "browsers" "aggressive" "tree" \
                "re-downloaded by browser" "${bbase} — ${sub}" "$base/$sub"
        done
    done
    # Firefox cache
    while IFS= read -r profile; do
        _emit_path "browser:firefox:$(_slug "$(basename "$(dirname "$profile")")"):cache2" "browsers" "safe" "tree" \
            "rebuilt by Firefox" "Firefox $(basename "$(dirname "$profile")") — cache2" "$profile"
    done < <(find "${HOME}/Library/Caches/Firefox/Profiles" -maxdepth 2 -type d -name cache2 2>/dev/null)

    # ── 4. Unknown top-level caches → review (recoverable) ────────────────────
    local c
    while IFS= read -r c; do
        [[ -d "$c" ]] || continue
        _emit_path "cache:$(_slug "$(basename "$c")")" "system" "review" "tree" \
            "regenerated if still used" "Cache: $(basename "$c")" "$c"
    done < <(find "${HOME}/Library/Caches" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    rm -f "$EMITTED_FILE"
}
