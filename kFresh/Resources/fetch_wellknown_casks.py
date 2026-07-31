#!/usr/bin/env python3
"""Fetch the well-known cask list and merge them into cask_rules.json.

This is a small companion to fetch_cask_rules.sh: the positional LIMIT of 1500
casks covers most installed apps, but the verification step in
docs/design/bundle-id-source.md requires the 10 most-popular macOS apps to be
present regardless of where they sort alphabetically.

Usage:
    python3 fetch_wellknown_casks.py [path/to/cask_rules.json] [path/to/output]
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

WELL_KNOWN_CASKS = [
    "visual-studio-code", "iterm2", "google-chrome", "firefox", "slack",
    "discord", "notion", "figma", "postman", "spotify",
]

DEFAULT_INPUT = os.path.join(os.path.dirname(__file__), "cask_rules.json")
DEFAULT_OUTPUT = DEFAULT_INPUT


def fetch_cask_ruby(token: str) -> str | None:
    url = (
        f"https://raw.githubusercontent.com/Homebrew/homebrew-cask/"
        f"master/Casks/{token[0]}/{token}.rb"
    )
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return resp.read().decode("utf-8", errors="ignore")
    except Exception:
        return None


def parse_zap(token: str, ruby: str) -> dict | None:
    m = re.search(r"zap\s+trash:\s*\[(.*?)\]", ruby, re.DOTALL)
    if not m:
        return None
    paths = re.findall(r'"([^"]+)"', m.group(1))
    return {
        "bundleID": token,
        "appName": token,
        "residuePaths": [p for p in paths if p.startswith("~/")],
        "systemLevelPaths": [p for p in paths if not p.startswith("~/")],
        "zapStanzas": [ruby[:500]],
        "confidence": 0.85,
        "source": "homebrew-cask",
    }


def main() -> int:
    input_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path

    if os.path.exists(input_path):
        with open(input_path) as f:
            rules = json.load(f)
    else:
        rules = []

    existing = {r["appName"] for r in rules}
    added = 0
    for token in WELL_KNOWN_CASKS:
        if token in existing:
            continue
        ruby = fetch_cask_ruby(token)
        if not ruby:
            print(f"  ! could not fetch {token}", file=sys.stderr)
            continue
        rule = parse_zap(token, ruby)
        if rule:
            rules.append(rule)
            added += 1
            print(f"  + {token}", file=sys.stderr)

    with open(output_path, "w") as f:
        json.dump(rules, f, indent=2)

    print(f"Merged {added} well-known casks; total now {len(rules)} rules -> {output_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())