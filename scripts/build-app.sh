#!/usr/bin/env bash
# Builds build/DNZ-Scenes.app (menu bar app, ad-hoc signed).
# Note: ad-hoc signing changes identity on each build, so macOS may ask you to
# re-grant the Accessibility permission after a rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DNZScenes"
APP="build/DNZ-Scenes.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/DNZScenes"
mkdir -p "$APP/Contents/Resources"
if [ -d assets/wallpapers ]; then
  cp -R assets/wallpapers "$APP/Contents/Resources/wallpapers"
else
  echo "Note: assets/wallpapers not found - building without bundled wallpapers (you can add images in the editor)."
fi

# App icon: build AppIcon.icns from the 1024 px master (needs macOS sips + iconutil).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.dnz.scenes</string>
  <key>CFBundleName</key><string>DNZ-Scenes</string>
  <key>CFBundleExecutable</key><string>DNZScenes</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.dnz.scenes</string>
    <key>CFBundleURLSchemes</key><array><string>dnzscenes</string></array>
  </dict></array>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"

# DNZ About metadata (core/standards/about-standard.md §3): build facts come from the build, never from source.
# Release builds: DNZ_CHANNEL=stable DNZ_ENVIRONMENT=production ./scripts/build-app.sh
PLB=/usr/libexec/PlistBuddy; PL="$APP/Contents/Info.plist"
set_plist() { "$PLB" -c "Set :$1 $2" "$PL" 2>/dev/null || "$PLB" -c "Add :$1 string $2" "$PL"; }
set_plist DNZCommit      "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
set_plist DNZReleaseDate "$(date -u +%Y-%m-%d)"
set_plist DNZChannel     "${DNZ_CHANNEL:-dev}"
set_plist DNZEnvironment "${DNZ_ENVIRONMENT:-development}"
cp app-info.json "$APP/Contents/Resources/app-info.json"

SIGN_ID="${SIGN_ID:--}"   # set SIGN_ID to a code signing identity name for a stable signature
codesign --force --options runtime --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
if [ "$SIGN_ID" = "-" ]; then
  echo "Signed ad-hoc. Accessibility permission will have to be granted again after every rebuild."
  echo "For a stable identity: SIGN_ID=\"Apple Development: Your Name (TEAMID)\" ./scripts/build-app.sh"
fi
echo "Built $APP"
echo "Run: open $APP"
