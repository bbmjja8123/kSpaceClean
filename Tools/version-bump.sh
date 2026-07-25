#!/bin/bash
# Usage: ./version-bump.sh <new-version>
# Updates kSpaceClean version in Info.plist

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <new-version>"
    echo "Example: $0 1.1.0"
    exit 1
fi

NEW_VERSION=$1
INFO_PLIST="kSpaceClean/Info.plist"

if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: $INFO_PLIST not found"
    exit 1
fi

# Validate version format
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Version must be in format X.Y.Z"
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
echo "Updated version to $NEW_VERSION in $INFO_PLIST"
