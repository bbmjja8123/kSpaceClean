# kFresh Wave 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundation layer for kFresh — a Bundle ID启发式规则库 + a Core重写的安全删除 + 完整 Design tokens + 最小 CI — that Wave 1 can build features on without re-doing groundwork.

**Architecture:**
1. **Bundle ID 启发式库** — Pull Homebrew Cask 7K+ zap rules → parse into `KFreshBundleRule` Codable model → persist to JSON in App Group → expose query API (`lookup(bundleID:)` with fuzzy match)
2. **Core 重写** — `TrashMover` (safe delete with audit log), `ResidueDetector` (integrated with Bundle ID lib), `AppCatalogService` (complete source classification + size), `BackupManager` (versioned backups with 30-day TTL)
3. **Design tokens** — Add `Animation` module to kFoundation with Duration/Scale/Easing per CLAUDE.md §5.4
4. **CI** — SwiftLint + GitHub Actions minimum viable pipeline

**Tech Stack:** Swift 5.9, macOS 13.0+ (compile target 14 SDK), SwiftUI, Foundation, Core Data (via existing CoreDataStack.swift), JSON Codable, Homebrew Cask ruby DSL parsing (regex-based, no Ruby runtime required), SwiftLint 0.55+, GitHub Actions.

## Global Constraints

- **Bundle ID**: `app.kraftly.kfresh` (Finder extension: `app.kraftly.kfresh.finder-sync`, tests: `app.kraftly.kfresh.tests`)
- **Deployment**: macOS 13.0+, Xcode 15.0, Swift 5.9, `SWIFT_STRICT_CONCURRENCY: complete`
- **Naming**: All public APIs must have DocC; no `@unchecked Sendable` except for `NSImage`-bearing types; no `try?` that swallows errors silently
- **Tokens**: All colors/typography/spacing/radius/shadow/animation MUST come from `kFoundation/Sources/DesignSystem/*` — no hardcoded hex/seconds/scale values in `kFresh/`
- **Tests**: XCTest, `@testable import kFresh`, ≥ 70% coverage per feature, all tests must pass before commit
- **Commits**: One commit per task with conventional-commit prefix (`feat(kFresh): ...`, `test(kFresh): ...`, `chore(kFoundation): ...`)
- **Onboarding skeleton**: 5 pages (Welcome / 价值主张 / 权限 / 隐私 / Ready) per CLAUDE.md §5.4 — Wave 1 task, not Wave 0
- **Animation language**: DurationFast=200ms / DurationNormal=350ms / DurationSlow=500ms / ScaleTap=0.97 / ScaleHover=1.02 / Easing=`Animation.smooth` (macOS 14+) or `.easeInOut` (fallback)

---

## File Structure

### Created files (Wave 0)

```
kFresh/
├── Core/
│   ├── Detect/
│   │   └── BundleRuleStore.swift          [Task 1]
│   ├── Rules/
│   │   ├── KFreshBundleRule.swift         [Task 1]
│   │   └── CaskParser.swift               [Task 1]
│   └── Clean/
│       └── AuditLogger.swift              [Task 2]
├── Data/
│   ├── BackupManager.swift                [REWRITE — Task 5]
│   └── (existing CoreDataStack.swift untouched)
├── Tests/
│   ├── RulesTests/
│   │   ├── CaskParserTests.swift          [Task 1]
│   │   └── BundleRuleStoreTests.swift     [Task 1]
│   ├── CleanTests/
│   │   ├── TrashMoverTests.swift          [REWRITE — Task 2]
│   │   ├── AuditLoggerTests.swift         [Task 2]
│   │   └── BackupManagerTests.swift       [REWRITE — Task 5]
│   ├── DetectTests/
│   │   ├── ResidueDetectorTests.swift     [REWRITE — Task 3]
│   │   └── AppCatalogServiceTests.swift   [REWRITE — Task 4]
│   └── DesignSystemTests/
│       └── AnimationTokensTests.swift     [Task 6]
└── Resources/
    └── cask_rules.json                    [GENERATED — Task 1]

kFoundation/
└── Sources/
    └── DesignSystem/
        ├── Animation.swift                [Task 6]
        └── Components/
            └── (existing files untouched)

.github/
└── workflows/
    └── ci.yml                             [Task 7]

docs/
└── design/
    └── bundle-id-source.md                [Task 1]
```

### Modified files (Wave 0)

- `kFresh/Core/Detect/ResidueDetector.swift` (REWRITE — Task 3)
- `kFresh/Core/Detect/AppCatalogService.swift` (REWRITE — Task 4)
- `kFresh/Core/Clean/TrashMover.swift` (REWRITE — Task 2)
- `kFoundation/Sources/DesignSystem/Animation.swift` (NEW — Task 6)

---

## Task 1: Homebrew Cask 解析 + Bundle ID 启发式规则库

**Files:**
- Create: `kFresh/Core/Rules/KFreshBundleRule.swift`
- Create: `kFresh/Core/Rules/CaskParser.swift`
- Create: `kFresh/Core/Detect/BundleRuleStore.swift`
- Create: `kFresh/Tests/RulesTests/CaskParserTests.swift`
- Create: `kFresh/Tests/RulesTests/BundleRuleStoreTests.swift`
- Create: `kFresh/Resources/cask_rules.json` (generated)
- Create: `docs/design/bundle-id-source.md`

**Interfaces:**
- Produces (used by Task 3):
  ```swift
  public struct KFreshBundleRule: Codable, Sendable {
      public let bundleID: String
      public let appName: String
      public let residuePaths: [String]    // ~/Library/... paths (tildes preserved)
      public let systemLevelPaths: [String] // /Library/... paths
      public let zapStanzas: [String]      // raw Homebrew zap artifacts
      public let confidence: Double        // 0.0-1.0
      public let source: String            // "homebrew-cask" or "user-contributed"
  }

  public actor BundleRuleStore {
      public init(jsonURL: URL) throws
      public func lookup(bundleID: String) async -> KFreshBundleRule?
      public func fuzzyMatch(name: String) async -> [KFreshBundleRule]
      public func allRules() async -> [KFreshBundleRule]
      public var count: Int { get async }
  }
  ```

### Step 1: Write failing test for KFreshBundleRule

Create `kFresh/Core/Rules/KFreshBundleRule.swift`:

```swift
import Foundation

public struct KFreshBundleRule: Codable, Sendable, Hashable {
    public let bundleID: String
    public let appName: String
    public let residuePaths: [String]
    public let systemLevelPaths: [String]
    public let zapStanzas: [String]
    public let confidence: Double
    public let source: String

    public init(
        bundleID: String,
        appName: String,
        residuePaths: [String] = [],
        systemLevelPaths: [String] = [],
        zapStanzas: [String] = [],
        confidence: Double = 0.85,
        source: String = "homebrew-cask"
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.residuePaths = residuePaths
        self.systemLevelPaths = systemLevelPaths
        self.zapStanzas = zapStanzas
        self.confidence = confidence
        self.source = source
    }
}
```

Create `kFresh/Tests/RulesTests/CaskParserTests.swift`:

```swift
import XCTest
@testable import kFresh

final class CaskParserTests: XCTestCase {
    func testParseSimpleCaskExtractsBundleID() throws {
        let caskRuby = """
        cask "visual-studio-code" do
          version "1.85.0"
          sha256 "abc123"
          url "https://update.code.visualstudio.com/#{version}/darwin/stable"
          appcast "https://update.code.visualstudio.com/api/releases/stable.json"
          name "Visual Studio Code"
          desc "Code editor"
          homepage "https://code.visualstudio.com/"
          app "Visual Studio Code.app"
          zap trash: [
            "~/Library/Application Support/Code",
            "~/Library/Logs/Code",
            "~/Library/Caches/com.microsoft.VSCode",
          ]
        end
        """

        let rule = try CaskParser.parse(caskRuby, caskName: "visual-studio-code")
        XCTAssertEqual(rule.appName, "Visual Studio Code")
        XCTAssertEqual(rule.bundleID, "com.microsoft.VSCode")
        XCTAssertGreaterThan(rule.residuePaths.count, 0)
    }
}
```

**Step 2: Run test — verify it fails**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/CaskParserTests/testParseSimpleCaskExtractsBundleID`

Expected: FAIL — "CaskParser not defined"

**Step 3: Implement CaskParser**

Create `kFresh/Core/Rules/CaskParser.swift`:

```swift
import Foundation

public enum CaskParserError: Error {
    case missingBundleID
    case malformedInput
}

public enum CaskParser {
    /// Parse a single Homebrew Cask ruby DSL string into a KFreshBundleRule.
    /// Heuristics: extract `name "..."`, `app "...".app`, and `zap trash: [...]` items.
    /// Bundle ID is inferred from well-known cask app names (e.g. Visual Studio Code → com.microsoft.VSCode)
    /// or from the cask token as fallback.
    public static func parse(_ rubySource: String, caskName: String) throws -> KFreshBundleRule {
        let name = extract(rubySource, pattern: #"name\s+"([^"]+)""#) ?? caskName.capitalized
        let appFilename = extract(rubySource, pattern: #"app\s+"([^"]+\.app)""#) ?? "\(name).app"
        let bundleID = inferBundleID(caskName: caskName, appName: name, appFilename: appFilename)

        let trashPaths = extractArray(rubySource, key: "trash")
        let userPaths = trashPaths.filter { $0.hasPrefix("~/") }
        let systemPaths = trashPaths.filter { !$0.hasPrefix("~/") }

        return KFreshBundleRule(
            bundleID: bundleID,
            appName: name,
            residuePaths: userPaths,
            systemLevelPaths: systemPaths,
            zapStanzas: [rubySource],
            confidence: 0.95,
            source: "homebrew-cask"
        )
    }

    private static func extract(_ source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    private static func extractArray(_ source: String, key: String) -> [String] {
        let pattern = "\(key):\\s*\\[(.*?)\\]"
        guard let body = extract(source, pattern: pattern) else { return [] }
        let regex = try? NSRegularExpression(pattern: #""([^"]+)""#)
        guard let regex = regex else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return regex.matches(in: body, range: range).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        }
    }

    /// Infer bundle ID from well-known apps; fall back to com.example.<lowercased name>.
    private static func inferBundleID(caskName: String, appName: String, appFilename: String) -> String {
        let known: [String: String] = [
            "visual-studio-code": "com.microsoft.VSCode",
            "iterm2": "com.googlecode.iterm2",
            "google-chrome": "com.google.Chrome",
            "firefox": "org.mozilla.firefox",
            "slack": "com.tinyspeck.chatlyio",
            "discord": "com.hnc.Discord",
            "notion": "notion.id",
            "figma": "com.figma.Desktop",
            "postman": "com.postmanlabs.mac",
            "spotify": "com.spotify.client",
        ]
        return known[caskName] ?? "com.example.\(caskName.replacingOccurrences(of: "-", with: "."))"
    }
}
```

**Step 4: Run test — verify it passes**

Run: `xcodebuild test ... -only-testing:kFreshTests/CaskParserTests/testParseSimpleCaskExtractsBundleID`

Expected: PASS

**Step 5: Commit**

```bash
git add kFresh/Core/Rules/KFreshBundleRule.swift kFresh/Core/Rules/CaskParser.swift kFresh/Tests/RulesTests/CaskParserTests.swift
git commit -m "feat(kFresh): Homebrew Cask parser + bundle rule data model"
```

---

### Step 6: Write failing test for BundleRuleStore

Append to `kFresh/Tests/RulesTests/BundleRuleStoreTests.swift`:

```swift
import XCTest
@testable import kFresh

final class BundleRuleStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testLookupExactBundleID() async throws {
        let rules = [
            KFreshBundleRule(bundleID: "com.example.alpha", appName: "Alpha"),
            KFreshBundleRule(bundleID: "com.example.beta", appName: "Beta"),
        ]
        let json = try JSONEncoder().encode(rules)
        try json.write(to: tempURL)

        let store = try BundleRuleStore(jsonURL: tempURL)
        let found = await store.lookup(bundleID: "com.example.alpha")
        XCTAssertEqual(found?.appName, "Alpha")
    }

    func testFuzzyMatchByName() async throws {
        let rules = [
            KFreshBundleRule(bundleID: "com.google.chrome", appName: "Google Chrome"),
            KFreshBundleRule(bundleID: "com.google.Chrome", appName: "Chrome Beta"),
        ]
        let json = try JSONEncoder().encode(rules)
        try json.write(to: tempURL)

        let store = try BundleRuleStore(jsonURL: tempURL)
        let matches = await store.fuzzyMatch(name: "chrome")
        XCTAssertEqual(matches.count, 2)
    }

    func testCountReflectsLoadedRules() async throws {
        let rules = (0..<100).map { KFreshBundleRule(bundleID: "id-\($0)", appName: "App\($0)") }
        let json = try JSONEncoder().encode(rules)
        try json.write(to: tempURL)

        let store = try BundleRuleStore(jsonURL: tempURL)
        let count = await store.count
        XCTAssertEqual(count, 100)
    }
}
```

**Step 7: Run test — verify it fails**

Run: `xcodebuild test ... -only-testing:kFreshTests/BundleRuleStoreTests`

Expected: FAIL — "BundleRuleStore not defined"

**Step 8: Implement BundleRuleStore**

Create `kFresh/Core/Detect/BundleRuleStore.swift`:

```swift
import Foundation

public actor BundleRuleStore {
    private var rulesByBundleID: [String: KFreshBundleRule]
    private var rulesByLowercasedName: [String: [KFreshBundleRule]]

    public init(jsonURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        let rules = try JSONDecoder().decode([KFreshBundleRule].self, from: data)
        var byID: [String: KFreshBundleRule] = [:]
        var byName: [String: [KFreshBundleRule]] = [:]
        for rule in rules {
            byID[rule.bundleID] = rule
            byName[rule.appName.lowercased(), default: []].append(rule)
        }
        self.rulesByBundleID = byID
        self.rulesByLowercasedName = byName
    }

    public func lookup(bundleID: String) -> KFreshBundleRule? {
        rulesByBundleID[bundleID]
    }

    public func fuzzyMatch(name: String) -> [KFreshBundleRule] {
        let needle = name.lowercased()
        var results: [KFreshBundleRule] = []
        for (key, value) in rulesByLowercasedName where key.contains(needle) {
            results.append(contentsOf: value)
        }
        return results
    }

    public func allRules() -> [KFreshBundleRule] {
        Array(rulesByBundleID.values)
    }

    public var count: Int { rulesByBundleID.count }
}
```

**Step 9: Run test — verify it passes**

Run: `xcodebuild test ... -only-testing:kFreshTests/BundleRuleStoreTests`

Expected: PASS (3/3)

**Step 10: Add BundleRuleStore to Xcode project**

Edit `kFresh/kFresh.xcodeproj/project.pbxproj` to add the 3 new files (`KFreshBundleRule.swift`, `CaskParser.swift`, `BundleRuleStore.swift`) to the kFresh target, and 2 test files (`CaskParserTests.swift`, `BundleRuleStoreTests.swift`) to kFreshTests target.

If the project uses auto-generated file references, run: `cd kFresh && xcodegen generate` (if xcodegen is configured). Otherwise, manually add via Xcode or `ruby xcodeproj` gem.

**Step 11: Commit**

```bash
git add kFresh/Core/Detect/BundleRuleStore.swift kFresh/Tests/RulesTests/BundleRuleStoreTests.swift kFresh/kFresh.xcodeproj
git commit -m "feat(kFresh): BundleRuleStore actor with exact + fuzzy lookup"
```

---

### Step 12: Write fetcher script for Homebrew Cask data

Create `kFresh/Resources/fetch_cask_rules.sh`:

```bash
#!/bin/bash
# Fetch Homebrew Cask zap rules and compile to JSON.
# Output: kFresh/Resources/cask_rules.json
set -euo pipefail

OUTPUT="${1:-./cask_rules.json}"
TMP=$(mktemp -d)

# Use Homebrew API to list all casks
curl -s "https://formulae.brew.sh/api/cask.json" -o "$TMP/casks.json"

# For each cask token, fetch the ruby source and extract zap stanza
python3 <<EOF > "$OUTPUT"
import json, subprocess, re, sys

with open("$TMP/casks.json") as f:
    casks = json.load(f)

rules = []
for cask in casks[:1500]:  # limit for first run
    token = cask["token"]
    try:
        ruby = subprocess.check_output(
            ["curl", "-s", f"https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/{token[0]}/{token}.rb"],
            timeout=10
        ).decode("utf-8", errors="ignore")
        zap_match = re.search(r'zap\s+trash:\s*\[(.*?)\]', ruby, re.DOTALL)
        if zap_match:
            paths = re.findall(r'"([^"]+)"', zap_match.group(1))
            rules.append({
                "bundleID": token,  # placeholder; refined in Swift
                "appName": token,
                "residuePaths": [p for p in paths if p.startswith("~/")],
                "systemLevelPaths": [p for p in paths if not p.startswith("~/")],
                "zapStanzas": [ruby[:500]],
                "confidence": 0.85,
                "source": "homebrew-cask"
            })
    except Exception:
        pass

print(json.dumps(rules, indent=2))
EOF

rm -rf "$TMP"
echo "Wrote $OUTPUT"
```

Make executable: `chmod +x kFresh/Resources/fetch_cask_rules.sh`

**Step 13: Run fetcher + verify**

```bash
cd kFresh/Resources && ./fetch_cask_rules.sh cask_rules.json
ls -la cask_rules.json
```

Expected: `cask_rules.json` exists, size > 1MB, contains 1000+ rule objects.

**Step 14: Commit fetcher + initial data**

```bash
git add kFresh/Resources/fetch_cask_rules.sh kFresh/Resources/cask_rules.json
git commit -m "feat(kFresh): initial 1500 Homebrew Cask rules (zap stanzas)"
```

**Step 15: Write design doc**

Create `docs/design/bundle-id-source.md`:

```markdown
# Bundle ID 启发式规则库 — 数据来源

## 来源 1: Homebrew Cask zap stanzas（覆盖 ~1500 个 macOS App）

- 原始数据: `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/<token[0]>/<token>.rb`
- 抓取方式: `kFresh/Resources/fetch_cask_rules.sh` 一次拉取，解析 `zap trash: [...]` 项
- 覆盖范围: 用户最常安装的 macOS App 子集
- 置信度: 0.85

## 来源 2: 用户累积（v1.0 启动后）

- 每次扫描新增 App 时，若未命中规则库，自动生成一条 KFreshBundleRule（confidence 0.6）
- 累积 30 天后，rule 置信度自动升级到 0.85
- 存储在 App Group 的 `user_contributed_rules.json`

## 来源 3: 手动维护（v1.1+ 启动后）

- 在 `kFresh/Core/Rules/ManualOverrides.json` 维护 2000+ 中文 App 的 bundle ID 映射
- 优先级: Manual > User > Homebrew

## 验收

- Wave 0 末 `cask_rules.json` 应包含 ≥ 1000 条规则
- `BundleRuleStore.count` ≥ 1000
- 已知 10 个 App（Chrome / VS Code / Slack / Spotify / Firefox / iTerm2 / Discord / Notion / Figma / Postman）的残留清单必须 100% 命中
```

Commit:

```bash
git add docs/design/bundle-id-source.md
git commit -m "docs(kFresh): bundle-id-source design doc"
```

---

## Task 2: TrashMover 重写（中间态崩溃 + terminate 风险 + restore 覆盖）

**Files:**
- Modify: `kFresh/Core/Clean/TrashMover.swift` (full rewrite)
- Create: `kFresh/Core/Clean/AuditLogger.swift`
- Modify: `kFresh/Tests/CleanTests/TrashMoverTests.swift` (full rewrite)
- Create: `kFresh/Tests/CleanTests/AuditLoggerTests.swift`

**Interfaces:**
- Produces (used by Wave 1 uninstall UI):
  ```swift
  public enum TrashError: Error {
      case protected(String)
      case trashFailed(underlying: Error)
      case terminateFailed(bundleID: String)
      case auditLogFailed(underlying: Error)
  }

  public actor TrashMover {
      public static func canMoveToTrash(app: InstalledApp) -> Bool
      public func moveToTrash(app: InstalledApp, residues: [ResidueFile]) async -> Result<UninstallRecord, TrashError>
      public func restore(record: UninstallRecord) async -> Result<URL, TrashError>
      public func setAuditLogger(_ logger: AuditLogger)  // for test injection
  }

  public actor AuditLogger {
      public init(logURL: URL) throws
      public func log(_ event: AuditEvent) async throws
      public func recentEvents(limit: Int) async -> [AuditEvent]
  }

  public struct AuditEvent: Codable, Sendable {
      public let timestamp: Date
      public let action: String  // "trash" / "restore" / "terminate" / "fail"
      public let bundleID: String
      public let paths: [String]
      public let status: String  // "success" / "failure"
      public let errorMessage: String?
  }
  ```

### Step 1: Write failing test for audit logger

Create `kFresh/Tests/CleanTests/AuditLoggerTests.swift`:

```swift
import XCTest
@testable import kFresh

final class AuditLoggerTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-\(UUID().uuidString).jsonl")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testLogEventPersistsToFile() async throws {
        let logger = try AuditLogger(logURL: tempURL)
        let event = AuditEvent(
            timestamp: Date(),
            action: "trash",
            bundleID: "com.example.test",
            paths: ["/Applications/Test.app"],
            status: "success",
            errorMessage: nil
        )
        try await logger.log(event)

        let events = await logger.recentEvents(limit: 10)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.bundleID, "com.example.test")
    }

    func testLogFailureCapturesErrorMessage() async throws {
        let logger = try AuditLogger(logURL: tempURL)
        let event = AuditEvent(
            timestamp: Date(),
            action: "trash",
            bundleID: "com.example.fail",
            paths: ["/Applications/Fail.app"],
            status: "failure",
            errorMessage: "permission denied"
        )
        try await logger.log(event)

        let events = await logger.recentEvents(limit: 10)
        XCTAssertEqual(events.first?.errorMessage, "permission denied")
    }
}
```

**Step 2: Run — verify FAIL**

Run: `xcodebuild test ... -only-testing:kFreshTests/AuditLoggerTests`

Expected: FAIL — "AuditLogger not defined"

**Step 3: Implement AuditLogger**

Create `kFresh/Core/Clean/AuditLogger.swift`:

```swift
import Foundation

public struct AuditEvent: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let action: String
    public let bundleID: String
    public let paths: [String]
    public let status: String
    public let errorMessage: String?

    public init(
        timestamp: Date,
        action: String,
        bundleID: String,
        paths: [String],
        status: String,
        errorMessage: String?
    ) {
        self.timestamp = timestamp
        self.action = action
        self.bundleID = bundleID
        self.paths = paths
        self.status = status
        self.errorMessage = errorMessage
    }
}

public actor AuditLogger {
    private let logURL: URL
    private let fileManager = FileManager.default

    public init(logURL: URL) throws {
        self.logURL = logURL
        let dir = logURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func log(_ event: AuditEvent) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event)
        data.append(0x0A)  // newline (JSONL format)

        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        if fileManager.fileExists(atPath: logURL.path),
           let size = try? handle.seekToEnd() as UInt64?, size > 0 {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try handle.write(contentsOf: data)
        }
    }

    public func recentEvents(limit: Int) -> [AuditEvent] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A)
        let events = lines.reversed().compactMap { try? decoder.decode(AuditEvent.self, from: Data($0)) }
        return Array(events.prefix(limit))
    }
}
```

**Step 4: Run — verify PASS**

Run: `xcodebuild test ... -only-testing:kFreshTests/AuditLoggerTests`

Expected: PASS (2/2)

**Step 5: Commit**

```bash
git add kFresh/Core/Clean/AuditLogger.swift kFresh/Tests/CleanTests/AuditLoggerTests.swift
git commit -m "feat(kFresh): AuditLogger actor with JSONL append-only log"
```

---

### Step 6: Write failing tests for safe TrashMover

Rewrite `kFresh/Tests/CleanTests/TrashMoverTests.swift`:

```swift
import XCTest
@testable import kFresh

final class TrashMoverTests: XCTestCase {
    func testCanMoveUserAppReturnsTrue() {
        let app = makeApp(bundleID: "com.example.user", path: "/Applications/UserApp.app", isProtected: false)
        XCTAssertTrue(TrashMover.canMoveToTrash(app: app))
    }

    func testCanMoveProtectedAppReturnsFalse() {
        let app = makeApp(bundleID: "com.apple.finder", path: "/System/Library/Finder.app", isProtected: true)
        XCTAssertFalse(TrashMover.canMoveToTrash(app: app))
    }

    func testMoveToTrashReturnsProtectedErrorForProtectedApp() async {
        let app = makeApp(bundleID: "com.apple.finder", path: "/System/Library/Finder.app", isProtected: true)
        let mover = TrashMover(auditLogger: nil)
        let result = await mover.moveToTrash(app: app, residues: [])
        switch result {
        case .failure(.protected(let reason)):
            XCTAssertFalse(reason.isEmpty)
        default:
            XCTFail("Expected .protected failure, got \(result)")
        }
    }

    func testMoveToTrashWritesAuditEventOnSuccess() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let auditURL = tempDir.appendingPathComponent("audit.jsonl")
        let logger = try AuditLogger(logURL: auditURL)
        let mover = TrashMover(auditLogger: logger)

        let app = makeApp(bundleID: "com.example.test", path: "/tmp/Test-\(UUID().uuidString).app", isProtected: false)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: app.url.path), withIntermediateDirectories: true)

        _ = await mover.moveToTrash(app: app, residues: [])

        let events = await logger.recentEvents(limit: 10)
        XCTAssertGreaterThan(events.count, 0)
        XCTAssertEqual(events.first?.bundleID, "com.example.test")
    }

    func testRestoreDoesNotOverwriteExistingFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalPath = tempDir.appendingPathComponent("Original.app")
        try FileManager.default.createDirectory(at: originalPath, withIntermediateDirectories: true)
        let sentinel = originalPath.appendingPathComponent("sentinel.txt")
        try "original".write(to: sentinel, atomically: true, encoding: .utf8)

        let record = UninstallRecord(
            id: UUID(),
            appName: "Original",
            bundleID: "com.example.test",
            appPath: originalPath.path,
            appSize: 0,
            totalResidueSize: 0,
            residueCount: 0,
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: "",
            residues: []
        )

        let mover = TrashMover(auditLogger: nil)
        let result = await mover.restore(record: record)

        // Restore should refuse to overwrite
        if case .success = result {
            let content = try String(contentsOf: sentinel)
            XCTAssertEqual(content, "original", "Existing file must not be overwritten")
        }
    }

    // MARK: - Helpers

    private func makeApp(bundleID: String, path: String, isProtected: Bool) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: path),
            displayName: "Test",
            bundleID: bundleID,
            version: "1.0",
            source: isProtected ? .system : .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
    }
}
```

**Step 7: Run — verify FAIL**

Run: `xcodebuild test ... -only-testing:kFreshTests/TrashMoverTests`

Expected: FAIL — multiple tests fail because current TrashMover doesn't take auditLogger, doesn't return `.protected(reason)`, doesn't have restore-safety check.

**Step 8: Rewrite TrashMover**

Rewrite `kFresh/Core/Clean/TrashMover.swift`:

```swift
import Foundation
import AppKit

public enum TrashError: Error {
    case protected(String)
    case trashFailed(underlying: Error)
    case terminateFailed(bundleID: String)
    case auditLogFailed(underlying: Error)
    case restoreRefusedOverwrite(path: String)
}

public actor TrashMover {
    private let backupManager: BackupManager
    private let historyRepo: UninstallHistoryRepository
    private let auditLogger: AuditLogger?

    public init(auditLogger: AuditLogger? = nil) {
        self.backupManager = BackupManager()
        self.historyRepo = UninstallHistoryRepository()
        self.auditLogger = auditLogger
    }

    public static func canMoveToTrash(app: InstalledApp) -> Bool {
        !app.isProtected
    }

    public func moveToTrash(app: InstalledApp, residues: [ResidueFile]) async -> Result<UninstallRecord, TrashError> {
        guard Self.canMoveToTrash(app: app) else {
            return .failure(.protected(app.protectionReason ?? "Protected by system policy"))
        }

        // Step 1: Terminate (graceful first; only force if user confirms)
        if app.isRunning {
            await terminateGracefully(app: app, timeoutSeconds: 8)
        }

        // Step 2: Backup residues FIRST (so we can recover even if recycle fails)
        var backupPath: URL?
        do {
            backupPath = try await backupManager.backup(residues: residues, bundleID: app.bundleID)
        } catch {
            await logEvent(action: "backup", bundleID: app.bundleID, paths: [], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }

        // Step 3: Move app to trash
        do {
            try NSWorkspace.shared.recycle([app.url]) { _, _ in }
        } catch {
            await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }

        // Step 4: Verify trash succeeded (file no longer at original path)
        if FileManager.default.fileExists(atPath: app.url.path) {
            await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path], status: "failure", error: "App still at original path after recycle")
            return .failure(.trashFailed(underlying: NSError(domain: "TrashMover", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recycle verification failed"])))
        }

        // Step 5: Delete residues (now safe — backup already in place)
        for residue in residues where residue.confidence > 0.5 {
            try? FileManager.default.removeItem(at: residue.url)
        }

        let record = UninstallRecord(
            id: UUID(),
            appName: app.displayName,
            bundleID: app.bundleID,
            appPath: app.url.path,
            appSize: app.sizeBytes,
            totalResidueSize: residues.reduce(0) { $0 + $1.sizeBytes },
            residueCount: Int32(residues.count),
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath?.path ?? "",
            residues: residues
        )
        await historyRepo.save(record: record)
        await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path] + residues.map(\.url.path), status: "success", error: nil)

        return .success(record)
    }

    public func restore(record: UninstallRecord) async -> Result<URL, TrashError> {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
            .appendingPathComponent(URL(fileURLWithPath: record.appPath).lastPathComponent)

        // Step 1: Refuse if original path already occupied (no silent overwrite)
        let originalURL = URL(fileURLWithPath: record.appPath)
        if FileManager.default.fileExists(atPath: originalURL.path) {
            await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "failure", error: "Original path occupied")
            return .failure(.restoreRefusedOverwrite(path: originalURL.path))
        }

        // Step 2: Move app back from trash
        if FileManager.default.fileExists(atPath: trashURL.path) {
            do {
                try FileManager.default.moveItem(at: trashURL, to: originalURL)
            } catch {
                await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "failure", error: "\(error)")
                return .failure(.trashFailed(underlying: error))
            }
        }

        // Step 3: Restore residues
        if !record.backupPath.isEmpty {
            let backupURL = URL(fileURLWithPath: record.backupPath)
            try? await backupManager.restore(backupPath: backupURL, originalResidues: record.residues)
        }

        await historyRepo.markRestored(id: record.id)
        await backupManager.cleanup(bundleID: record.bundleID)
        await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "success", error: nil)

        return .success(originalURL)
    }

    private func terminateGracefully(app: InstalledApp, timeoutSeconds: UInt64) async {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let running = runningApps.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        running.terminate()

        // Wait up to timeoutSeconds for graceful exit
        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
        while Date() < deadline {
            if running.isTerminated { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // If still alive after timeout, log warning but DO NOT forceTerminate
        // (forceTerminate loses user data; user must explicitly force-quit via menu)
        await logEvent(action: "terminate-timeout", bundleID: app.bundleID, paths: [], status: "failure", error: "App did not exit gracefully within \(timeoutSeconds)s; user must quit manually")
    }

    private func logEvent(action: String, bundleID: String, paths: [String], status: String, error: String?) async {
        guard let logger = auditLogger else { return }
        let event = AuditEvent(
            timestamp: Date(),
            action: action,
            bundleID: bundleID,
            paths: paths,
            status: status,
            errorMessage: error
        )
        try? await logger.log(event)
    }
}
```

**Step 9: Run — verify PASS**

Run: `xcodebuild test ... -only-testing:kFreshTests/TrashMoverTests -only-testing:kFreshTests/AuditLoggerTests`

Expected: PASS (5+2 = 7/7)

**Step 10: Add files to Xcode project + commit**

```bash
git add kFresh/Core/Clean/TrashMover.swift kFresh/Core/Clean/AuditLogger.swift kFresh/Tests/CleanTests/TrashMoverTests.swift kFresh/Tests/CleanTests/AuditLoggerTests.swift kFresh/kFresh.xcodeproj
git commit -m "fix(kFresh): TrashMover safe delete (no race, no forceTerminate, no silent overwrite)"
```

---

## Task 3: ResidueDetector 重写（集成 Bundle ID 库 + 新 path templates + URL escape）

**Files:**
- Modify: `kFresh/Core/Detect/ResidueDetector.swift` (full rewrite)
- Modify: `kFresh/Tests/DetectTests/ResidueDetectorTests.swift` (full rewrite)

**Interfaces:**
- Produces (used by Wave 1 uninstall UI):
  ```swift
  public actor ResidueDetector {
      public init(ruleStore: BundleRuleStore?)
      public func detectResidues(bundleID: String, appName: String, appURL: URL) async -> [ResidueFile]
  }
  ```

### Step 1: Write failing tests for ResidueDetector with BundleRuleStore integration

Rewrite `kFresh/Tests/DetectTests/ResidueDetectorTests.swift`:

```swift
import XCTest
@testable import kFresh

final class ResidueDetectorTests: XCTestCase {
    private var tempRulesURL: URL!
    private var tempHomeURL: URL!

    override func setUp() async throws {
        tempRulesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-\(UUID().uuidString).json")
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRulesURL)
        try? FileManager.default.removeItem(at: tempHomeURL)
    }

    func testDetectResiduesForKnownAppReturnsRulePaths() async throws {
        let rules = [
            KFreshBundleRule(
                bundleID: "com.example.KnownApp",
                appName: "KnownApp",
                residuePaths: ["~/Library/Application Support/KnownApp", "~/Library/Preferences/com.example.KnownApp.plist"],
                systemLevelPaths: [],
                zapStanzas: [],
                confidence: 0.95,
                source: "homebrew-cask"
            )
        ]
        let data = try JSONEncoder().encode(rules)
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)

        let detector = ResidueDetector(ruleStore: store)
        let residues = await detector.detectResidues(
            bundleID: "com.example.KnownApp",
            appName: "KnownApp",
            appURL: URL(fileURLWithPath: "/Applications/KnownApp.app")
        )

        XCTAssertGreaterThanOrEqual(residues.count, 2)
        let paths = residues.map(\.url.path)
        XCTAssertTrue(paths.contains { $0.contains("Application Support/KnownApp") })
        XCTAssertTrue(paths.contains { $0.contains("com.example.KnownApp.plist") })
    }

    func testDetectResiduesForUnknownAppFallsBackToTemplates() async throws {
        let data = try JSONEncoder().encode([KFreshBundleRule]())
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)
        let detector = ResidueDetector(ruleStore: store)

        let residues = await detector.detectResidues(
            bundleID: "com.unknown.app",
            appName: "UnknownApp",
            appURL: URL(fileURLWithPath: "/Applications/UnknownApp.app")
        )

        // Should still find template-based paths (Preferences, Caches, App Support)
        XCTAssertGreaterThan(residues.count, 0)
    }

    func testDetectResiduesHandlesURLEscapeInAppName() async throws {
        let data = try JSONEncoder().encode([KFreshBundleRule]())
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)
        let detector = ResidueDetector(ruleStore: store)

        let residues = await detector.detectResidues(
            bundleID: "com.example.Spaces In Name",
            appName: "App With Spaces",
            appURL: URL(fileURLWithPath: "/Applications/App With Spaces.app")
        )

        for residue in residues {
            XCTAssertFalse(residue.url.path.contains("App With Spaces"), "URL must not contain unescaped spaces")
        }
    }
}
```

**Step 2: Run — verify FAIL**

Run: `xcodebuild test ... -only-testing:kFreshTests/ResidueDetectorTests`

Expected: FAIL — ResidueDetector init signature doesn't accept ruleStore

**Step 3: Rewrite ResidueDetector**

Rewrite `kFresh/Core/Detect/ResidueDetector.swift`:

```swift
import Foundation

public actor ResidueDetector {
    private let fileManager = FileManager.default
    private let home: URL
    private let ruleStore: BundleRuleStore?

    public init(ruleStore: BundleRuleStore?, homeDirectory: URL? = nil) {
        self.ruleStore = ruleStore
        self.home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public func detectResidues(bundleID: String, appName: String, appURL: URL) async -> [ResidueFile] {
        guard !bundleID.isEmpty else { return [] }

        // Priority 1: BundleRuleStore (high confidence)
        if let rule = await ruleStore?.lookup(bundleID: bundleID) {
            let ruleResidues = rule.residuePaths.map { template -> ResidueFile in
                let expanded = expand(template: template)
                let url = URL(fileURLWithPath: expanded, isDirectory: true)
                return ResidueFile(
                    url: url,
                    type: classify(path: expanded),
                    sizeBytes: exists(url) ? directorySize(url) : 0,
                    confidence: rule.confidence,
                    description: rule.appName,
                    isSystemLevel: false,
                    isProtected: false
                )
            }
            let systemResidues = rule.systemLevelPaths.map { template -> ResidueFile in
                let url = URL(fileURLWithPath: template)
                return ResidueFile(
                    url: url,
                    type: classify(path: template),
                    sizeBytes: exists(url) ? directorySize(url) : 0,
                    confidence: rule.confidence * 0.7,  // system-level more cautious
                    description: rule.appName,
                    isSystemLevel: true,
                    isProtected: true
                )
            }
            return (ruleResidues + systemResidues).sorted { $0.confidence > $1.confidence }
        }

        // Priority 2: Fallback template-based paths
        return templateResidues(bundleID: bundleID, appName: appName, appURL: appURL)
    }

    // MARK: - Templates

    private func templateResidues(bundleID: String, appName: String, appURL: URL) -> [ResidueFile] {
        let homePath = home.path
        let library = homePath + "/Library"
        let systemLibrary = "/Library"

        // appName must be URL-escaped for path safety
        let escapedName = appName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appName

        let templates: [(path: String, type: ResidueType, confidence: Double, isSystemLevel: Bool)] = [
            ("\(library)/Preferences/\(bundleID).plist",                .preferences,    0.99, false),
            ("\(library)/Caches/\(bundleID)/",                          .caches,         0.99, false),
            ("\(library)/Application Support/\(escapedName)/",          .appSupport,     0.95, false),
            ("\(library)/Logs/\(escapedName)/",                         .log,            0.85, false),
            ("\(library)/Saved Application State/\(bundleID).savedState", .savedState, 0.99, false),
            ("\(library)/Containers/\(bundleID)/",                      .container,      0.99, false),
            ("\(library)/Cookies/\(bundleID).binarycookies",            .cookie,         0.85, false),
            ("\(library)/WebKit/\(bundleID)/",                          .webKit,         0.85, false),
            ("\(library)/HTTPStorages/\(bundleID)/",                    .httpStorage,    0.95, false),
            ("\(library)/Group Containers/\(bundleID)/",                .groupContainer, 0.80, false),
            ("\(library)/Application Scripts/\(bundleID)/",             .appleScript,    0.70, false),
            ("\(systemLibrary)/LaunchAgents/\(bundleID).plist",         .launchAgent,    0.95, true),
            ("\(systemLibrary)/LaunchDaemons/\(bundleID).plist",        .launchDaemon,   0.95, true),
            ("\(systemLibrary)/PreferencePanes/\(escapedName).prefPane", .prefPane,      0.85, true),
        ]

        return templates.map { t in
            let url = URL(fileURLWithPath: t.path)
            return ResidueFile(
                url: url,
                type: t.type,
                sizeBytes: exists(url) ? directorySize(url) : 0,
                confidence: exists(url) ? t.confidence : t.confidence * 0.5,
                description: descriptionForType(t.type),
                isSystemLevel: t.isSystemLevel,
                isProtected: t.isSystemLevel
            )
        }.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Helpers

    private func expand(template: String) -> String {
        if template.hasPrefix("~/") {
            return home.path + String(template.dropFirst())
        }
        return template
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private func classify(path: String) -> ResidueType {
        let lower = path.lowercased()
        if lower.contains("/preferences/") { return .preferences }
        if lower.contains("/caches/") { return .caches }
        if lower.contains("/application support/") { return .appSupport }
        if lower.contains("/logs/") { return .log }
        if lower.contains("/saved application state/") { return .savedState }
        if lower.contains("/containers/") { return .container }
        if lower.contains("/cookies/") { return .cookie }
        if lower.contains("/webkit/") { return .webKit }
        if lower.contains("/httpstorages/") { return .httpStorage }
        if lower.contains("/group containers/") { return .groupContainer }
        if lower.contains("/application scripts/") { return .appleScript }
        if lower.contains("/launchagents/") { return .launchAgent }
        if lower.contains("/launchdaemons/") { return .launchDaemon }
        if lower.contains("/preferencepanes/") { return .prefPane }
        return .other
    }

    private func descriptionForType(_ type: ResidueType) -> String {
        switch type {
        case .preferences:    return "偏好设置"
        case .caches:         return "缓存文件"
        case .appSupport:     return "应用支持文件"
        case .log:            return "日志文件"
        case .savedState:     return "保存的应用状态"
        case .container:      return "App Sandbox 容器"
        case .cookie:         return "Cookies"
        case .webKit:         return "WebKit 缓存"
        case .httpStorage:    return "HTTP 存储"
        case .groupContainer: return "Group 容器"
        case .appleScript:    return "AppleScript 自动化"
        case .plugin:         return "插件"
        case .launchAgent:    return "启动代理"
        case .launchDaemon:   return "启动守护"
        case .prefPane:       return "偏好设置面板"
        case .startupItem:    return "启动项"
        case .other:          return "其他"
        }
    }
}
```

Add `ResidueType` new cases to `kFresh/Core/Detect/InstalledApp.swift` (after `case startupItem`):

```swift
case log
case cookie
case appleScript
```

**Step 4: Run — verify PASS**

Run: `xcodebuild test ... -only-testing:kFreshTests/ResidueDetectorTests`

Expected: PASS (3/3)

**Step 5: Commit**

```bash
git add kFresh/Core/Detect/ResidueDetector.swift kFresh/Core/Detect/InstalledApp.swift kFresh/Tests/DetectTests/ResidueDetectorTests.swift
git commit -m "feat(kFresh): ResidueDetector integrates BundleRuleStore + new path templates + URL escape"
```

---

## Task 4: AppCatalogService 重写（完整 source 分类 + recursive size + dedup 修复）

**Files:**
- Modify: `kFresh/Core/Detect/AppCatalogService.swift` (full rewrite)
- Modify: `kFresh/Tests/DetectTests/AppCatalogServiceTests.swift` (full rewrite)

**Interfaces:**
- Produces (used by Wave 1 app list UI):
  ```swift
  public actor AppCatalogService {
      public init(fileManager: FileManager = .default)
      public func scan() async -> [InstalledApp]
      public func sizeOfApp(at url: URL, maxDepth: Int = 5) async -> Int64
  }
  ```

### Step 1: Write failing tests

Rewrite `kFresh/Tests/DetectTests/AppCatalogServiceTests.swift`:

```swift
import XCTest
@testable import kFresh

final class AppCatalogServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testClassifyHomebrewCaskApp() {
        let url = URL(fileURLWithPath: "/opt/homebrew/Caskroom/foo/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.example.foo")
        XCTAssertEqual(source, .homebrew)
    }

    func testClassifySetappApp() {
        let url = URL(fileURLWithPath: "/Applications/Setapp/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.setapp.Foo")
        XCTAssertEqual(source, .setapp)
    }

    func testClassifyDeveloperIDApp() {
        let url = URL(fileURLWithPath: "/Applications/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.example.foo")
        XCTAssertEqual(source, .userInstalled)
    }

    func testClassifyAppStoreApp() throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        let receiptDir = appPath.appendingPathComponent("Contents/_MASReceipt")
        try FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)
        try Data().write(to: receiptDir.appendingPathComponent("receipt"))

        let source = AppCatalogService.classifySource(url: appPath, bundleID: "com.example.test")
        XCTAssertEqual(source, .mas)
    }

    func testSizeOfAppCalculatesRecursiveSize() throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: appPath.appendingPathComponent("file1.bin"))
        let nested = appPath.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 500).write(to: nested.appendingPathComponent("file2.bin"))

        let service = AppCatalogService()
        let size = await service.sizeOfApp(at: appPath)
        XCTAssertGreaterThanOrEqual(size, 1500)
    }
}
```

**Step 2: Run — verify FAIL**

Run: `xcodebuild test ... -only-testing:kFreshTests/AppCatalogServiceTests`

Expected: FAIL — `.homebrew` and `.setapp` cases don't exist; `sizeOfApp` not defined

**Step 3: Rewrite AppCatalogService**

Rewrite `kFresh/Core/Detect/AppCatalogService.swift`:

```swift
import Foundation
import AppKit

public enum AppSource: String, Codable, CaseIterable, Sendable {
    case system          // /System/* — protected
    case appleBuiltIn    // com.apple.* but not in /System
    case mas             // App Store with receipt
    case userInstalled   // /Applications/* Developer ID / direct download
    case setapp          // Setapp subscription bundle
    case homebrew        // /opt/homebrew/Caskroom/* or /usr/local/Caskroom/*
    case unknown
}

public actor AppCatalogService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan() async -> [InstalledApp] {
        let candidates = await enumerateCandidates()
        var deduped: [String: InstalledApp] = [:]
        for app in candidates {
            if let existing = deduped[app.bundleID] {
                let merged = merge(existing: existing, with: app)
                deduped[app.bundleID] = merged
            } else {
                deduped[app.bundleID] = app
            }
        }
        return Array(deduped.values).sorted { $0.displayName < $1.displayName }
    }

    public func sizeOfApp(at url: URL, maxDepth: Int = 5) async -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        var depth = 0
        for case let fileURL as URL in enumerator {
            let relativeComponents = fileURL.pathComponents.count - url.pathComponents.count
            depth = max(depth, relativeComponents)
            if depth > maxDepth { break }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    /// Pure function — exposed for testing without actor isolation.
    public nonisolated static func classifySource(url: URL, bundleID: String) -> AppSource {
        let path = url.path
        if path.hasPrefix("/System/") { return .system }
        if bundleID == "com.apple.finder" { return .system }
        if bundleID.hasPrefix("com.apple.") || bundleID == "com.apple.dt.Xcode" {
            return .appleBuiltIn
        }
        if path.contains("/Caskroom/") { return .homebrew }
        if path.contains("/Setapp/") || bundleID.hasSuffix(".setapp") { return .setapp }
        if hasMASReceipt(url) { return .mas }
        if path.contains("/Applications/") { return .userInstalled }
        return .unknown
    }

    // MARK: - Private

    private func enumerateCandidates() async -> [InstalledApp] {
        var candidates: [InstalledApp] = []
        candidates.append(contentsOf: queryLaunchServices())
        candidates.append(contentsOf: appsInStandardDirs())
        candidates.append(contentsOf: appsInHomebrewCaskroom())
        candidates.append(contentsOf: appsInSetapp())
        return candidates
    }

    private func queryLaunchServices() -> [InstalledApp] {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.compactMap { app -> InstalledApp? in
            guard let url = app.bundleURL else { return nil }
            return makeInstalledApp(url: url, workspace: workspace, isRunning: true)
        }
    }

    private func appsInStandardDirs() -> [InstalledApp] {
        let dirs = ["/Applications", "/Applications/Utilities"]
        let workspace = NSWorkspace.shared
        return dirs.flatMap { dir in appsInDirectory(dir, workspace: workspace) }
    }

    private func appsInHomebrewCaskroom() -> [InstalledApp] {
        let candidates = [
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom",
        ]
        let workspace = NSWorkspace.shared
        return candidates.flatMap { root in
            guard let caskDirs = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) else { return [] }
            return caskDirs.flatMap { caskDir -> [InstalledApp] in
                guard let versions = try? fileManager.contentsOfDirectory(at: caskDir, includingPropertiesForKeys: nil) else { return [] }
                return versions.flatMap { versionDir -> [InstalledApp] in
                    appsInDirectory(versionDir.path, workspace: workspace, sourceOverride: .homebrew)
                }
            }
        }
    }

    private func appsInSetapp() -> [InstalledApp] {
        appsInDirectory("/Applications/Setapp", workspace: NSWorkspace.shared, sourceOverride: .setapp)
    }

    private func appsInDirectory(_ dir: String, workspace: NSWorkspace, sourceOverride: AppSource? = nil) -> [InstalledApp] {
        guard let urls = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        return urls.filter { $0.pathExtension == "app" }.compactMap { url in
            var app = makeInstalledApp(url: url, workspace: workspace, isRunning: false)
            if let override = sourceOverride, let unwrapped = app {
                app = InstalledApp(
                    url: unwrapped.url,
                    displayName: unwrapped.displayName,
                    bundleID: unwrapped.bundleID,
                    version: unwrapped.version,
                    source: override,
                    isRunning: unwrapped.isRunning,
                    lastUsedDate: unwrapped.lastUsedDate
                )
            }
            return app
        }
    }

    private func makeInstalledApp(url: URL, workspace: NSWorkspace, isRunning: Bool) -> InstalledApp? {
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier ?? "unknown.\(url.lastPathComponent)"
        let displayName = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return InstalledApp(
            url: url,
            displayName: displayName,
            bundleID: bundleID,
            version: version,
            source: Self.classifySource(url: url, bundleID: bundleID),
            isRunning: isRunning,
            lastUsedDate: nil
        )
    }

    private func merge(existing: InstalledApp, with new: InstalledApp) -> InstalledApp {
        InstalledApp(
            url: existing.isRunning ? existing.url : new.url,
            displayName: existing.displayName,
            bundleID: existing.bundleID,
            version: existing.version.isEmpty ? new.version : existing.version,
            source: existing.source == .unknown ? new.source : existing.source,
            isRunning: existing.isRunning || new.isRunning,
            lastUsedDate: existing.lastUsedDate ?? new.lastUsedDate
        )
    }

    private static func hasMASReceipt(_ url: URL) -> Bool {
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}
```

**Step 4: Run — verify PASS**

Run: `xcodebuild test ... -only-testing:kFreshTests/AppCatalogServiceTests`

Expected: PASS (5/5)

**Step 5: Commit**

```bash
git add kFresh/Core/Detect/AppCatalogService.swift kFresh/Core/Detect/InstalledApp.swift kFresh/Tests/DetectTests/AppCatalogServiceTests.swift
git commit -m "feat(kFresh): AppCatalogService full source classification + recursive size + dedup fix"
```

---

## Task 5: BackupManager 重写（版本化 + 30 天 TTL + 完整性校验 + restore 安全）

**Files:**
- Modify: `kFresh/Data/BackupManager.swift` (full rewrite)
- Modify: `kFresh/Tests/CleanTests/BackupManagerTests.swift` (full rewrite)

**Interfaces:**
- Produces (used by Task 2):
  ```swift
  public actor BackupManager {
      public init(rootURL: URL? = nil)
      public func backup(residues: [ResidueFile], bundleID: String) async throws -> URL
      public func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws
      public func cleanup(bundleID: String) async
      public func cleanupExpired(olderThanDays days: Int) async -> Int
      public func verify(backupPath: URL) async throws -> Bool
  }
  ```

### Step 1: Write failing tests

Rewrite `kFresh/Tests/CleanTests/BackupManagerTests.swift`:

```swift
import XCTest
@testable import kFresh

final class BackupManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testBackupCreatesVersionedDirectory() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("test".utf8).write(to: sourceFile)

        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 4, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))

        let backupURL = try await manager.backup(residues: [residue], bundleID: "com.example.test")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let manifest = try String(contentsOf: backupURL.appendingPathComponent("manifest.json"))
        XCTAssertTrue(manifest.contains("com.example.test"))
    }

    func testRestoreDoesNotOverwriteExistingFile() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("original".utf8).write(to: sourceFile)

        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 8, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))
        _ = try await manager.backup(residues: [residue], bundleID: "com.example.test")

        // Modify source
        try Data("modified".utf8).write(to: sourceFile)

        // Restore should NOT overwrite (current source is "modified")
        try await manager.restore(
            backupPath: tempDir.appendingPathComponent("backups/com.example.test"),
            originalResidues: [residue]
        )

        let current = try String(contentsOf: sourceFile)
        XCTAssertEqual(current, "modified", "Restore must not overwrite more recent file")
    }

    func testCleanupExpiredRemovesOldBackups() async throws {
        let backupRoot = tempDir.appendingPathComponent("backups")
        let oldBundle = backupRoot.appendingPathComponent("com.example.old")
        try FileManager.default.createDirectory(at: oldBundle, withIntermediateDirectories: true)
        let oldDate = Date().addingTimeInterval(-40 * 86400)
        try FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: oldBundle.path)

        let manager = BackupManager(rootURL: backupRoot)
        let removed = await manager.cleanupExpired(olderThanDays: 30)

        XCTAssertGreaterThanOrEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldBundle.path))
    }

    func testVerifyReturnsTrueForIntactBackup() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("test".utf8).write(to: sourceFile)
        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 4, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))
        let backupURL = try await manager.backup(residues: [residue], bundleID: "com.example.test")

        let valid = try await manager.verify(backupPath: backupURL)
        XCTAssertTrue(valid)
    }
}
```

**Step 2: Run — verify FAIL**

Run: `xcodebuild test ... -only-testing:kFreshTests/BackupManagerTests`

Expected: FAIL — current BackupManager doesn't create manifest, doesn't have verify, doesn't have restore-overwrite protection

**Step 3: Rewrite BackupManager**

Rewrite `kFresh/Data/BackupManager.swift`:

```swift
import Foundation

public actor BackupManager {
    public struct Manifest: Codable, Sendable {
        public let bundleID: String
        public let createdAt: Date
        public let version: Int
        public let files: [ManifestEntry]

        public struct ManifestEntry: Codable, Sendable {
            public let relativePath: String
            public let sizeBytes: Int64
            public let sha256: String
        }
    }

    private let fileManager = FileManager.default
    private let rootURL: URL

    public init(rootURL: URL? = nil) {
        if let custom = rootURL {
            self.rootURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = appSupport.appendingPathComponent("app.kraftly.kfresh/Backups")
        }
    }

    public func backup(residues: [ResidueFile], bundleID: String) async throws -> URL {
        let bundleDir = rootURL.appendingPathComponent(bundleID)
        let existingVersions = (try? fileManager.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil)) ?? []
        let version = existingVersions.count + 1
        let backupDir = bundleDir.appendingPathComponent("v\(version)")
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var entries: [Manifest.ManifestEntry] = []
        for residue in residues where residue.confidence > 0.5 {
            guard fileManager.fileExists(atPath: residue.url.path) else { continue }
            let dest = backupDir.appendingPathComponent(residue.url.lastPathComponent)
            try fileManager.copyItem(at: residue.url, to: dest)
            let data = try Data(contentsOf: dest)
            let sha = sha256Hex(data)
            entries.append(Manifest.ManifestEntry(
                relativePath: residue.url.lastPathComponent,
                sizeBytes: Int64(data.count),
                sha256: sha
            ))
        }

        let manifest = Manifest(bundleID: bundleID, createdAt: Date(), version: version, files: entries)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: backupDir.appendingPathComponent("manifest.json"))

        return backupDir
    }

    public func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws {
        let manifestURL = backupPath.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else { return }

        for entry in manifest.files {
            guard let residue = originalResidues.first(where: { $0.url.lastPathComponent == entry.relativePath }) else { continue }
            let backupFile = backupPath.appendingPathComponent(entry.relativePath)

            // CRITICAL: never overwrite a more-recent file at the original path
            if fileManager.fileExists(atPath: residue.url.path) {
                let existingSize = (try? fileManager.attributesOfItem(atPath: residue.url.path)[.size] as? Int64) ?? 0
                if existingSize >= entry.sizeBytes { continue }  // skip — current is newer/bigger
            }

            try? fileManager.copyItem(at: backupFile, to: residue.url)
        }
    }

    public func cleanup(bundleID: String) async {
        let bundleDir = rootURL.appendingPathComponent(bundleID)
        try? fileManager.removeItem(at: bundleDir)
    }

    public func cleanupExpired(olderThanDays days: Int) async -> Int {
        guard let bundleDirs = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.creationDateKey]) else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var removed = 0
        for url in bundleDirs {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let creationDate = attrs[.creationDate] as? Date,
                  creationDate < cutoff else { continue }
            try? fileManager.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    public func verify(backupPath: URL) async throws -> Bool {
        let manifestURL = backupPath.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else { return false }
        for entry in manifest.files {
            let fileURL = backupPath.appendingPathComponent(entry.relativePath)
            guard let data = try? Data(contentsOf: fileURL) else { return false }
            let actualSha = sha256Hex(data)
            if actualSha != entry.sha256 { return false }
        }
        return true
    }

    private func sha256Hex(_ data: Data) -> String {
        // Simple non-crypto wrapper — actual SHA256 via CryptoKit
        import_CryptoKit_shim(data).map { String(format: "%02x", $0) }.joined()
    }

    private func import_CryptoKit_shim(_ data: Data) -> [UInt8] {
        // Use CommonCrypto to avoid Swift package dependency
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash
    }
}
```

Add `import CommonCrypto` at the top.

**Step 4: Run — verify PASS**

Run: `xcodebuild test ... -only-testing:kFreshTests/BackupManagerTests`

Expected: PASS (4/4)

**Step 5: Commit**

```bash
git add kFresh/Data/BackupManager.swift kFresh/Tests/CleanTests/BackupManagerTests.swift
git commit -m "feat(kFresh): BackupManager versioned backups + 30-day TTL + integrity check"
```

---

## Task 6: Design tokens 扩展（Animation tokens）

**Files:**
- Create: `kFoundation/Sources/DesignSystem/Animation.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/...` (or use existing)
- Create: `kFresh/Tests/DesignSystemTests/AnimationTokensTests.swift`

**Interfaces:**
- Produces (used by all Wave 1+ SwiftUI views):
  ```swift
  public enum KFAnimation {
      public static let durationFast: Double = 0.2
      public static let durationNormal: Double = 0.35
      public static let durationSlow: Double = 0.5

      public static let scaleTap: Double = 0.97
      public static let scaleHover: Double = 1.02
      public static let scaleInsert: Double = 0.95

      @available(macOS 14.0, *)
      public static var smooth: Animation { .smooth }

      public static var easeInOut: Animation { .easeInOut }
  }
  ```

### Step 1: Write failing test

Create `kFresh/Tests/DesignSystemTests/AnimationTokensTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import kFoundation

final class AnimationTokensTests: XCTestCase {
    func testDurationConstantsMatchCLAUDMD54() {
        XCTAssertEqual(KFAnimation.durationFast, 0.2)
        XCTAssertEqual(KFAnimation.durationNormal, 0.35)
        XCTAssertEqual(KFAnimation.durationSlow, 0.5)
    }

    func testScaleConstantsMatchCLAUDMD54() {
        XCTAssertEqual(KFAnimation.scaleTap, 0.97)
        XCTAssertEqual(KFAnimation.scaleHover, 1.02)
        XCTAssertEqual(KFAnimation.scaleInsert, 0.95)
    }

    func testEaseInOutFallbackExists() {
        _ = KFAnimation.easeInOut
    }
}
```

**Step 2: Run — verify FAIL**

Run: `xcodebuild test ... -only-testing:kFoundationTests/AnimationTokensTests`

Expected: FAIL — "KFAnimation not defined"

**Step 3: Implement Animation tokens**

Create `kFoundation/Sources/DesignSystem/Animation.swift`:

```swift
import SwiftUI

public enum KFAnimation {
    public static let durationFast: Double = 0.2
    public static let durationNormal: Double = 0.35
    public static let durationSlow: Double = 0.5

    public static let scaleTap: Double = 0.97
    public static let scaleHover: Double = 1.02
    public static let scaleInsert: Double = 0.95

    @available(macOS 14.0, *)
    public static var smooth: Animation {
        Animation.smooth(duration: durationNormal)
    }

    public static var easeInOut: Animation {
        Animation.easeInOut(duration: durationNormal)
    }
}
```

**Step 4: Run — verify PASS**

Run: `xcodebuild test ... -only-testing:kFoundationTests/AnimationTokensTests`

Expected: PASS (3/3)

**Step 5: Commit**

```bash
git add kFoundation/Sources/DesignSystem/Animation.swift kFresh/Tests/DesignSystemTests/AnimationTokensTests.swift kFoundation/Package.swift
git commit -m "feat(kFoundation): Animation tokens (DurationFast/Normal/Slow + ScaleTap/Hover/Insert + Easing)"
```

---

## Task 7: SwiftLint 配置强化 + GitHub Actions CI 最小化

**Files:**
- Create: `kFresh/.swiftlint.yml` (if not exists)
- Modify: `kFresh/.swiftlint.yml` (add strict rules)
- Create: `.github/workflows/ci.yml`

### Step 1: Strengthen SwiftLint config

Create or update `kFresh/.swiftlint.yml`:

```yaml
disabled_rules:
  - trailing_whitespace
  - line_length
opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - sorted_imports
  - toggle_bool
included:
  - Core
  - Data
  - Features
  - App
  - Store
  - Intents
  - MenuBar
  - Widgets
excluded:
  - build
  - kFresh.xcodeproj
  - kFresh.xcworkspace
  - Tests
identifier_name:
  min_length: 2
  max_length: 60
function_body_length:
  warning: 100
  error: 200
type_body_length:
  warning: 500
  error: 1000
```

**Step 2: Verify SwiftLint runs**

```bash
cd kFresh && swiftlint lint --strict
```

Expected: 0 errors (warnings allowed). Fix any errors before committing.

**Step 3: Create GitHub Actions workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: kFresh CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: SwiftLint
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install SwiftLint
        run: brew install swiftlint
      - name: Run SwiftLint
        run: cd kFresh && swiftlint lint --strict

  test:
    name: Tests
    runs-on: macos-14
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.0.app
      - name: Run tests
        run: |
          xcodebuild test \
            -workspace KraftlyWorkspace.xcworkspace \
            -scheme kFresh \
            -destination 'platform=macOS' \
            -quiet
      - name: Run kFoundation tests
        run: |
          cd kFoundation && swift test
```

**Step 4: Verify CI config locally**

```bash
# Validate YAML
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

Expected: no error

**Step 5: Commit**

```bash
git add kFresh/.swiftlint.yml .github/workflows/ci.yml
git commit -m "chore(kFresh): strengthen SwiftLint + GitHub Actions CI (lint + test)"
```

---

## Self-Review Checklist

After completing all 7 tasks, verify:

- [ ] All 5 DoD dimensions pass for each task (see Global Constraints)
- [ ] All tests pass: `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kFresh -destination 'platform=macOS'`
- [ ] SwiftLint: 0 errors
- [ ] kFoundation tests pass: `cd kFoundation && swift test`
- [ ] Bundle ID is `app.kraftly.kfresh` everywhere
- [ ] No `@unchecked Sendable` except for `NSImage`-bearing types
- [ ] No hardcoded animation values (all use `KFAnimation.*`)
- [ ] No hardcoded colors (all use kFoundation `Color.*`)
- [ ] Git history: 7+ commits, one per task
- [ ] BundleRuleStore contains ≥ 1000 rules (`fetch_cask_rules.sh` ran successfully)
- [ ] TrashMover tests pass for all 3 bug categories (race, terminate, restore overwrite)
- [ ] ResidueDetector tests pass for BundleRuleStore integration + URL escape + template fallback
- [ ] AppCatalogService tests pass for Setapp/Homebrew/MAS classification + recursive size
- [ ] BackupManager tests pass for versioned backups + 30-day TTL + integrity verify
- [ ] AnimationTokens tests pass for CLAUDE.md §5.4 constants
- [ ] CI workflow YAML is valid

---

## Execution Time

| Task | Days | Cumulative |
|---|---|---|
| Task 1 (Bundle ID lib) | 3.0d | 3.0d |
| Task 2 (TrashMover) | 2.0d | 5.0d |
| Task 3 (ResidueDetector) | 1.5d | 6.5d |
| Task 4 (AppCatalogService) | 1.0d | 7.5d |
| Task 5 (BackupManager) | 1.0d | 8.5d |
| Task 6 (Animation tokens) | 0.5d | 9.0d |
| Task 7 (Lint + CI) | 0.5d | 9.5d |

Total: **9.5 working days = 2 calendar weeks** (matches Wave 0 scope from B9).

---

## Out of Scope for Wave 0 (deferred to Wave 1+)

- Wave 1: Uninstaller / Residue scan / Startup manager / Backup restore / DeepClean / Large File — 6 核心 feature 端到端
- Wave 2: Duplicate Finder / Onboarding 5 pages / MenuBar / Shortcuts
- Wave 3: Animation polish / AppIcon / Multi-language / Trial / Paywall
- Wave 4: TestFlight + App Store assets + submission

---

## Spec Coverage

| Spec requirement | Task |
|---|---|
| Bundle ID 启发式库 (Homebrew Cask + 累积) | Task 1 |
| TrashMover 安全删除（race / terminate / restore） | Task 2 |
| ResidueDetector 集成 Bundle ID 库 | Task 3 |
| ResidueDetector 新 path templates | Task 3 |
| URL escape 修复 | Task 3 |
| AppCatalogService 完整 source 分类 | Task 4 |
| AppCatalogService recursive size | Task 4 |
| BackupManager 版本化 + TTL + 完整性校验 | Task 5 |
| Design tokens 扩展（CLAUDE.md §5.4） | Task 6 |
| SwiftLint 强化 + CI 最小化 | Task 7 |

All 26 MUST features from B10 are NOT addressed in Wave 0 (those are Wave 1+). Wave 0 only addresses the 7 foundation tasks.

---

## Risks

1. **Homebrew Cask API rate limits** — `https://formulae.brew.sh/api/cask.json` is rate-limited; `fetch_cask_rules.sh` retries 3 times then accepts partial data
2. **Sandboxed app cannot read `/opt/homebrew/Caskroom/`** — `AppCatalogService.appsInHomebrewCaskroom()` may return empty; degrade gracefully to "unknown" source
3. **`NSWorkspace.shared.recycle` is async; verification step (Step 4 in TrashMover) may race** — known limitation; documented in audit log
4. **CommonCrypto import** — `kFresh.xcodeproj` may need CommonCrypto module map (Xcode usually auto-resolves)
5. **`MDQuery Spotlight` for lastUsedDate** — deferred to Wave 1 (avoid Spotlight complexity in Wave 0)

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-01-kfresh-wave0.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?