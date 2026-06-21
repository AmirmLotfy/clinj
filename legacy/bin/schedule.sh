#!/bin/bash
# schedule.sh — (re)install Clinj's auto-run LaunchAgent.
# Usage: schedule.sh daily | 3day | weekly | off [hour]
set -uo pipefail

WHEN="${1:-daily}"
HOUR="${2:-3}"
UID_NUM="$(id -u)"
LABEL="com.frameless.clinj.schedule"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
ENGINE="${HOME}/.clinj/bin/clinj.sh"
LOG="${HOME}/Library/Logs/clinj-launchd.log"

# Read hour from conf if present and not overridden
CONF="${HOME}/.clinj/etc/clinj.conf"
if [[ "${2:-}" == "" && -f "$CONF" ]]; then
    h=$(grep -E '^CLINJ_SCHEDULE_HOUR=' "$CONF" | head -1 | cut -d= -f2 | tr -dc '0-9')
    [[ -n "$h" ]] && HOUR="$h"
fi

unload() { launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true; }

if [[ "$WHEN" == "off" ]]; then
    unload
    rm -f "$PLIST"
    echo "Clinj auto-run disabled."
    exit 0
fi

# Build the timing block
case "$WHEN" in
    daily)
        TIMING="    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>${HOUR}</integer>
        <key>Minute</key><integer>0</integer>
    </dict>" ;;
    weekly)
        TIMING="    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key><integer>0</integer>
        <key>Hour</key><integer>${HOUR}</integer>
        <key>Minute</key><integer>0</integer>
    </dict>" ;;
    3day)
        TIMING="    <key>StartInterval</key>
    <integer>259200</integer>" ;;
    *)
        echo "Unknown schedule: $WHEN (use daily|3day|weekly|off)"; exit 1 ;;
esac

mkdir -p "${HOME}/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${ENGINE}</string>
        <string>--quiet</string>
    </array>
${TIMING}
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${LOG}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLISTEOF

unload
launchctl bootstrap "gui/${UID_NUM}" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
echo "Clinj auto-run scheduled: ${WHEN} (hour ${HOUR})."
