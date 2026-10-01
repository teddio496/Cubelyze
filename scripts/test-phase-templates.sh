#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
xcrun swiftc -parse-as-library \
  -module-cache-path build/ModuleCache \
  Cubelyze/AnalysisModels.swift tests/PhaseTemplates.swift \
  -o build/phase-template-checks
build/phase-template-checks
