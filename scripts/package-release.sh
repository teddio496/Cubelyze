#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

version="${1:-0.1.0}"
case "$version" in
    *[!0-9A-Za-z.-]*|'')
        printf 'Invalid version: %s\n' "$version" >&2
        exit 1
        ;;
esac

sh scripts/build.sh
archive="build/Cubelyze-${version}-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent build/Cubelyze.app "$archive"
printf 'Packaged %s\n' "$archive"
printf 'This development archive is ad-hoc signed and not notarized.\n'
