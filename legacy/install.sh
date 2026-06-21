#!/bin/bash
# Clinj installer — builds the Dock + menu-bar apps, installs the engine to ~/.clinj,
# sets up the auto-run schedule, and retires the old cleanup-mac setup.
#
# Usage:
#   bash install.sh                          Normal install
#   bash install.sh --enable-purge-nopasswd  Also allow password-free RAM purge (writes
#                                            a narrow /etc/sudoers.d rule; needs sudo once)
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_CLINJ="${HOME}/.clinj"
ENABLE_PURGE=false
for a in "$@"; do [[ "$a" == "--enable-purge-nopasswd" ]] && ENABLE_PURGE=true; done

say() { printf "• %s\n" "$*"; }

echo "🧼 Installing Clinj…"

# ── 1. runtime → ~/.clinj ────────────────────────────────────────────────────
mkdir -p "$HOME_CLINJ/bin" "$HOME_CLINJ/etc" "$HOME_CLINJ/assets" "$HOME_CLINJ/backup"
cp "$SRC/bin/clinj.sh" "$SRC/bin/schedule.sh" "$HOME_CLINJ/bin/"
chmod +x "$HOME_CLINJ/bin/"*.sh
if [[ -f "$HOME_CLINJ/etc/clinj.conf" ]]; then
    say "Kept your existing config at ~/.clinj/etc/clinj.conf"
else
    cp "$SRC/etc/clinj.conf" "$HOME_CLINJ/etc/"
    say "Installed default config"
fi

# ── 2. icon → ~/.clinj/assets/clinj.icns ─────────────────────────────────────
ICNS="$HOME_CLINJ/assets/clinj.icns"
TMP_ICON="$(mktemp -d)"; PNG="$TMP_ICON/icon_1024.png"; SETDIR="$TMP_ICON/clinj.iconset"; mkdir -p "$SETDIR"
if swift "$SRC/app/makeicon.swift" "$PNG" 2>/dev/null && [[ -f "$PNG" ]]; then
    for s in 16 32 128 256 512; do
        sips -z $s $s          "$PNG" --out "$SETDIR/icon_${s}x${s}.png"      >/dev/null 2>&1
        sips -z $((s*2)) $((s*2)) "$PNG" --out "$SETDIR/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    sips -z 1024 1024 "$PNG" --out "$SETDIR/icon_512x512@2x.png" >/dev/null 2>&1
    iconutil -c icns "$SETDIR" -o "$ICNS" 2>/dev/null && say "Built app icon" || say "Icon build skipped"
else
    say "Icon render skipped (apps will use the default icon)"
fi

# ── pick an install dir for the apps ─────────────────────────────────────────
if [[ -w /Applications ]]; then APPDIR="/Applications"; else APPDIR="${HOME}/Applications"; mkdir -p "$APPDIR"; fi
say "Installing apps to ${APPDIR}"

# ── 3. Dock app (AppleScript) ────────────────────────────────────────────────
DOCK="$APPDIR/Clinj.app"
rm -rf "$DOCK"
osacompile -o "$DOCK" "$SRC/app/Clinj.applescript"
[[ -f "$ICNS" ]] && cp "$ICNS" "$DOCK/Contents/Resources/applet.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.frameless.clinj" "$DOCK/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep -s - "$DOCK" 2>/dev/null || true
touch "$DOCK"
say "Built Clinj.app (Dock)"

# ── 4. Menu-bar app (Swift) ──────────────────────────────────────────────────
TMP_BUILD="$(mktemp -d)"; EXE="$TMP_BUILD/clinj-menubar"
if swiftc -O "$SRC/app/MenuBar.swift" -o "$EXE" 2>"$TMP_BUILD/swift.log"; then
    MENU="$APPDIR/Clinj Menu.app"
    rm -rf "$MENU"
    mkdir -p "$MENU/Contents/MacOS" "$MENU/Contents/Resources"
    cp "$EXE" "$MENU/Contents/MacOS/clinj-menubar"
    [[ -f "$ICNS" ]] && cp "$ICNS" "$MENU/Contents/Resources/clinj.icns"
    cat > "$MENU/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Clinj Menu</string>
    <key>CFBundleDisplayName</key><string>Clinj Menu</string>
    <key>CFBundleIdentifier</key><string>com.frameless.clinj.menubar</string>
    <key>CFBundleExecutable</key><string>clinj-menubar</string>
    <key>CFBundleIconFile</key><string>clinj.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PLIST
    codesign --force --deep -s - "$MENU" 2>/dev/null || true
    touch "$MENU"
    say "Built Clinj Menu.app (menu bar)"

    # login agent for the menu-bar app
    MB_LABEL="com.frameless.clinj.menubar"
    MB_PLIST="${HOME}/Library/LaunchAgents/${MB_LABEL}.plist"
    cat > "$MB_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>${MB_LABEL}</string>
    <key>ProgramArguments</key><array>
        <string>${MENU}/Contents/MacOS/clinj-menubar</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict></plist>
PLIST
    launchctl bootout "gui/$(id -u)/${MB_LABEL}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$MB_PLIST" 2>/dev/null || launchctl load "$MB_PLIST" 2>/dev/null || true
    open "$MENU" 2>/dev/null || true
    say "Menu-bar app set to launch at login (and started now)"
else
    say "⚠️  Menu-bar build failed — see $TMP_BUILD/swift.log (Dock app still works)"
fi

# ── 5. auto-run schedule ─────────────────────────────────────────────────────
WHEN="$(grep -E '^CLINJ_SCHEDULE=' "$HOME_CLINJ/etc/clinj.conf" 2>/dev/null | head -1 | cut -d= -f2 | tr -dc 'a-z0-9')"
[[ -z "$WHEN" ]] && WHEN="daily"
bash "$HOME_CLINJ/bin/schedule.sh" "$WHEN" >/dev/null && say "Auto-run schedule: $WHEN"

# ── 6. optional password-free purge ──────────────────────────────────────────
if $ENABLE_PURGE; then
    RULE="$(id -un) ALL=(root) NOPASSWD: /usr/sbin/purge"
    echo "$RULE" | sudo tee /etc/sudoers.d/clinj >/dev/null && sudo chmod 0440 /etc/sudoers.d/clinj
    if sudo visudo -cf /etc/sudoers.d/clinj >/dev/null 2>&1; then
        say "Enabled password-free RAM purge (/etc/sudoers.d/clinj)"
    else
        sudo rm -f /etc/sudoers.d/clinj; say "⚠️ sudoers rule invalid — removed; purge will keep prompting"
    fi
fi

# ── 7. retire the old cleanup-mac setup ──────────────────────────────────────
launchctl bootout "gui/$(id -u)/com.frameless.cleanup-mac" 2>/dev/null || true
if [[ -f "${HOME}/cleanup-mac.sh" ]]; then
    cp "${HOME}/cleanup-mac.sh" "$HOME_CLINJ/backup/cleanup-mac.sh.bak" 2>/dev/null || true
    rm -f "${HOME}/cleanup-mac.sh"
    say "Removed old ~/cleanup-mac.sh (backup at ~/.clinj/backup/)"
fi
rm -f "${HOME}/Library/LaunchAgents/com.frameless.cleanup-mac.plist"
rm -f "${HOME}"/Library/Logs/cleanup-mac*.log
say "Retired old com.frameless.cleanup-mac LaunchAgent"

# ── 8. clear quarantine so Gatekeeper opens the apps cleanly ─────────────────
xattr -dr com.apple.quarantine "$DOCK" 2>/dev/null || true
[[ -d "$APPDIR/Clinj Menu.app" ]] && xattr -dr com.apple.quarantine "$APPDIR/Clinj Menu.app" 2>/dev/null || true

echo ""
echo "✅ Clinj installed."
echo "   • Dock app:   $DOCK   (double-click, or drag to your Dock)"
echo "   • Menu bar:   look for the 🧼 icon (top-right)"
echo "   • Engine:     ~/.clinj/bin/clinj.sh   (run with --scan / --dry-run anytime)"
echo "   • Schedule:   $WHEN  — change it from either app's menu"
echo "   • Uninstall:  bash \"$SRC/uninstall.sh\""
