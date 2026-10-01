#!/bin/sh
# Regenerate the macOS asset catalog and ICNS from the master artwork.
set -eu
cd "$(dirname "$0")/.."
master="docs/design/cubelyze-icon.png"
catalog="Cubelyze/Assets.xcassets/AppIcon.appiconset"
iconset="build/Cubelyze.iconset"
mkdir -p "$catalog" "$iconset" Cubelyze/Resources
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""
    if [ "$scale" -eq 2 ]; then suffix="@2x"; fi
    filename="icon_${size}x${size}${suffix}.png"
    sips -z "$pixels" "$pixels" "$master" --out "$catalog/$filename" >/dev/null
    cp "$catalog/$filename" "$iconset/$filename"
  done
done
iconutil -c icns "$iconset" -o Cubelyze/Resources/AppIcon.icns
