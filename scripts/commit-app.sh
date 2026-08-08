#!/usr/bin/env bash
# commit-app.sh — boundary-safe git add for per-app worktrees.
#
# Usage:
#   scripts/commit-app.sh <app> [--dry-run] [--allow-kfoundation]
#   scripts/commit-app.sh <app> <file>...   # explicit paths
#
# Enforces the strict-boundary convention: only paths under the app's
# own directory may be staged. kFoundation additions require an explicit
# --allow-kfoundation flag and trigger a review warning.
#
# Examples:
#   scripts/commit-app.sh kWise
#       # stages all modified files under kWise/
#   scripts/commit-app.sh kWise --dry-run
#       # prints what would be staged without actually staging
#   scripts/commit-app.sh kWise kWise/App/NewView.swift
#       # stages the explicit path only (still validates it lives under kWise/)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <app> [--dry-run] [--allow-kfoundation] [path...]" >&2
    exit 64
fi

APP="$1"; shift
DRY_RUN=0
ALLOW_KFOUNDATION=0
EXPLICIT_PATHS=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)              DRY_RUN=1 ;;
        --allow-kfoundation)    ALLOW_KFOUNDATION=1 ;;
        -*)                     echo "unknown flag: $arg" >&2; exit 64 ;;
        *)                      EXPLICIT_PATHS+=("$arg") ;;
    esac
done

case "$APP" in
    kWise|kWatch|kSift|kFresh) ;;
    *)
        echo "error: app must be one of: kWise | kWatch | kSift | kFresh (got '$APP')" >&2
        exit 65
        ;;
esac

# Discover candidates. If explicit paths given, use those. Otherwise use
# `git status --porcelain` and filter to the app's directory.
if [[ ${#EXPLICIT_PATHS[@]} -gt 0 ]]; then
    CANDIDATES=("${EXPLICIT_PATHS[@]}")
else
    mapfile -t CANDIDATES < <(git status --porcelain | awk '{print $2}')
fi

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "commit-app: nothing to stage" >&2
    exit 0
fi

ALLOWED=()
REJECTED=()
KFOUNDATION_TOUCHED=0

for path in "${CANDIDATES[@]}"; do
    # Strip leading rename markers (R / C) if any leaked in.
    clean="${path#?? }"

    case "$clean" in
        "$APP"/?*)        ALLOWED+=("$clean") ;;
        kFoundation/?*)
            if [[ $ALLOW_KFOUNDATION -eq 1 ]]; then
                ALLOWED+=("$clean")
                KFOUNDATION_TOUCHED=1
            else
                REJECTED+=("$clean")
            fi
            ;;
        *)
            REJECTED+=("$clean")
            ;;
    esac
done

if [[ ${#REJECTED[@]} -gt 0 ]]; then
    echo "commit-app: refusing to stage paths outside $APP/" >&2
    for r in "${REJECTED[@]}"; do
        echo "  - $r" >&2
    done
    echo >&2
    echo "  these cross the per-app boundary. If intentional:" >&2
    echo "    - move them to $APP/ first" >&2
    echo "    - or split into a separate commit on the appropriate app branch" >&2
    echo "    - or pass --allow-kfoundation for kFoundation/ paths (still warns)" >&2
    exit 66
fi

if [[ ${#ALLOWED[@]} -eq 0 ]]; then
    echo "commit-app: no in-scope paths to stage" >&2
    exit 0
fi

if [[ $KFOUNDATION_TOUCHED -eq 1 ]]; then
    echo "commit-app: WARNING — staging kFoundation/ paths." >&2
    echo "  kFoundation is shared across all 4 apps. Coordinate before merge:" >&2
    echo "    1. commit on your app branch" >&2
    echo "    2. merge to main FIRST (so other apps see the change)" >&2
    echo "    3. other worktrees pull main and rebuild" >&2
    echo >&2
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "commit-app (dry-run) — would add:" >&2
    for p in "${ALLOWED[@]}"; do
        echo "  + $p" >&2
    done
    exit 0
fi

git add -- "${ALLOWED[@]}"
echo "commit-app: staged ${#ALLOWED[@]} path(s) under $APP/" >&2
git status --short