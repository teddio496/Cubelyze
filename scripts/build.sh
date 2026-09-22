#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

app="build/Cubelyze.app"
mkdir -p "$app/Contents/MacOS" build/ModuleCache
xcrun swiftc -parse-as-library -O \
  -Xlinker -no_adhoc_codesign \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path build/ModuleCache \
  Cubelyze/*.swift -o "$app/Contents/MacOS/Cubelyze"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Cubelyze</string>
    <key>CFBundleIdentifier</key><string>com.cubelyze.Cubelyze</string>
    <key>CFBundleName</key><string>Cubelyze</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
