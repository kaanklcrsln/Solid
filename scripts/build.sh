#!/bin/bash
# Builds SOLID.app (universal arm64 + x86_64) and SOLID.dmg into ./dist
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0"
APP="dist/SOLID.app"
rm -rf dist && mkdir -p dist

echo "==> Building arm64"
swift build -c release --triple arm64-apple-macosx13.0
echo "==> Building x86_64"
swift build -c release --triple x86_64-apple-macosx13.0

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  "$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/SOLID" \
  "$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/SOLID" \
  -output "$APP/Contents/MacOS/SOLID"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SOLID</string>
  <key>CFBundleDisplayName</key><string>SOLID</string>
  <key>CFBundleIdentifier</key><string>local.solid.cleaner</string>
  <key>CFBundleExecutable</key><string>SOLID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>SOLID macOS Cleaner. Local only.</string>
  <key>NSAppleEventsUsageDescription</key><string>SOLID asks Finder to empty the Trash and uses the macOS administrator prompt only when you confirm such an operation.</string>
</dict>
</plist>
PLIST

echo "==> Icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SOLID" -srcfolder "$STAGE" -ov -format UDZO "dist/SOLID-${VERSION}.dmg" >/dev/null

lipo -info "$APP/Contents/MacOS/SOLID"
du -sh "$APP" "dist/SOLID-${VERSION}.dmg"
echo "Done."
