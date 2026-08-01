#!/usr/bin/env python3
"""Re-extract Lemon cleaning-rule XML into bundleIDMapping.json preserving
item -> action(title) -> path triples, bilingual (zh-Hans + en).

Source XML files:
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
OUTPUT = Path(__file__).resolve().parents[1] / "Resources" / "bundleIDMapping.json"


def text_of(elem):
    return (elem.text or "").strip() if elem is not None else ""


def parse_xml(path: Path):
    """Parse a Lemon XML and return list of (bundleID, item_title, [actions]).

    Each action dict carries the Lemon `type` attribute, a title (may be empty —
    e.g. Safari/Chrome ship untitled actions), and the cleaned absolute paths.
    """
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
                if paths:
                    actions.append({
                        "type": action.get("type") or "",
                        "name": action_title,
                        "paths": paths,
                    })
            if item_title and actions:
                items.append({
                    "bundleID": bundle_id,
                    "appstoreBundleID": item.get("appstorebundleid"),
                    "itemTitle": item_title,
                    "actions": actions,
                })
    return items


def _pair_actions(zh_actions, en_actions):
    """Pair zh and en actions into (zh_action, en_action_or_None).

    Lemon distinguishes actions by their `type` attribute, which both XMLs carry
    on every <action>. A type appearing exactly once on each side pairs
    unambiguously. Remaining actions pair greedily by maximum path overlap,
    preferring same-type candidates (this resolves duplicated types such as
    Xcode's multiple type="file" actions). The cross-type overlap fallback also
    catches zh/en type mismatches (e.g. iFLYTEK logs are typed "file" in the zh
    XML but "appcache" in the en XML). Chat-app actions share identical paths
    but differ by type, so they are all resolved by the type-keyed pass and
    never reach the overlap fallback.
    """
    en_used = [False] * len(en_actions)
    pairs_by_idx = {}
    pending = []
    for zi, zh_a in enumerate(zh_actions):
        cands = [ei for ei, en_a in enumerate(en_actions)
                 if not en_used[ei] and en_a["type"] == zh_a["type"]]
        if len(cands) == 1:
            pairs_by_idx[zi] = (zh_a, en_actions[cands[0]])
            en_used[cands[0]] = True
        else:
            pending.append(zi)
    for zi in pending:
        zh_a = zh_actions[zi]
        zh_paths = set(zh_a["paths"])
        best = None
        best_score = (-1, -1)  # (same type?, path overlap), tuple order matters
        for ei, en_a in enumerate(en_actions):
            if en_used[ei]:
                continue
            same = 1 if en_a["type"] == zh_a["type"] else 0
            overlap = len(zh_paths & set(en_a["paths"]))
            if (same, overlap) > best_score:
                best_score = (same, overlap)
                best = ei
        if best is not None:
            pairs_by_idx[zi] = (zh_a, en_actions[best])
            en_used[best] = True
        else:
            pairs_by_idx[zi] = (zh_a, None)
    return [pairs_by_idx[i] for i in range(len(zh_actions))]


def merge(zh_items, en_items):
    """Merge zh-Hans and en items by bundleID. Each app gets bilingual action titles."""
    en_by_id = {x["bundleID"]: x for x in en_items}
    merged = {}
    for zh in zh_items:
        bid = zh["bundleID"]
        en = en_by_id.get(bid, {})
        item_title = zh["itemTitle"]
        actions_out = []
        for zh_action, en_a in _pair_actions(zh["actions"], en.get("actions", [])):
            zh_title = zh_action["name"]
            paths = zh_action["paths"]
            en_title = en_a["name"] if en_a else ""
            if zh_title:
                # Normal case: zh title present, en title joined by type/path.
                nameCN = zh_title
                name = en_title or _fallback_title(zh_title)
            else:
                # zh title missing (e.g. Safari/Chrome): recover from en title,
                # else item title with a "- Cache" suffix for cache paths.
                recovered = en_title or _cache_suffix_name(item_title, paths)
                nameCN = recovered
                name = recovered
            actions_out.append({"nameCN": nameCN, "name": name, "paths": paths})
        merged[bid] = {
            "bundleID": bid,
            "appstoreBundleID": zh.get("appstoreBundleID") or en.get("appstoreBundleID"),
            "nameCN": item_title,
            "name": en.get("itemTitle", item_title),
            "actions": actions_out,
            "vendor": _vendor_from_bundle_id(bid),
            "type": _type_from_bundle_id(bid),
            "riskLevel": "recommended",
            "confidence": "high",
        }
    return merged


def _fallback_title(zh_title):
    """Fallback when no English title matched: keep the Chinese title in `name`."""
    return zh_title  # UI will fall back to nameCN if name == nameCN


def _cache_suffix_name(item_title, paths):
    """Fallback title for untitled actions: item title + ' - Cache' for cache paths."""
    if any("/Caches/" in p or "/Cache/" in p for p in paths):
        return f"{item_title} - Cache"
    return item_title


def _vendor_from_bundle_id(bid):
    parts = bid.split(".")
    if len(parts) >= 3 and parts[0] == "com":
        return parts[1].capitalize()
    return parts[0].capitalize() if parts else "Unknown"


def _type_from_bundle_id(bid):
    dev = {"apple", "microsoft", "google", "jetbrains", "github", "docker", "orbstack"}
    chat = {"tencent", "slack", "discord", "telegram", "zoom"}
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