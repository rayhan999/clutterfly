#!/bin/zsh
# Builds "Clutterfly.app" next to this script. Run: ./build.sh
# ./build.sh release  → universal (Apple Silicon + Intel) build zipped as Clutterfly.zip, for GitHub Releases.
set -e
cd "${0:A:h}"
APP="Clutterfly.app"
VERSION="1.1.2"
SRC=(Clutterfly.swift Screens.swift Extras.swift System.swift)
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/"  # regenerate: see make_icon.swift
if [[ "$1" == release ]]; then
    T=$(mktemp -d)
    for a in arm64 x86_64; do swiftc -O -parse-as-library -target $a-apple-macos14 $SRC -o "$T/$a"; done
    lipo -create "$T/arm64" "$T/x86_64" -output "$APP/Contents/MacOS/Clutterfly"; rm -rf "$T"
else
    swiftc -O -parse-as-library $SRC -o "$APP/Contents/MacOS/Clutterfly"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Clutterfly</string>
<key>CFBundleIdentifier</key><string>local.clutterfly</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Clutterfly</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Hardened runtime: blocks DYLD_INSERT_LIBRARIES-style code injection, so nothing can borrow the app's Full Disk Access.
codesign -s - --force --options runtime "$APP"
echo "Built $APP"
if [[ "$1" == release ]]; then rm -f Clutterfly.zip; ditto -c -k --keepParent "$APP" Clutterfly.zip; echo "Zipped Clutterfly.zip"; fi

# Install into /Applications, restarting the app if it was open.
running=$(pgrep -x Clutterfly || true)
[[ -n "$running" ]] && { pkill -x Clutterfly; while pgrep -x Clutterfly >/dev/null; do sleep 0.2; done; }
rm -rf "/Applications/$APP" && ditto "$APP" "/Applications/$APP"
echo "Installed /Applications/$APP"
[[ -n "$running" ]] && { sleep 1; open "/Applications/$APP"; }
true
