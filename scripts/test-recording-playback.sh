#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" -module-cache-path build/ModuleCache \
  Cubelyze/AnalysisModels.swift Cubelyze/AnalysisStore.swift Cubelyze/IssueTags.swift \
  Cubelyze/VideoTrimStore.swift Cubelyze/PlaybackModel.swift Tests/RecordingPlaybackChecks.swift \
  -o build/recording-playback-checks
python3 scripts/recording-fixture.py build/recording-fixture.mov
build/recording-playback-checks build/recording-fixture.mov
