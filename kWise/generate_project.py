#!/usr/bin/env python3
"""DEPRECATED — superseded by project.yml + XcodeGen.

Run `scripts/generate.sh` (requires `brew install xcodegen`) to regenerate
kWise.xcodeproj. This stub remains only so stale references produce an
explicit error instead of silently writing an obsolete project file.
"""

import sys

sys.exit(
    "generate_project.py is superseded by project.yml + XcodeGen.\n"
    "Run: scripts/generate.sh"
)
