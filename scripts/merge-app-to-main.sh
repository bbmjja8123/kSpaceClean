#!/usr/bin/env bash
# merge-app-to-main.sh — merge an app worktree branch back into main.
#
# Usage:
#   scripts/merge-app-to-main.sh <app> [--squash|--no-ff|--ff-only]
#   scripts/merge-app-to-main.sh <app> --abort
#
# Run from the MAIN worktree (kSpaceClean/, on main). Defaults to
# --no-ff merge so the per-app branch's history is preserved.
#
# Side effects:
#   - fetches origin/<branch>
#   - merges origin/<branch> into main
#   - pushes main to origin
#   - returns 0 on success, non-zero on conflict (user must resolve)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <app> [--squash|--no-ff|--ff-only] [--abort]" >&2
    exit 64
fi

APP="$1"; shift

case "$APP" in
    kWise|kWatch|kSift|kFresh) ;;
    *) echo "error: app must be one of: kWise | kWatch | kSift | kFresh" >&2; exit 65 ;;
esac

BRANCH="worktree-${APP,,}-v1"

STRATEGY="--no-ff"
ABORT=0
for arg in "$@"; do
    case "$arg" in
        --squash)   STRATEGY="--squash" ;;
        --no-ff)    STRATEGY="--no-ff" ;;
        --ff-only)  STRATEGY="--ff-only" ;;
        --abort)    ABORT=1 ;;
        -*)         echo "unknown flag: $arg" >&2; exit 64 ;;
        *)          echo "unexpected positional: $arg" >&2; exit 64 ;;
    esac
done

# Must run from main worktree on main branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" != "main" ]]; then
    echo "error: must run on main branch (currently on '$current_branch')" >&2
    echo "  cd to /Users/torsys/Documents/aicoding/kSpaceClean" >&2
    exit 67
fi

if [[ $ABORT -eq 1 ]]; then
    if [[ -f .git/MERGE_HEAD ]]; then
        git merge --abort
        echo "merge-app-to-main: aborted in-progress merge"
    else
        echo "merge-app-to-main: no merge in progress"
    fi
    exit 0
fi

# Working tree must be clean
if ! git diff --quiet HEAD 2>/dev/null; then
    echo "error: working tree has unstaged changes — commit or stash first" >&2
    exit 68
fi

echo "merge-app-to-main: fetching $BRANCH..."
git fetch origin "$BRANCH"

echo "merge-app-to-main: merging origin/$BRANCH $STRATEGY into main..."
if ! git merge $STRATEGY "origin/$BRANCH" -m "merge: $APP branch into main

Brings worktree-$APP-v1 changes into main via $(echo $STRATEGY | tr -d '-') merge.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"; then
    echo
    echo "merge-app-to-main: CONFLICT — resolve and commit, then run:"
    echo "  git push origin main"
    exit 69
fi

echo "merge-app-to-main: pushing main to origin..."
git push origin main

echo
echo "merge-app-to-main: DONE — $BRANCH merged into main and pushed."
echo "  other worktrees should now run: git pull origin main"