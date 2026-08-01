#!/bin/bash
# Fetch Homebrew Cask zap rules and compile to JSON.
# Output: kFresh/Resources/cask_rules.json
set -euo pipefail

OUTPUT="${1:-./cask_rules.json}"
LIMIT="${2:-1500}"
PARALLEL="${3:-16}"
TMP=$(mktemp -d)

# Well-known casks that may live past the positional LIMIT; these are required
# by the verification step in docs/design/bundle-id-source.md.
KNOWN_CASKS=(
  "visual-studio-code" "iterm2" "google-chrome" "firefox" "slack"
  "discord" "notion" "figma" "postman" "spotify"
)

# Use Homebrew API to list all casks
curl -fsSL "https://formulae.brew.sh/api/cask.json" -o "$TMP/casks.json"

# Build list of cask tokens to process (token, first-letter directory)
python3 - "$TMP/casks.json" "$LIMIT" "$TMP/known.txt" "${KNOWN_CASKS[@]}" <<'PY' > "$TMP/jobs.txt"
import json, sys
path, limit = sys.argv[1], int(sys.argv[2])
known_out = sys.argv[3]
known = set(sys.argv[4:])

with open(path) as f:
    casks = json.load(f)

seen = set()
with open(known_out, "w") as f:
    pass  # placeholder; we append below

with open(known_out, "w") as fk:
    for k in sorted(known):
        fk.write(f"{k[0]}/{k}\n")

for cask in casks[:limit]:
    token = cask["token"]
    seen.add(token)
    print(f"{token[0]}/{token}")

# Append any well-known casks not already in the positional slice.
for k in sorted(known - seen):
    print(f"{k[0]}/{k}")
PY

# Fetch each cask ruby source in parallel and parse the zap stanza.
mkdir -p "$TMP/ruby"
fetch_one() {
    local rel="$1"
    local dir="${rel%%/*}"
    local token="${rel##*/}"
    local out="$TMP/ruby/${token}.rb"
    if curl -fsSL --max-time 10 "https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/${rel}.rb" -o "$out" 2>/dev/null; then
        echo "$out"
    fi
}
export -f fetch_one
export TMP

# xargs runs `fetch_one` for each line in jobs.txt with $PARALLEL workers.
xargs -n 1 -P "$PARALLEL" -I {} bash -c 'fetch_one "$@"' _ {} < "$TMP/jobs.txt" > "$TMP/fetched.txt"

# Aggregate zap stanzas into JSON.
#
# NOTE: The `zap trash: [...]` extraction regex below is duplicated in
# `fetch_wellknown_casks.py:parse_zap()`. Both scripts must parse the same
# ruby DSL shape — when one changes, change the other. A future refactor
# could extract a shared `extract_zap_stanzas.py` helper invoked from
# both shells (the bash script would simply call `python3
# extract_zap_stanzas.py <input> <output>`), but the bash→python boundary
# is awkward enough that we accept the duplication for now. If you fix a
# bug here, mirror the fix in the python script's `parse_zap`.
python3 - "$TMP/fetched.txt" "$OUTPUT" "$(dirname "$(readlink -f "$0")")" <<'PY'
import json, os, re, sys
import importlib.util
fetched_path, output_path, resources_dir = sys.argv[1], sys.argv[2], sys.argv[3]
_spec = importlib.util.spec_from_file_location(
    "extract_cask_bundle_id",
    os.path.join(resources_dir, "extract_cask_bundle_id.py"),
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
extract_bundle_id = _mod.extract_bundle_id

rules = []
for line in open(fetched_path):
    path = line.strip()
    if not path:
        continue
    token = path.rsplit("/", 1)[-1][:-3]  # strip .rb
    try:
        ruby = open(path).read()
    except Exception:
        continue
    m = re.search(r'zap\s+trash:\s*\[(.*?)\]', ruby, re.DOTALL)
    if not m:
        continue
    paths = re.findall(r'"([^"]+)"', m.group(1))
    bundle_id = extract_bundle_id(ruby, token)
    rules.append({
        "bundleID": bundle_id,
        "appName": token,
        "residuePaths": [p for p in paths if p.startswith("~/")],
        "systemLevelPaths": [p for p in paths if not p.startswith("~/")],
        "zapStanzas": [ruby[:500]],
        "confidence": 0.85,
        "source": "homebrew-cask"
    })

with open(output_path, "w") as f:
    json.dump(rules, f, indent=2)

print(f"Wrote {len(rules)} rules to {output_path}", file=sys.stderr)
PY

rm -rf "$TMP"
echo "Wrote $OUTPUT"