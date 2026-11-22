#!/bin/zsh
# Builds "Molehill.app" next to this script. Run: ./build.sh
set -e
cd "${0:A:h}"
APP="Molehill.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/"  # regenerate: see make_icon.swift
swiftc -O -parse-as-library Molehill.swift Screens.swift Extras.swift System.swift -o "$APP/Contents/MacOS/Molehill"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Molehill</string>
<key>CFBundleIdentifier</key><string>local.molehill</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Molehill</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
