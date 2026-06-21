#!/usr/bin/env bash
# safety.sh — the guardrail every deletion must pass through.
# Designed to fail CLOSED: anything not provably inside a known-disposable
# zone, and anything inside a protected user-data zone, is refused.

# Hard-protected roots — never touched, even if a rule names them.
clinj_protected_roots() {
    printf '%s\n' \
        "${HOME}/Documents" "${HOME}/Desktop" "${HOME}/Downloads" \
        "${HOME}/Pictures" "${HOME}/Movies" "${HOME}/Music" \
        "${HOME}/Library/Mobile Documents" \
        "${HOME}/Library/Keychains" \
        "${HOME}/Library/Messages" \
        "${HOME}/Library/Mail" \
        "${HOME}/Library/Application Support/AddressBook" \
        "${HOME}/Library/Application Support/MobileSync" \
        "${HOME}/.ssh" "${HOME}/.gnupg" "${HOME}/.config/gh"
}

# Zones where disposable data is allowed to live.
clinj_allowed_prefixes() {
    printf '%s\n' \
        "${HOME}/Library/Caches" \
        "${HOME}/Library/Logs" \
        "${HOME}/Library/Application Support" \
        "${HOME}/Library/Developer" \
        "${HOME}/Library/Containers" \
        "${HOME}/.cache" "${HOME}/.npm" "${HOME}/.gradle" "${HOME}/.cocoapods" \
        "${HOME}/.docker" "${HOME}/.Trash" \
        "${HOME}/.bun/install/cache" "${HOME}/.yarn/cache" \
        "${HOME}/.cargo/registry/cache" "${HOME}/.pub-cache" \
        "/private/var/folders" "/tmp" "/private/tmp"
}

# Return 0 only if it is safe to delete $1.
assert_safe_path() {
    local p="$1" root prefix ok=1
    [[ -z "${p// /}" ]] && { log "BLOCK empty path"; return 1; }
    [[ "$p" == "/" || "$p" == "$HOME" || "$p" == "$HOME/" ]] && { log "BLOCK root/home: $p"; return 1; }
    case "$p" in *..* ) log "BLOCK dotdot: $p"; return 1 ;; esac
    # must be under an allowed prefix
    while IFS= read -r prefix; do
        [[ "$p" == "$prefix" || "$p" == "$prefix/"* ]] && { ok=0; break; }
    done < <(clinj_allowed_prefixes)
    [[ "$ok" -eq 0 ]] || { log "BLOCK outside-allowed: $p"; return 1; }
    # ...and never inside a protected root
    while IFS= read -r root; do
        [[ "$p" == "$root" || "$p" == "$root/"* ]] && { log "BLOCK protected: $p"; return 1; }
    done < <(clinj_protected_roots)
    return 0
}
