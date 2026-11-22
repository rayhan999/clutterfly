#!/bin/zsh
# Builds "Molehill.app" next to this script. Run: ./build.sh
# ./build.sh release  → universal (Apple Silicon + Intel) build zipped as Molehill.zip, for GitHub Releases.
set -e
cd "${0:A:h}"
APP="Molehill.app"
VERSION="1.0"
SRC=(Molehill.swift Screens.swift Extras.swift System.swift)
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/"  # regenerate: see make_icon.swift
if [[ "$1" == release ]]; then
    T=$(mktemp -d)
    for a in arm64 x86_64; do swiftc -O -parse-as-library -target $a-apple-macos14 $SRC -o "$T/$a"; done
    lipo -create "$T/arm64" "$T/x86_64" -output "$APP/Contents/MacOS/Molehill"; rm -rf "$T"
else
    swiftc -O -parse-as-library $SRC -o "$APP/Contents/MacOS/Molehill"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Molehill</string>
<key>CFBundleIdentifier</key><string>local.molehill</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Molehill</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
if [[ "$1" == release ]]; then rm -f Molehill.zip; ditto -c -k --keepParent "$APP" Molehill.zip; echo "Zipped Molehill.zip"; fi
