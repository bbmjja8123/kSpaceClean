#!/bin/bash
# Usage: ./version-bump.sh <new-version> [build-number]
# Updates Klaris (kWise) version in kWise/project.yml (XcodeGen source of
# truth) and regenerates the Xcode project via kWise/scripts/generate.sh.
# Every App Store upload needs a fresh build number.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="$ROOT/kWise/project.yml"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <new-version> [build-number]"
    echo "Example: $0 1.6.0 2"
    exit 1
fi

NEW_VERSION=$1
NEW_BUILD=${2:-}

# Validate version format
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Version must be in format X.Y.Z"
    exit 1
fi

if [ ! -f "$PROJECT_YML" ]; then
    echo "Error: $PROJECT_YML not found"
    exit 1
fi

sed -i '' "s/^    MARKETING_VERSION: \".*\"/    MARKETING_VERSION: \"$NEW_VERSION\"/" "$PROJECT_YML"
echo "Updated MARKETING_VERSION to $NEW_VERSION in kWise/project.yml"

if [ -n "$NEW_BUILD" ]; then
    if ! echo "$NEW_BUILD" | grep -qE '^[0-9]+$'; then
        echo "Error: Build number must be an integer"
        exit 1
    fi
    sed -i '' "s/^    CURRENT_PROJECT_VERSION: \".*\"/    CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJECT_YML"
    echo "Updated CURRENT_PROJECT_VERSION to $NEW_BUILD"
fi

grep -nE 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' "$PROJECT_YML"

# Regenerate the Xcode project so the new version lands in the pbxproj.
"$ROOT/kWise/scripts/generate.sh"

echo "Done. Commit kWise/project.yml + kWise.xcodeproj together."
