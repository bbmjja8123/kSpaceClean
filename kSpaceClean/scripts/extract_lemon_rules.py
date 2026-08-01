#!/usr/bin/env python3
"""Re-extract Lemon cleaning-rule XML into bundleIDMapping.json preserving
item -> action(title) -> path triples, bilingual (zh-Hans + en).

Source XML files:
  /Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/garbage.xml         (system)
  .../zh-Hans.lproj/garbage1.xml            (app + system, zh-Hans titles)
  .../en.lproj/garbage_appstore.xml         (app + system, en titles)

Output: kSpaceClean/Resources/bundleIDMapping.json (overwrites, preserves manual apps if --preserve-manual).

Usage:
  python3 extract_lemon_rules.py
  python3 extract_lemon_rules.py --preserve-manual
"""
import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LEMON_BASE = Path("/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner")
ZH_XML = LEMON_BASE / "zh-Hans.lproj" / "garbage1.xml"
EN_XML = LEMON_BASE / "en.lproj" / "garbage_appstore.xml"
SYSTEM_XML = LEMON_BASE / "garbage.xml"
OUTPUT = Path(__file__).resolve().parents[1] / "Resources" / "bundleIDMapping.json"


def text_of(elem):
    return (elem.text or "").strip() if elem is not None else ""


def parse_xml(path: Path):
    """Parse a Lemon XML and return list of (bundleID, item_title, [(action_title, [paths])])."""
    tree = ET.parse(path)
    root = tree.getroot()
    items = []
    for category in root.findall("category"):
        for item in category.findall("item"):
            bundle_id = item.get("bundleid")
            if not bundle_id:
                continue
            item_title = text_of(item.find("title"))
            actions = []
            for action in item.findall("action"):
                action_title = text_of(action.find("title"))
                paths = []
                for p in action.findall("path"):
                    v = p.get("value", "")
                    if v.startswith("~/") or v.startswith("/"):
                        paths.append(v)
                if action_title and paths:
                    actions.append({"name": action_title, "paths": paths})
            if item_title and actions:
                items.append({
                    "bundleID": bundle_id,
                    "appstoreBundleID": item.get("appstorebundleid"),
                    "itemTitle": item_title,
                    "actions": actions,
                })
    return items


def merge(zh_items, en_items):
    """Merge zh-Hans and en items by bundleID. Each app gets bilingual action titles."""
    en_by_id = {x["bundleID"]: x for x in en_items}
    merged = {}
    for zh in zh_items:
        bid = zh["bundleID"]
        en = en_by_id.get(bid, {})
        en_action_titles = {a["name"]: a["paths"] for a in en.get("actions", [])}
        actions_out = []
        for zh_action in zh["actions"]:
            zh_title = zh_action["name"]
            paths = zh_action["paths"]
            # Try to find an en title by path overlap (same paths = same action)
            en_title = None
            for en_a in en.get("actions", []):
                if set(en_a["paths"]) & set(paths):
                    en_title = en_a["name"]
                    break
            actions_out.append({
                "nameCN": zh_title,
                "name": en_title or _pinyinize(zh_title),  # fallback
                "paths": paths,
            })
        merged[bid] = {
            "bundleID": bid,
            "appstoreBundleID": zh.get("appstoreBundleID") or en.get("appstoreBundleID"),
            "nameCN": zh["itemTitle"],
            "name": en.get("itemTitle", zh["itemTitle"]),
            "actions": actions_out,
            "vendor": _vendor_from_bundle_id(bid),
            "type": _type_from_bundle_id(bid),
            "riskLevel": "recommended",
            "confidence": "high",
        }
    return merged


def _pinyinize(zh_title):
    """Fallback: keep Chinese title in `name` field when no en match found."""
    return zh_title  # UI will fall back to nameCN if name == nameCN


def _vendor_from_bundle_id(bid):
    parts = bid.split(".")
    if len(parts) >= 3 and parts[0] == "com":
        return parts[1].capitalize()
    return parts[0].capitalize() if parts else "Unknown"


def _type_from_bundle_id(bid):
    design = {"adobe", "sketch", "figma", "affinity"}
    dev = {"apple", "microsoft", "google", "jetbrains", "github", "docker", "orbstack"}
    chat = {"tencent", "slack", "discord", "telegram", "zoom"}
    browser = {"google", "mozilla", "brave", "arc"}
    browser_set = {"Chrome", "Firefox", "Brave", "Arc", "Edge", "Safari", "Opera", "Vivaldi"}
    if any(v in bid for v in dev):
        return "developer"
    if any(v in bid for v in chat):
        return "communication"
    return "general"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preserve-manual", action="store_true",
                        help="Preserve manually-added apps not present in Lemon XML")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()

    print(f"Reading {ZH_XML} ...")
    zh = parse_xml(ZH_XML)
    print(f"Reading {EN_XML} ...")
    en = parse_xml(EN_XML)
    merged = merge(zh, en)

    # Load existing output to preserve manual apps
    existing = {}
    if args.preserve_manual and args.output.exists():
        existing = json.loads(args.output.read_text()).get("apps", {})
        manual_ids = set(existing.keys()) - set(merged.keys())
        for mid in manual_ids:
            merged[mid] = existing[mid]
            print(f"Preserved manual: {mid}")

    out = {
        "version": 2,  # Bumped: actions[] schema
        "generatedAt": "2026-08-01",
        "source": "Lemon libcleaner cleaning-rule XML (item->action->path extraction, bilingual)",
        "appCount": len(merged),
        "apps": merged,
    }
    args.output.write_text(json.dumps(out, indent=2, ensure_ascii=False))
    print(f"Wrote {len(merged)} apps to {args.output}")


if __name__ == "__main__":
    main()