#!/bin/bash
set -euo pipefail
version=${1:?Usage: scripts/release.sh VERSION BUILD_NUMBER}
build_number=${2:?Usage: scripts/release.sh VERSION BUILD_NUMBER}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ $build_number =~ ^[1-9][0-9]*$ ]] || exit 1
cd "$(dirname "$0")/.."
mkdir -p build/release
xcodebuild -project Cubelyze.xcodeproj -scheme Cubelyze -configuration Release \
  -derivedDataPath "$PWD/build/release/DerivedData" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO build
app="$PWD/build/release/Cubelyze.app"
ditto "$PWD/build/release/DerivedData/Build/Products/Release/Cubelyze.app" "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
zip="$PWD/build/release/Cubelyze-${version}-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
staging="$PWD/build/release/dmg-staging"
mkdir -p "$staging"
ditto "$app" "$staging/Cubelyze.app"
ln -s /Applications "$staging/Applications"
dmg="$PWD/build/release/Cubelyze-${version}-macOS.dmg"
hdiutil create -volname Cubelyze -srcfolder "$staging" -format UDZO -ov "$dmg"
shasum -a 256 "$dmg" "$zip" > "$PWD/build/release/SHA256SUMS.txt"
