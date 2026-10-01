#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
xcrun swiftc -parse-as-library \
  -module-cache-path build/ModuleCache \
  Cubelyze/AnalysisModels.swift Cubelyze/IssueTags.swift Tests/IssueTagChecks.swift \
  -o build/issue-tag-checks
build/issue-tag-checks
