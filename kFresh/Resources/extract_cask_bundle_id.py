#!/usr/bin/env python3
"""Best-effort extraction of macOS bundle identifiers from Homebrew cask
ruby sources.

Real bundle IDs are reverse-DNS strings like `com.google.Chrome` or
`com.microsoft.VSCode`. The cask ruby source rarely contains the literal
`CFBundleIdentifier` (which lives in the installed app's Info.plist), but
it does mention the bundle ID in several stanzas:

- `uninstall quit: "com.example.app"` — bundle ID passed to `quit:`
- `zap launchctl: ["com.example.helper"]` — LaunchAgent / LaunchDaemon label
- `livecheck ... strategy :extract_plist do |items| items["com.example.app"]`
  — bundle ID keyed in a plist hash

We try those patterns first; if none match, we fall back to the cask
token. The token fallback preserves backwards compatibility with the
pre-fix JSON but, by construction, downstream `lookup(bundleID:)` will
miss the rule because the installed app's real bundle ID will not equal
the token (cask tokens permit hyphens, e.g. `010-editor`, `115browser`).

Used by both `fetch_cask_rules.sh` and `fetch_wellknown_casks.py`. Both
scripts must agree on the extraction contract — keep them in sync.
"""

import re


# `uninstall quit: "com.example.app"` — bundle ID passed to `quit:`.
# The uninstall stanza may span multiple lines, so we use DOTALL and
# allow arbitrary characters (excluding `#` for inline comments) between
# `uninstall` and `quit:`.
_UNINSTALL_QUIT_RE = re.compile(
    r'uninstall.*?\bquit:\s*"([^"]+)"',
    re.DOTALL,
)

# `zap launchctl: ["com.example.a", "com.example.b"]` (or single string)
_ZAP_LAUNCHCTL_RE = re.compile(r'zap\s+launchctl:\s*\[([^\]]*)\]', re.DOTALL)

# `livecheck ... items["com.example.app"]`
_LIVECHECK_ITEMS_RE = re.compile(r'items\["([^"]+)"\]')


def extract_bundle_id(ruby: str, token: str) -> str:
    """Return the best-effort bundle identifier for a cask ruby source.

    - Parameter ruby: Full text of the cask `.rb` file.
    - Parameter token: Cask token (e.g. `visual-studio-code`); used as the
      fallback when no real bundle ID is found in `ruby`.
    - Returns: The extracted bundle ID, or `token` if no signal was found.
    """
    # 1. uninstall quit: "..."
    m = _UNINSTALL_QUIT_RE.search(ruby)
    if m:
        return m.group(1)
    # 2. zap launchctl: ["com.example.a", "com.example.b"]  (or single string)
    m = _ZAP_LAUNCHCTL_RE.search(ruby)
    if m:
        ids = re.findall(r'"([^"]+)"', m.group(1))
        # Filter out plain agent names (no dots) — those are usually
        # user-mode launchd labels, not bundle IDs. Prefer ones that look
        # reverse-DNS.
        for candidate in ids:
            if candidate.count('.') >= 2:
                return candidate
        if ids:
            return ids[0]
    # 3. livecheck ... items["com.example.app"]
    m = _LIVECHECK_ITEMS_RE.search(ruby)
    if m:
        return m.group(1)
    # 4. fallback: token. Documented limitation.
    return token