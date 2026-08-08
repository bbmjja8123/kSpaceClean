#!/usr/bin/env bash
# new-worktree.sh — create a per-app worktree at the canonical sibling path.
#
# Usage:
#   scripts/new-worktree.sh <app>
#
# Bootstraps a fresh per-app worktree at:
#   /Users/torsys/Documents/aicoding/<app>
# on branch worktree-<app-lowercase>-v1, tracking origin.
#
# Use this when:
#   - setting up a new machine
#   - recreating a worktree after accidental `git worktree remove`
#   - onboarding a new collaborator

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <app>" >&2
    echo "  app: kWise | kWatch | kSift | kFresh" >&2
    exit 64
fi

APP="$1"

case "$APP" in
    kWise|kWatch|kSift|kFresh) ;;
    *) echo "error: app must be kWise | kWatch | kSift | kFresh (got '$APP')" >&2; exit 65 ;;
esac

LOWER=$(echo "$APP" | tr '[:upper:]' '[:lower:]')
BRANCH="worktree-${LOWER}-v1"
WT_PATH="/Users/torsys/Documents/aicoding/${APP}"

# Pre-flight: source repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: must run from inside the Kraftly git repo" >&2
    exit 66
fi

# Pre-flight: target path absent
if [[ -e "$WT_PATH" ]]; then
    echo "error: $WT_PATH already exists — remove it first if you want to recreate" >&2
    exit 67
fi

# Pre-flight: branch tracking
if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    echo "new-worktree: origin/$BRANCH exists — creating local branch + worktree"
else
    echo "new-worktree: origin/$BRANCH missing — creating local branch from main"
    git branch "$BRANCH" main
    git push -u origin "$BRANCH"
fi

git worktree add "$WT_PATH" "$BRANCH"

echo
echo "new-worktree: DONE — worktree at $WT_PATH on branch $BRANCH"
echo
echo "next steps:"
echo "  cd $WT_PATH"
echo "  ./scripts/commit-app.sh $APP --dry-run   # confirm boundary script works"