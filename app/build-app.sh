#!/usr/bin/env bash
# build-app.sh — compile the SwiftUI app into a self-contained Clinj.app
# (the clinj engine is bundled inside, so the app needs nothing else installed).
#   bash app/build-app.sh            → builds dist/Clinj.app
#   bash app/build-app.sh --install  → also copies it to /Applications (or ~/Applications)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"; APP="$DIST/Clinj.app"; BUILD="$(mktemp -d)"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "• Compiling SwiftUI app…"
swiftc -O -parse-as-library "$ROOT/app/MainApp.swift" -o "$APP/Contents/MacOS/Clinj"

echo "• Bundling engine…"
cp -R "$ROOT/core" "$APP/Contents/Resources/core"
chmod +x "$APP/Contents/Resources/core/clinj.sh"

echo "• Generating icon…"
PNG="$BUILD/icon.png"; SET="$BUILD/clinj.iconset"; mkdir -p "$SET"
if swift "$ROOT/app/makeicon.swift" "$PNG" 2>/dev/null && [[ -f "$PNG" ]]; then
    for s in 16 32 128 256 512; do
        sips -z $s $s          "$PNG" --out "$SET/icon_${s}x${s}.png"      >/dev/null 2>&1
        sips -z $((s*2)) $((s*2)) "$PNG" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    sips -z 1024 1024 "$PNG" --out "$SET/icon_512x512@2x.png" >/dev/null 2>&1
    iconutil -c icns "$SET" -o "$APP/Contents/Resources/Clinj.icns" 2>/dev/null || true
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Clinj</string>
  <key>CFBundleDisplayName</key><string>Clinj</string>
  <key>CFBundleIdentifier</key><string>com.amirmlotfy.clinj</string>
  <key>CFBundleExecutable</key><string>Clinj</string>
  <key>CFBundleIconFile</key><string>Clinj</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>CFBundleVersion</key><string>2.0.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "✅ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    if [[ -w /Applications ]]; then DEST=/Applications; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
    rm -rf "$DEST/Clinj.app"; cp -R "$APP" "$DEST/"
    xattr -dr com.apple.quarantine "$DEST/Clinj.app" 2>/dev/null || true
    echo "✅ Installed to $DEST/Clinj.app"
fi
