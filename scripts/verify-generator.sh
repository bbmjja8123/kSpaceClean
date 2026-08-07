#!/usr/bin/env bash
# scripts/verify-generator.sh
#
# CI guard for kSpaceClean/generate_project.py — fails the build if the
# generator's `swift_files` / `test_files` registration lists have drifted
# out of sync with the actual Swift sources on disk.
#
# Why this exists
# ---------------
# `generate_project.py` hand-writes the `project.pbxproj` from in-script
# lists. New Swift files are easy to add to the project tree but easy to
# forget to register — when forgotten, the file is silently excluded from
# the target's compile phase and lives as "dead code" (this has already
# happened at least once: A5 added `CascadeCheckboxTests.swift` and A12
# added `ToolbarView.swift` + `KeyboardShortcuts.swift` without
# registering them; A13 surfaced the gap and fixed part of it).
#
# This script makes the drift impossible to land:
#
#     $ ./scripts/verify-generator.sh
#     kSpaceClean generator drift check ... OK
#     kSpaceClean generator drift check ... FAILED  (exit 1)
#
# Usage
# -----
# Local:   ./scripts/verify-generator.sh
# CI:      ./scripts/verify-generator.sh --strict
#
# Modes
# -----
# Default: prints the diff (added / removed) for each list and exits
#          non-zero if either side differs.
#
# --strict: same, but also refuses to silently "fix" anything. The script
#          never modifies the generator — that's the human author's job.
#
# Exit codes
# ----------
#   0 — generator lists match on-disk Swift files
#   1 — drift detected (one or more files added/removed)
#   2 — generator script missing or not executable
#
# Implementation
# --------------
# The script extracts the registered paths by parsing
# `generate_project.py`:
#   - `swift_files` entries are tuples like
#     `("App/RootView.swift", "App")` — first string is the relative path.
#   - `test_files` entries are bare filenames like `"SnapshotTestCase.swift"`
#     that are implicitly rooted under `Tests/`.
#
# The on-disk truth is the `find` of all `*.swift` files under
# `kSpaceClean/`, excluding `kSpaceClean/build/` and the `.xcodeproj/`
# bundle.
#
# The two lists are sorted and diffed with `comm`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATOR="$REPO_ROOT/kSpaceClean/generate_project.py"
TARGET_DIR="$REPO_ROOT/kSpaceClean"

if [[ ! -f "$GENERATOR" ]]; then
  echo "ERROR: generator not found at $GENERATOR" >&2
  exit 2
fi

STRICT=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --help|-h)
      sed -n '3,55p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

WORK="$(mktemp -d -t kspc-gen-drift.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1) Generator-registered main swift files
#    Match lines like:        ("App/RootView.swift", "App"),
#    Extract the first quoted string from the line.
awk '
  /swift_files = /  { in_main=1; next }
  in_main && /^[[:space:]]*]/ { in_main=0; next }
  in_main && /^[[:space:]]*\(/  {
    line=$0
    # Drop the leading (" prefix, then stop at the next quote.
    sub(/^[[:space:]]*\("/, "", line)
    sub(/".*$/, "", line)
    if (line != "") print line
  }
' "$GENERATOR" | sort > "$WORK/gen_main.txt"

# 2) Generator-registered test swift files
#    Match lines like:        "SnapshotTestCase.swift",
#    The generator stores these as bare filenames; the project groups them
#    under `Tests/`, so we add the prefix on read.
awk '
  /test_files = /   { in_test=1; next }
  in_test && /^[[:space:]]*]/ { in_test=0; next }
  in_test && /^[[:space:]]*"/ {
    line=$0
    sub(/^[[:space:]]*"/, "", line)
    sub(/",?[[:space:]]*$/, "", line)
    if (line != "" && line !~ /^#/) print "Tests/" line
  }
' "$GENERATOR" | sort > "$WORK/gen_test.txt"

# 3) On-disk main swift files (everything except Tests/ and build artefacts)
#    `find` prints paths relative to `$REPO_ROOT`; strip the leading
#    `kSpaceClean/` segment so the paths match the generator's
#    `("App/RootView.swift", ...)` format.
( cd "$REPO_ROOT" \
    && find kSpaceClean \
         \( -path 'kSpaceClean/Tests' -o -path 'kSpaceClean/build' -o -path 'kSpaceClean/kSpaceClean.xcodeproj' \) -prune \
         -o -name '*.swift' -print \
  ) | sed 's|^kSpaceClean/||' | sort > "$WORK/disk_main.txt"

# 4) On-disk test swift files
( cd "$REPO_ROOT" \
    && find kSpaceClean/Tests -name '*.swift' -print \
  ) | sed 's|^kSpaceClean/||' | sort > "$WORK/disk_test.txt"

fail=0

echo "kSpaceClean generator drift check"
echo "----------------------------------"

# Main sources
echo
echo "[main sources]"
if diff -u "$WORK/gen_main.txt" "$WORK/disk_main.txt" > "$WORK/main.diff"; then
  echo "  OK ($(wc -l < "$WORK/gen_main.txt" | tr -d ' ') files match)"
else
  echo "  FAILED — generator and on-disk list differ:"
  sed 's/^/    /' "$WORK/main.diff"
  echo
  echo "  Generator-only (registered but missing on disk):"
  comm -23 "$WORK/gen_main.txt" "$WORK/disk_main.txt" | sed 's/^/    - /' || true
  echo "  Disk-only (on disk but NOT registered):"
  comm -13 "$WORK/gen_main.txt" "$WORK/disk_main.txt" | sed 's/^/    + /' || true
  fail=1
fi

# Test sources
echo
echo "[test sources]"
if diff -u "$WORK/gen_test.txt" "$WORK/disk_test.txt" > "$WORK/test.diff"; then
  echo "  OK ($(wc -l < "$WORK/gen_test.txt" | tr -d ' ') files match)"
else
  echo "  FAILED — generator and on-disk list differ:"
  sed 's/^/    /' "$WORK/test.diff"
  echo
  echo "  Generator-only (registered but missing on disk):"
  comm -23 "$WORK/gen_test.txt" "$WORK/disk_test.txt" | sed 's/^/    - /' || true
  echo "  Disk-only (on disk but NOT registered):"
  comm -13 "$WORK/gen_test.txt" "$WORK/disk_test.txt" | sed 's/^/    + /' || true
  fail=1
fi

echo
if [[ $fail -ne 0 ]]; then
  echo "RESULT: DRIFT DETECTED — please update generate_project.py and run:"
  echo "        python3 kSpaceClean/generate_project.py"
  echo "        to regenerate project.pbxproj."
  exit 1
fi

echo "RESULT: OK — generator lists match on-disk Swift files."
exit 0