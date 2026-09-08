#!/usr/bin/env bash
# Regenerate kWise.xcodeproj from project.yml and verify it is in sync with git.
# CI gate: a non-zero diff after generation means project.yml changed without
# regenerating, or the pbxproj was hand-edited.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || {
  echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
}

xcodegen generate

if git diff --exit-code -- kWise.xcodeproj >/dev/null 2>&1; then
  echo "✅ kWise.xcodeproj is in sync with project.yml"
else
  echo "⚠️  kWise.xcodeproj changed after regeneration — commit the updated project file."
  git diff --stat -- kWise.xcodeproj
  exit 2
fi
