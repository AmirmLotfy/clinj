#!/bin/bash
# Clinj uninstaller — removes apps, agents, sudoers rule, and ~/.clinj.
# Leaves your ~/.clinj/backup untouched unless you pass --purge-all.
set -uo pipefail
PURGE_ALL=false
for a in "$@"; do [[ "$a" == "--purge-all" ]] && PURGE_ALL=true; done

say() { printf "• %s\n" "$*"; }
echo "Uninstalling Clinj…"

# stop & remove LaunchAgents
for label in com.frameless.clinj.schedule com.frameless.clinj.menubar; do
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    rm -f "${HOME}/Library/LaunchAgents/${label}.plist"
done
say "Removed LaunchAgents"

# quit & remove apps from both possible locations
for dir in /Applications "${HOME}/Applications"; do
    rm -rf "${dir}/Clinj.app" "${dir}/Clinj Menu.app"
done
pkill -f "clinj-menubar" 2>/dev/null || true
say "Removed apps"

# sudoers rule (if present)
if [[ -f /etc/sudoers.d/clinj ]]; then
    sudo rm -f /etc/sudoers.d/clinj && say "Removed password-free purge rule"
fi

# logs
rm -f "${HOME}/Library/Logs/clinj.log" "${HOME}/Library/Logs/clinj-last.json" "${HOME}/Library/Logs/clinj-launchd.log"

# runtime
if $PURGE_ALL; then
    rm -rf "${HOME}/.clinj"
    say "Removed ~/.clinj (including backups)"
else
    rm -rf "${HOME}/.clinj/bin" "${HOME}/.clinj/assets"
    say "Removed ~/.clinj engine (kept ~/.clinj/etc config & ~/.clinj/backup)"
fi

echo "✅ Clinj uninstalled."
