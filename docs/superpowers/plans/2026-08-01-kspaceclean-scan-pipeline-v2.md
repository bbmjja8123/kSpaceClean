# kSpaceClean 扫描管线 v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the kSpaceClean v1 scan pipeline to deliver the full 4-level tree (Category → SubCategory[app] → Action → Result) with rich app coverage (~100 apps), reversible filter semantics (fold-not-delete), and 6 always-present category skeletons — fixing the "scanned too little / app bucket collapses to category name" complaint from the 2026-08-01 build.

**Architecture:** Replace the flat `cleanPaths` rule table with Lemon-style `item → action(title) → path` triples (Chinese + English titles), bucket by `bundleID` across all root paths per category, render the action level (`showAction = true`) so each app surfaces 3-4 semantic action rows, and split display filter from cleanup selection via an `isHiddenByFilter` flag so the default 100 KB size floor no longer destroys nodes. Static rule library is the spine; `ClassifierProtocol` remains the future hook for v1.x CoreML augmentation (Q3). Path probing of `/Applications` is v2 only (Q10).

**Tech Stack:** Swift 5.9, SwiftUI, macOS 13+, Xcode 14.3.1 (`/Applications/Xcode 2.app`), Swift Concurrency, Python 3 (rule extractor), XCTest

**Test command (run from worktree root):**
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kWise/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -destination 'platform=macOS' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES test 2>&1 | tail -40
```

**Build command (no tests):**
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kWise/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -20
```

**Project regen (after adding new Swift files):**
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1/kSpaceClean && python3 generate_project.py
```

## Global Constraints

- macOS 13.0 minimum deployment target; macOS 14 SDK compile target (`#available` wraps higher-version APIs).
- Swift 5.9 with `SWIFT_STRICT_CONCURRENCY = complete`; no `@unchecked Sendable` for new types — use actor isolation or proper value types.
- Xcode 14.3.1 at `/Applications/Xcode 2.app`; no `MainActor.assumeIsolated` (Xcode 14.3 lacks it).
- Project uses `kWise/generate_project.py` for pbxproj generation — every new `.swift` file **must** be registered in `swift_files` list before build.
- App Sandbox ON; TCC Full Disk Access required for non-`~/Library` paths (System cache, `/Library/Logs`, `/private/var/log`, `/Library/Caches`).
- **Never** copy Lemon Objective-C / C++ code; reference logic only.
- All public APIs must have DocC comments; SwiftLint enforced via `kFoundation/.swiftlint.yml`.
- Test coverage > 70% on new code.
- Models: `ScanCategory` (L1) → `ScanSubCategory` (L2, app-scoped) → `ScanAction` (L3, semantic name) → `ScanResult` (L4, file). The four-level tree is the canonical structure for v1.
- Filtering: **fold, do not delete** (Q6). The default size floor is **100 KB** (Q5). The user's PreScanPanel slider may range 0–100 MB; `showAllHidden` toggle reveals hidden-by-filter nodes.
- Empty categories: **always render 6 skeletons** with `占位 / 未发现相关项` placeholder (Q7).
- Bundle rule storage: single `kWise/Resources/bundleIDMapping.json` with `apps[id].actions: [{name, nameCN, paths, type}]` (Q2, Q9). Both languages are required for every action title.
- `/Applications` probing is **out of scope for v1.0** (Q10). Implement as a stub `InstalledAppProbe` returning empty list with a TODO comment for v2.

## File Structure

| # | File | Action | Purpose |
|---|---|---|---|
| 1 | `kWise/scripts/extract_lemon_rules.py` | **Create** | Re-extract Lemon XML into `bundleIDMapping.json` preserving `item → action(title) → path` triples, bilingual |
| 2 | `kWise/Resources/bundleIDMapping.json` | **Modify** | Adopt `apps[id].actions` schema; add ~50 new apps (D range) |
| 3 | `kFoundation/Sources/FileScanner/BundleIDResolver.swift` | **Modify** | Fix L1 path-prefix expansion to use real `$HOME`, not sandbox container |
| 4 | `kFoundation/Sources/FileScanner/BundleIDResolverTests.swift` | **Create** | Sandbox-vs-real-home regression test |
| 5 | `kWise/Features/SmartScan/Models/ScanTreeNode.swift` | **Modify** | Add `isHiddenByFilter: Bool` to protocol |
| 6 | `kWise/Features/SmartScan/Models/ScanCategory.swift` | **Modify** | Add `isHiddenByFilter` field, ensure skeleton init exposes empty placeholder |
| 7 | `kWise/Features/SmartScan/Models/ScanSubCategory.swift` | **Modify** | Add `isHiddenByFilter` field |
| 8 | `kWise/Features/SmartScan/Models/ScanAction.swift` | **Modify** | Add `isHiddenByFilter` field, switch `showAction` to `var` |
| 9 | `kWise/Features/SmartScan/Models/ScanResult.swift` | **Modify** | Add `isHiddenByFilter` field |
| 10 | `kWise/Features/SmartScan/Models/ScanCategory.swift` | **Modify** | Switch `showAction` to `var` for runtime decision |
| 11 | `kWise/Features/SmartScan/Engine/ScanOrchestrator.swift` | **Modify** | Bucket shared across rootPaths (Q8); build action level per app (Q2); emit `isHiddenByFilter=false` default |
| 12 | `kWise/Features/SmartScan/Views/ScanResultsViewModel.swift` | **Modify** | `applyFilters` becomes `annotateHidden` (returns tree unchanged, marks `isHiddenByFilter=true`); default `minimumSizeBytes = 102_400`; `showAllHidden: Bool` toggle; preserve 6 skeleton categories |
| 13 | `kWise/Features/SmartScan/Views/ScanResultsView.swift` | **Modify** | RecursiveTreeNode skips `isHiddenByFilter` unless `showAllHidden`; PreScanPanel adds "显示全部" toggle |
| 14 | `kWise/Tests/ScanTreeFilterTests.swift` | **Create** | Hidden-flag + skeleton preservation + showAllHidden tests |
| 15 | `kWise/Tests/AppRuleFixtures.swift` | **Create** | Per-app integration fixtures (one per new app class) |

---

## Task 1: Fix BundleIDResolver L1 sandbox tilde mismatch

**Files:**
- Modify: `kFoundation/Sources/FileScanner/BundleIDResolver.swift:108-138`
- Test: `kFoundation/Tests/FileScannerTests/BundleIDResolverTests.swift` (new file)

**Why first:** Without this fix, every `~/Library/Application Support/<App>` lookup falls back to the generic `def.id` bucket, which is the root cause of "应用缓存 → 应用缓存" duplication.

**Step 1: Write failing test**

Create `kFoundation/Tests/FileScannerTests/BundleIDResolverTests.swift`:

```swift
import XCTest
@testable import FileScanner

final class BundleIDResolverTests: XCTestCase {
    func testL1PrefixMatchIgnoresSandboxContainer() throws {
        // Real-home path: /Users/test/Library/Application Support/Slack
        // Sandbox expands ~/ → container home which does NOT contain real
        // bundleIDs. The resolver must use real-home expansion.
        let mappingJSON = """
        {
          "version": 1,
          "apps": {
            "com.tinyspeck.chatlytic": {
              "name": "Slack",
              "nameCN": "Slack",
              "actions": [{
                "name": "Slack Caches",
                "nameCN": "Slack 缓存",
                "paths": ["~/Library/Application Support/Slack"]
              }]
            }
          }
        }
        """.data(using: .utf8)!
        let url = try writeTempMapping(mappingJSON)
        defer { try? FileManager.default.removeItem(at: url) }
        let resolver = try BundleIDResolver.load(from: url)

        let realHome = NSHomeDirectory() // passwd-based, sandboxed apps see container — must match what orchestrator uses
        let path = realHome + "/Library/Application Support/Slack/Cookies/localstorage.json"
        let resolved = resolver.resolve(path: path)
        XCTAssertEqual(resolved?.bundleID, "com.tinyspeck.chatlytic",
                       "L1 prefix match must hit real-home expansion, not sandbox container")
    }

    private func writeTempMapping(_ data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundleID-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }
}
```

**Step 2: Run test to verify failure**

Run from worktree root:
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kWise/kSpaceClean.xcodeproj -scheme kSpaceClean \
  -destination 'platform=macOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  test -only-testing:BundleIDResolverTests 2>&1 | tail -25
```

Expected: FAIL — current `expand(_:)` uses `expandingTildeInPath` which resolves to sandbox container, so prefix `~/Library/Application Support/Slack` never matches the real-home path the orchestrator passes in.

**Step 3: Fix `expand(_:)` in BundleIDResolver**

Edit `kFoundation/Sources/FileScanner/BundleIDResolver.swift`, replacing the `expand(_:)` static method (around line 137):

```swift
/// Expand a tilde-prefixed path against the **real** $HOME (passwd-based),
/// NOT the sandbox container home. `expandingTildeInPath` resolves `~` to
/// the container home inside a sandboxed app, which never matches the
/// orchestrator's enumerator output (also passwd-based via
/// `UserPathResolver.expandTilde`). This silent mismatch was the root cause
/// of the 2026-08-01 "应用缓存 → 应用缓存" duplication bug.
private static func expand(_ path: String) -> String {
    guard path.hasPrefix("~/") else { return path }
    let home = FileManager.default.homeDirectoryForCurrentUser
        .standardizedFileURL.path
    return home + String(path.dropFirst(1))
}
```

Also update `BundleIDResolver.load()` if it relies on `expand` for `cleanPaths` — find the loop that calls `expandedCleanPaths` and ensure it uses the new `expand(_:)`. (The current implementation should already call it consistently; verify by re-running tests.)

**Step 4: Run test to verify pass**

Same command as Step 2.

Expected: PASS.

**Step 5: Run full suite to ensure no regression**

Run the test command at top of plan. Expected: 248/248 (previous 247 + 1 new).

**Step 6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kFoundation/Sources/FileScanner/BundleIDResolver.swift \
        kFoundation/Tests/FileScannerTests/BundleIDResolverTests.swift && \
git commit -m "fix(BundleIDResolver): expand tilde against real \$HOME, not sandbox container"
```

---

## Task 2: Rewrite Lemon XML extractor preserving item → action → path + bilingual

**Files:**
- Create: `kWise/scripts/extract_lemon_rules.py`

**Why second:** Without preserving action titles, the third level of the 4-level tree stays missing (current symptom).

**Step 1: Write the extractor**

Create `kWise/scripts/extract_lemon_rules.py`:

```python
#!/usr/bin/env python3
"""Re-extract Lemon cleaning-rule XML into bundleIDMapping.json preserving
item → action(title) → path triples, bilingual (zh-Hans + en).

Source XML files:
  /Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/garbage.xml         (system)
  .../zh-Hans.lproj/garbage1.xml            (app + system, zh-Hans titles)
  .../en.lproj/garbage_appstore.xml         (app + system, en titles)

Output: kWise/Resources/bundleIDMapping.json (overwrites, preserves manual apps if --preserve-manual).

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
        "source": "Lemon libcleaner cleaning-rule XML (item→action→path extraction, bilingual)",
        "appCount": len(merged),
        "apps": merged,
    }
    args.output.write_text(json.dumps(out, indent=2, ensure_ascii=False))
    print(f"Wrote {len(merged)} apps to {args.output}")


if __name__ == "__main__":
    main()
```

**Step 2: Run extractor**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1/kWise/scripts && \
python3 extract_lemon_rules.py --preserve-manual
```

Expected: prints count (≈25-35 apps preserved), writes `Resources/bundleIDMapping.json` with `version: 2` and `apps[id].actions` schema.

**Step 3: Verify schema**

```bash
python3 -c "
import json
d = json.load(open('/Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1/kWise/Resources/bundleIDMapping.json'))
assert d['version'] == 2, f'expected version 2, got {d[\"version\"]}'
qq = d['apps']['com.tencent.qq']
assert 'actions' in qq, 'QQ missing actions'
assert all('name' in a and 'nameCN' in a and 'paths' in a for a in qq['actions']), 'action missing bilingual title or paths'
print(f'OK: {len(d[\"apps\"])} apps, QQ has {len(qq[\"actions\"])} actions')
"
```

Expected: `OK: <N> apps, QQ has 8 actions` (or similar).

**Step 4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kWise/scripts/extract_lemon_rules.py kWise/Resources/bundleIDMapping.json && \
git commit -m "feat(scripts): rewrite Lemon extractor to preserve item→action→path with bilingual titles"
```

---

## Task 3: Update BundleIDResolver to consume new `actions[]` schema

**Files:**
- Modify: `kFoundation/Sources/FileScanner/BundleIDResolver.swift`
- Test: `kFoundation/Tests/FileScannerTests/BundleIDResolverTests.swift` (extend)

**Step 1: Write failing test for actions schema**

Append to `BundleIDResolverTests.swift`:

```swift
func testLoadsActionsSchemaV2() throws {
    let mappingJSON = """
    {
      "version": 2,
      "apps": {
        "com.example.app": {
          "bundleID": "com.example.app",
          "name": "Example",
          "nameCN": "示例",
          "actions": [{
            "name": "Example Cache",
            "nameCN": "示例缓存",
            "paths": ["~/Library/Caches/com.example.app"]
          }]
        }
      }
    }
    """.data(using: .utf8)!
    let url = try writeTempMapping(mappingJSON)
    defer { try? FileManager.default.removeItem(at: url) }
    let resolver = try BundleIDResolver.load(from: url)
    XCTAssertEqual(resolver.appCount, 1)
    XCTAssertEqual(resolver.app(forBundleID: "com.example.app")?.name, "Example")
}
```

**Step 2: Run test to verify failure**

Run the test command from Task 1 Step 2.

Expected: FAIL — current loader expects flat `cleanPaths`.

**Step 3: Update `ResolvedApp` and loader**

Edit `BundleIDResolver.swift`:

```swift
public struct ResolvedApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String
    public let nameCN: String
    public let actions: [ResolvedAction]  // NEW: replaces cleanPaths

    public struct ResolvedAction: Sendable, Equatable {
        public let name: String
        public let nameCN: String
        public let paths: [String]
    }
}
```

Replace the `cleanPaths` decode and the `expandedCleanPaths` cache with:

```swift
private struct JSONMapping: Decodable {
    let apps: [String: JSONApp]
}
private struct JSONApp: Decodable {
    let bundleID: String
    let name: String
    let nameCN: String?
    let actions: [JSONAction]?  // v2
    let cleanPaths: [String]?    // v1 legacy fallback
}
private struct JSONAction: Decodable {
    let name: String
    let nameCN: String?
    let paths: [String]
}

public init(mapping: [String: ResolvedApp]) {
    self.mapping = mapping
}

static func load(from url: URL) throws -> BundleIDResolver {
    let data = try Data(contentsOf: url)
    let raw = try JSONDecoder().decode(JSONMapping.self, from: data)
    var out: [String: ResolvedApp] = [:]
    for (key, app) in raw.apps {
        let actions: [ResolvedApp.ResolvedAction]
        if let v2 = app.actions {
            actions = v2.map { .init(name: $0.name,
                                     nameCN: $0.nameCN ?? $0.name,
                                     paths: $0.paths) }
        } else if let v1 = app.cleanPaths {
            actions = [.init(name: app.nameCN, nameCN: app.nameCN, paths: v1)]
        } else {
            continue
        }
        out[key] = .init(bundleID: app.bundleID,
                          name: app.name,
                          nameCN: app.nameCN ?? app.name,
                          actions: actions)
    }
    return BundleIDResolver(mapping: out)
}
```

Add convenience API:
```swift
public var appCount: Int { mapping.count }
public func app(forBundleID id: String) -> ResolvedApp? { mapping[id] }
```

**Step 4: Run test to verify pass**

Same as Step 2. Expected: PASS.

**Step 5: Update `resolve(path:)` to use `actions[].paths` for L1 prefix matching**

Replace the L1 loop:
```swift
public func resolve(path: String) -> ResolvedApp? {
    let normalized = Self.expand(path)
    // L1 — path-prefix match (any action's any path)
    for entry in mapping.values {
        for action in entry.actions {
            for raw in action.paths {
                let prefix = Self.expand(raw)
                if normalized.hasPrefix(prefix) { return entry }
            }
        }
    }
    // L2 — reverse-DNS token
    for entry in mapping.values {
        if normalized.contains(entry.bundleID) { return entry }
    }
    return nil
}
```

**Step 6: Run full suite**

Run test command from plan top. Expected: 249/249.

**Step 7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kFoundation/Sources/FileScanner/BundleIDResolver.swift \
        kFoundation/Tests/FileScannerTests/BundleIDResolverTests.swift && \
git commit -m "feat(BundleIDResolver): consume v2 actions[] schema with bilingual titles"
```

---

## Task 4: Add `isHiddenByFilter` to ScanTreeNode protocol and four models

**Files:**
- Modify: `kWise/Features/SmartScan/Models/ScanTreeNode.swift`
- Modify: `kWise/Features/SmartScan/Models/ScanCategory.swift`
- Modify: `kWise/Features/SmartScan/Models/ScanSubCategory.swift`
- Modify: `kWise/Features/SmartScan/Models/ScanAction.swift`
- Modify: `kWise/Features/SmartScan/Models/ScanResult.swift`

**Step 1: Write failing test**

Create `kWise/Tests/ScanTreeFilterTests.swift`:

```swift
import XCTest
@testable import kSpaceClean

@MainActor
final class ScanTreeFilterTests: XCTestCase {
    func testHiddenFlagDefaultsToFalse() {
        let result = ScanResult(resultID: "r1", path: "/tmp/foo", size: 1024)
        let action = ScanAction(actionID: "a1", title: "Cache", results: [result])
        let sub = ScanSubCategory(subCategoryID: "s1", title: "Xcode", actions: [action])
        let cat = ScanCategory(categoryID: "c1", title: "Dev", subItems: [sub])

        XCTAssertFalse(result.isHiddenByFilter)
        XCTAssertFalse(action.isHiddenByFilter)
        XCTAssertFalse(sub.isHiddenByFilter)
        XCTAssertFalse(cat.isHiddenByFilter)
    }

    func testHiddenFlagMutable() {
        var action = ScanAction(actionID: "a1", title: "Cache", results: [])
        action.isHiddenByFilter = true
        XCTAssertTrue(action.isHiddenByFilter)
    }
}
```

**Step 2: Run test to verify failure**

Run full test command. Expected: FAIL — `isHiddenByFilter` not defined.

**Step 3: Add `isHiddenByFilter` to protocol**

Edit `ScanTreeNode.swift`, add to protocol:

```swift
public protocol ScanTreeNode: Identifiable, Hashable, Sendable {
    // ... existing
    /// True when a default filter (e.g. 100 KB size floor) would hide this
    /// node from the default tree view. The node remains in the data model
    /// so the cleanup pipeline can still select it; `ScanResultsView`
    /// skips rendering unless `ScanResultsViewModel.showAllHidden` is on.
    var isHiddenByFilter: Bool { get set }
}
```

**Step 4: Add field to all four models**

For `ScanCategory`, `ScanSubCategory`, `ScanAction`, `ScanResult`: add `public var isHiddenByFilter: Bool = false` and add `isHiddenByFilter: Bool = false` parameter to each initializer (default false). Use Edit tool for each file — find the existing `public let riskLevel` or similar pattern and add the field right after.

**Step 5: Switch `showAction` to `var` in ScanSubCategory and ScanCategory**

Currently `let showAction: Bool = false`. Change to `var showAction: Bool = false` so the orchestrator can decide per-category whether to render the action level.

**Step 6: Run test to verify pass**

Run test command. Expected: PASS.

**Step 7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kWise/Features/SmartScan/Models/ kWise/Tests/ScanTreeFilterTests.swift && \
git commit -m "feat(ScanTree): add isHiddenByFilter flag; switch showAction to var"
```

---

## Task 5: ScanOrchestrator — bucket shared across rootPaths + action-level grouping

**Files:**
- Modify: `kWise/Features/SmartScan/Engine/ScanOrchestrator.swift` (around lines 549-645, the `scanCategory` worker)
- Test: `kWise/Tests/AppRuleFixtures.swift` (new — see Step 1)

**Step 1: Write failing test for action-level grouping**

Create `kWise/Tests/AppRuleFixtures.swift`:

```swift
import XCTest
import FileScanner
@testable import kSpaceClean

@MainActor
final class AppRuleFixtures: XCTestCase {
    /// Multi-rootPath category with one known app expected to surface
    /// under TWO rootPaths (~/Library/Application Support + ~/Library/Containers).
    /// Asserts (a) one sub-category per app, (b) action level built.
    func testSlackSurfacesOnceAcrossTwoRootPaths() async throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("ksc-fixture-slack-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // App Support: ~/Library/Application Support/Slack/Cookies/localstorage.json
        let appSupport = root.appendingPathComponent("AppSupp/Slack/Cookies", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 2048).write(to: appSupport.appendingPathComponent("localstorage.json"))

        // Containers: ~/Library/Containers/com.tinyspeck.chatlytic/Library/Caches/fsCachedData
        let containers = root.appendingPathComponent("Containers/com.tinyspeck.chatlytic/Library/Caches/fsCachedData",
                                                     isDirectory: true)
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 4096).write(to: containers.appendingPathComponent("abc.dat"))

        let mappingJSON = """
        {
          "version": 2,
          "apps": {
            "com.tinyspeck.chatlytic": {
              "bundleID": "com.tinyspeck.chatlytic",
              "name": "Slack",
              "nameCN": "Slack",
              "actions": [
                {"name": "Slack Cache", "nameCN": "Slack 缓存",
                 "paths": ["\(root.path)/AppSupp/Slack"]},
                {"name": "Sandbox Cache", "nameCN": "沙盒缓存",
                 "paths": ["\(root.path)/Containers/com.tinyspeck.chatlytic"]}
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let mappingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapping-\(UUID().uuidString).json")
        try mappingJSON.write(to: mappingURL)
        defer { try? FileManager.default.removeItem(at: mappingURL) }

        let resolver = try BundleIDResolver.load(from: mappingURL)
        let cats = [
            CategoryDefinition(
                id: "fixture.appcache",
                title: "Fixture App Cache",
                paths: [
                    root.appendingPathComponent("AppSupp").path,
                    root.appendingPathComponent("Containers").path
                ],
                riskLevel: .recommended
            )
        ]
        let orchestrator = ScanOrchestrator(
            categoryDefinitions: cats,
            resolver: resolver
        )

        let stream = await orchestrator.startScan()
        for await p in stream { if case .completed = p.state { break } }

        let category = try XCTUnwrap(orchestrator.publishedCategories.first)
        XCTAssertEqual(category.subItems.count, 1,
                       "Slack must appear as ONE sub-category across both rootPaths")
        let slack = try XCTUnwrap(category.subItems.first)
        XCTAssertEqual(slack.bundleID, "com.tinyspeck.chatlytic")
        XCTAssertGreaterThan(slack.actions.count, 1,
                             "action level must be built when resolver provides multiple actions")
    }
}
```

**Step 2: Run test to verify failure**

Run test command, expect FAIL.

**Step 3: Refactor `scanCategory` worker**

Edit `ScanOrchestrator.swift` `scanCategory(_:)` method. The key changes:

(a) Hoist `bucketByApp` outside the `for rootPath in def.paths` loop. Declare them once per category:

```swift
var bucketByApp: [String: [ScanResult]] = [:]
var bucketActions: [String: [ResolvedAction]] = [:]  // action metadata per app
var bucketTitle: [String: String] = [:]
var bucketBundleID: [String: String] = [:]
var bucketAppName: [String: String] = [:]
```

(b) Inside the inner `for await info in enumerator.enumerate(rootPath:)` loop, change `let bucketKey = app?.bundleID ?? def.id` and populate `bucketActions[bucketKey] = app?.actions ?? []` (only first time).

(c) After both loops, for each `(bundleID, results)` in `bucketByApp`, build:

```swift
let actions = bucketActions[bundleID].map { ra in
    ScanAction(
        actionID: "\(def.id).\(bundleID).\(ra.name)",
        title: ra.nameCN,
        titleCN: ra.nameCN,
        titleEN: ra.name,
        results: results.filter { /* belongs to this action's paths */ },
        riskLevel: def.riskLevel,
        recommend: true,
        isRecommended: true
    )
}
```

(d) Emit `ScanSubCategory` with `showAction: true` and `actions: actions`, `directResults: []`.

**Step 4: Run test to verify pass**

Run test command, expect PASS.

**Step 5: Run full suite**

Run full test command. Expect 250/250.

**Step 6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kWise/Features/SmartScan/Engine/ScanOrchestrator.swift \
        kWise/Tests/AppRuleFixtures.swift && \
git commit -m "feat(ScanOrchestrator): bucket shared across rootPaths + build action level from rule actions"
```

---

## Task 6: applyFilters → annotateHidden (fold-not-delete) + default 100 KB + skeleton preservation

**Files:**
- Modify: `kWise/Features/SmartScan/Views/ScanResultsViewModel.swift`

**Step 1: Write failing test for fold-not-delete**

Append to `ScanTreeFilterTests.swift`:

```swift
@MainActor
final class ScanResultsViewModelFilterTests: XCTestCase {
    func testApplyFiltersAnnotatesHiddenDoesNotDelete() {
        // Build a category with one big result and one small result
        let big = ScanResult(resultID: "r1", path: "/tmp/big", size: 10_000_000)
        let small = ScanResult(resultID: "r2", path: "/tmp/small", size: 100)
        let action = ScanAction(actionID: "a1", title: "Cache", results: [big, small])
        let sub = ScanSubCategory(subCategoryID: "s1", title: "TestApp", actions: [action])
        let cat = ScanCategory(categoryID: "c1", title: "Test", subItems: [sub])

        let options = ScanFilterOptions(minimumSizeBytes: 102_400)  // 100 KB
        let result = ScanResultsViewModel.annotateHidden(
            [cat], options: options, now: Date()
        )

        let resultCat = try! XCTUnwrap(result.first)
        let resultSub = try! XCTUnwrap(resultCat.subItems.first)
        let resultAction = try! XCTUnwrap(resultSub.actions.first)
        XCTAssertEqual(resultAction.results.count, 2,
                       "all results must remain in tree, only isHiddenByFilter changes")
        XCTAssertFalse(resultAction.results[0].isHiddenByFilter) // 10 MB → visible
        XCTAssertTrue(resultAction.results[1].isHiddenByFilter)   // 100 B → hidden
    }

    func testApplyFiltersPreservesSixSkeletons() {
        // Empty categories (FDA missing, no apps installed)
        let cats = (1...6).map { i in
            ScanCategory(categoryID: "c\(i)", title: "Cat \(i)", subItems: [])
        }
        let result = ScanResultsViewModel.annotateHidden(
            cats, options: .default, now: Date()
        )
        XCTAssertEqual(result.count, 6,
                       "empty categories must remain as skeletons, not be deleted")
    }
}
```

**Step 2: Run test to verify failure**

Run test command, expect FAIL.

**Step 3: Rename and refactor `applyFilters`**

In `ScanResultsViewModel.swift`:

(a) Replace `minimumSizeBytes: Int64 = 1_048_576` with `minimumSizeBytes: Int64 = 102_400` (100 KB) in `ScanFilterOptions.init`.

(b) Rename `static func applyFilters` to `static func annotateHidden`. Change return signature to `[ScanCategory]` (same as before). Inside, replace `compactMap` with `map` so nothing is deleted:

```swift
static func annotateHidden(
    _ categories: [ScanCategory],
    options: ScanFilterOptions,
    now: Date = Date()
) -> [ScanCategory] {
    let _ = PerfInterval("filter.annotate")
    let runningBundleIDs: Set<String> = options.skipRunningApps
        ? Self.snapshotRunningBundleIDs() : []
    let ageCutoff: Date? = options.minimumUnusedDays > 0
        ? now.addingTimeInterval(-Double(options.minimumUnusedDays) * 86_400)
        : nil

    return categories.map { category in
        let subs = category.subItems.map { sub in
            annotateSubHidden(sub, options: options,
                              runningBundleIDs: runningBundleIDs, ageCutoff: ageCutoff)
        }
        let visibleSubs = subs.filter { !$0.isHiddenByFilter || subs.contains(where: { !$0.isHiddenByFilter }) }
        // Keep all subs; mark parent hidden only if all children hidden
        let allChildrenHidden = subs.allSatisfy(\.isHiddenByFilter)
        return ScanCategory(
            categoryID: category.categoryID,
            title: category.title,
            tooltip: category.tooltip,
            totalSize: category.totalSize,
            subItems: subs,
            riskLevel: category.riskLevel,
            isRecommended: category.isRecommended,
            isHiddenByFilter: allChildrenHidden
        )
    }
}

private static func annotateSubHidden(...) -> ScanSubCategory { ... }
```

**Important:** the function must still apply `skipRunningApps` (delete is OK for safety — a sub-category for a currently running app truly cannot be cleaned); `skipDangerous` (mark hidden, do not delete). Only the size and age filters become "mark hidden" semantics.

(c) Update the caller in `startRealScan`:
```swift
newSnapshot.categories = Self.annotateHidden(raw, options: filters)
```

(d) Add `showAllHidden: Bool = false` to `ScanResultsViewModel` as `@Published`.

**Step 4: Run test to verify pass**

Run test command, expect PASS.

**Step 5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kWise/Features/SmartScan/Views/ScanResultsViewModel.swift \
        kWise/Tests/ScanTreeFilterTests.swift && \
git commit -m "feat(ScanResultsViewModel): annotateHidden folds nodes; default 100 KB; preserve 6 skeletons"
```

---

## Task 7: ScanResultsView — skip hidden unless `showAllHidden`

**Files:**
- Modify: `kWise/Features/SmartScan/Views/ScanResultsView.swift`

**Step 1: Write failing test**

Append to `ScanResultsViewModelFilterTests.swift`:

```swift
@MainActor
final class ScanResultsViewHiddenRenderingTests: XCTestCase {
    func testHiddenNodeNotRenderedWhenShowAllHiddenFalse() {
        // Indirect: RecursiveTreeNode.== should consider isHiddenByFilter
        // false for a hidden node so SwiftUI can skip its body. We assert
        // via RecursiveTreeNode equality with showAllHidden binding.
        let result = ScanResult(resultID: "r1", path: "/tmp/x", size: 100, isHiddenByFilter: true)
        let node = RecursiveTestFactory.make(node: result, level: 0, expandedIDs: [])
        // RecursiveTreeNode.== should treat hidden nodes as visually empty
        // when showAllHidden is false — we test via the public visibleNodes
        // accessor (added in this task).
        XCTAssertFalse(node.isVisibleWhenHidden(showAllHidden: false))
        XCTAssertTrue(node.isVisibleWhenHidden(showAllHidden: true))
    }
}
```

Add `func isVisibleWhenHidden(showAllHidden: Bool) -> Bool` to `RecursiveTreeNode`:

```swift
extension RecursiveTreeNode {
    func isVisibleWhenHidden(showAllHidden: Bool) -> Bool {
        if showAllHidden { return true }
        return !node.isHiddenByFilter
    }
}
```

Make `RecursiveTreeNode` `internal` (drop `private`) so the test can reference it.

**Step 2: Run test to verify failure**

Run test command, expect FAIL.

**Step 3: Wire `showAllHidden` into ScanResultsView body**

In `ScanResultsView.body`, gate `ForEach(viewModel.categories)`:
```swift
} else {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.categories) { category in
                if !category.isHiddenByFilter || viewModel.showAllHidden {
                    RecursiveTreeNode(
                        node: category,
                        level: 0,
                        expandedIDs: viewModel.expandedIDs,
                        showAllHidden: viewModel.showAllHidden,
                        onToggleExpand: viewModel.toggleExpand,
                        onToggleSelect: viewModel.toggleSelect
                    )
                    .equatable()
                }
            }
        }
    }
}
```

Pass `showAllHidden` down through `RecursiveTreeNode` and `ScanTreeRow`.

**Step 4: Add "显示全部" toggle to PreScanPanel**

In `PreScanPanel` (or above the tree when results show), add:

```swift
Toggle("显示过滤掉的项", isOn: $viewModel.showAllHidden)
    .accessibilityLabel("显示过滤掉的项")
```

Place above `ScrollView` when `!viewModel.categories.isEmpty`.

**Step 5: Run test to verify pass**

Run test command, expect PASS.

**Step 6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git add kWise/Features/SmartScan/Views/ScanResultsView.swift \
        kWise/Tests/ScanTreeFilterTests.swift && \
git commit -m "feat(ScanResultsView): gate tree on showAllHidden; add 显示全部 toggle"
```

---

## Task 8: Add ~50 new app rules (D range) — AI Coding & Agent Tools (Batch 1)

**Files:**
- Modify: `kWise/Resources/bundleIDMapping.json`

**Subagents must execute the per-app research loop below.** This task covers the first batch (AI tools + IDEs) of the ~50 new apps.

### Apps in this batch

| App | bundleID | Vendor | Primary cleanPaths pattern (research needed) |
|---|---|---|---|
| Claude Code | `com.anthropic.claude` | Anthropic | `~/Library/Application Support/Claude` + `~/Library/Caches/com.anthropic.claude` + `~/Library/Logs/Claude` |
| Claude Desktop | `com.anthropic.claudefordesktop` | Anthropic | `~/Library/Application Support/Claude` + Electron `Cache` + `Local Storage` |
| Cursor | `com.todesclient.unicorn` | Cursor Inc | VSCode fork → `~/Library/Application Support/Cursor` + `~/Library/Caches/com.todesclient.unicorn` + `CachedData` |
| Windsurf | `com.codeium.windsurf` | Codeium | VSCode fork → `~/Library/Application Support/Windsurf` + `CachedData` |
| Trae | `com.trae.app` | ByteDance | VSCode fork → `~/Library/Application Support/Trae` + `CachedData` |
| ChatGPT Desktop | `com.openai.chat` | OpenAI | `~/Library/Application Support/com.openai.chat` + Electron cache |
| Perplexity Desktop | `com.perplexity.perplexity` | Perplexity | `~/Library/Application Support/Perplexity` |
| Raycast | `com.raycast.macos` | Raycast | `~/Library/Application Support/Raycast` + `~/Library/Caches/com.raycast.macos` + extension caches |
| MacGPT | `com.macgpt.macgpt` | MacGPT | `~/Library/Application Support/MacGPT` |
| Ollama | `com.electron.ollama` | Ollama | `~/.ollama/models` (skipped — user data) + `~/Library/Application Support/Ollama` |
| LM Studio | `com.lmstudio.lmstudio` | LM Studio | `~/.cache/lm-studio` + `~/Library/Application Support/LM Studio` |
| Jan.ai | `com.jan.jan` | Jan | `~/Library/Application Support/Jan` |
| GPT4All | `com.nomic.gpt4all` | Nomic | `~/Library/Application Support/gpt4all` |
| Xcode 16 | `com.apple.dt.Xcode` | Apple | `~/Library/Developer/Xcode/DerivedData` + `iOS DeviceSupport` + `Archives` + `ModuleCache.noindex` + `iOS Device Logs` + `DocumentationCache` |
| JetBrains Toolbox | `com.jetbrains.toolbox` | JetBrains | `~/Library/Application Support/JetBrains/Toolbox` + `~/Library/Caches/com.jetbrains.toolbox` |
| JetBrains IntelliJ | `com.jetbrains.intellij` | JetBrains | `~/Library/Application Support/JetBrains/IntelliJIdea2024.*` + `~/Library/Caches/JetBrains/IntelliJIdea2024.*` |
| JetBrains PyCharm | `com.jetbrains.pycharm` | JetBrains | same pattern |
| JetBrains WebStorm | `com.jetbrains.WebStorm` | JetBrains | same pattern |
| Zed | `dev.zed.Zed` | Zed | `~/Library/Application Support/Zed` + `~/Library/Caches/dev.zed.Zed` |
| Antigravity | `com.google.antigravity` | Google | TBD (likely VSCode fork path) |

**Step 1: For each app, run research loop**

For each row above:

1. `ls -la ~/Library/Application Support/<AppName>` and `~/Library/Caches/<bundleID>` after **launching the app at least once** (creates caches).
2. Check `~/Library/Containers/<bundleID>/Data/Library/Caches/...` for sandboxed apps.
3. Check `~/Library/Logs/<AppName>` for log directories.
4. For dev tools, also check `~/.cache/<tool>` and `~/.<tool>/` for hidden cache directories.

**Step 2: Add entry to bundleIDMapping.json**

For each app, append an entry to `apps`:

```json
"com.anthropic.claude": {
  "bundleID": "com.anthropic.claude",
  "name": "Claude Code",
  "nameCN": "Claude Code",
  "vendor": "Anthropic",
  "type": "developer",
  "riskLevel": "caution",
  "confidence": "high",
  "actions": [
    {
      "name": "Claude Cache",
      "nameCN": "Claude 缓存",
      "paths": [
        "~/Library/Caches/com.anthropic.claude",
        "~/Library/Application Support/Claude/Cache",
        "~/Library/Application Support/Claude/CachedData"
      ]
    },
    {
      "name": "Claude Logs",
      "nameCN": "Claude 日志",
      "paths": ["~/Library/Logs/Claude"]
    },
    {
      "name": "Claude Code Data",
      "nameCN": "Claude Code 数据",
      "paths": [
        "~/Library/Application Support/Claude",
        "~/Library/Application Support/com.anthropic.claude"
      ]
    }
  ]
}
```

**Step 3: Add fixture integration test**

Append to `AppRuleFixtures.swift` one test per app class (5-6 tests covering the batch, not 20):

```swift
func testClaudeCodeActionBucketsResolveCorrectly() async throws {
    // Mirror Slack test pattern: create fixture dirs at each declared path,
    // drop a tiny file, assert category appears with action-level grouping.
}
```

**Step 4: Run test command**

Expect 250/250 + N new tests pass.

**Step 5: Commit per app class**

```bash
git add kWise/Resources/bundleIDMapping.json kWise/Tests/AppRuleFixtures.swift && \
git commit -m "feat(rules): add AI coding & agent tools batch (Claude Code, Cursor, Windsurf, ...)"
```

---

## Task 9: Add ~50 new app rules (D range) — Browsers + Containers + Terminals (Batch 2)

Same template as Task 8.

### Apps in this batch

| App | bundleID | Notes |
|---|---|---|
| Arc Browser | `company.thebrowser.daily` | Chromium cache + `~/Library/Application Support/Arc` |
| Brave | `com.brave.Browser` | Chromium cache |
| Vivaldi | `com.vivaldi.Vivaldi` | Chromium cache |
| Orion | `com.kagi.kagimacOS` | WebKit cache |
| Firefox | `org.mozilla.firefox` | `~/Library/Caches/Firefox` + `~/Library/Application Support/Firefox` |
| SigmaOS | `com.sigmaos.macos` | Chromium cache |
| Docker Desktop | `com.docker.docker` | `~/Library/Containers/com.docker.docker` + `~/Library/Group Containers/group.com.docker` |
| OrbStack | `dev.orbstack.OrbStack` | `~/.orbstack` (skip — VM data) + `~/Library/Application Support/OrbStack` |
| Colima | `abiosoft.colima` | `~/.colima` (skip — VM data) + `~/Library/Application Support/Colima` |
| Podman Desktop | `io.podman_desktop.PodmanDesktop` | Electron cache |
| Warp | `dev.warp.Warp-Stable` | `~/Library/Application Support/dev.warp.Warp-Stable` + AI training data cache |
| Ghostty | `com.mitchellh.ghostty` | `~/Library/Application Support/com.mitchellh.ghostty` |
| Rio | `com.raphaelamorim.rio` | `~/Library/Application Support/com.raphaelamorim.rio` |
| Fig | `fig.tools.client` | `~/Library/Application Support/fig` |

**Steps:** same as Task 8 — research → add entries → fixture tests → commit.

---

## Task 10: Add ~50 new app rules (D range) — Communication & Collaboration (Batch 3)

### Apps in this batch

| App | bundleID | Notes |
|---|---|---|
| Slack | `com.tinyspeck.chatlytic` | Already in Lemon; verify paths + add Cookies / Local Storage action |
| Discord | `com.hnc.Discord` | `~/Library/Application Support/discord` + Electron cache |
| Microsoft Teams | `com.microsoft.teams` | `~/Library/Application Support/Microsoft Teams` |
| Zoom | `us.zoom.xos` | `~/Library/Application Support/zoom.us` |
| Telegram Desktop | `org.telegram.desktop` | `~/Library/Application Support/Telegram Desktop` |
| Signal Desktop | `org.whispersystems.signal-desktop` | `~/Library/Application Support/Signal` |
| Lark | `com.bytedance.lark` | `~/Library/Application Support/Lark` |
| DingTalk | `com.alibaba.DingTalkMac` | Already in Lemon; verify |
| Feishu | `com.bytedance.feishu` | `~/Library/Application Support/feishu` |
| WhatsApp | `net.whatsapp.WhatsApp` | `~/Library/Application Support/WhatsApp` |

**Steps:** same as Task 8.

---

## Task 11: Run full suite + visual smoke test + commit final

**Step 1: Run full test suite**

Run test command at top of plan.

Expected: 250 baseline + N per-app tests (target 280-290 total) all pass.

**Step 2: Build the app**

Run build command. Expect clean build, no warnings.

**Step 3: Visual smoke test**

Launch `kSpaceClean.app` from build folder. Run a scan. Verify:
- 6 top-level categories visible (skeletons OK for empty)
- AI tools category shows Claude Code / Cursor / ChatGPT entries
- Each app row expands to 2-4 action rows (缓存 / 日志 / 数据)
- "显示过滤掉的项" toggle reveals sub-100KB files
- No "应用缓存 → 应用缓存" duplicate names

**Step 4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && \
git status  # verify no uncommitted changes
```

If clean, no commit needed. If anything left over, commit with `chore: post-v2-scan-pipeline verification`.

---

## Execution Handoff

This plan is complete and saved to `docs/superpowers/plans/2026-08-01-kspaceclean-scan-pipeline-v2.md`.

**Recommended execution: subagent-driven-development** — dispatch a fresh implementer subagent per task, run a spec-compliance + code-quality review between tasks, and a broad final review at the end. Tasks 8/9/10 (per-app rule research) are best delegated to per-batch subagents with isolated context.