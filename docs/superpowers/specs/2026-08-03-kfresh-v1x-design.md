# kFresh v1.x 设计规格（2026-08-03）

**项目**: Kraftly Mac App Suite
**App**: kFresh（应用卸载，前身 kUninstall）
**Bundle ID**: `app.kraftly.kfresh`
**作者**: 独立开发者
**日期**: 2026-08-03
**状态**: ✅ 已定稿（用户 2026-08-03 确认「按推荐来」；§1.1/§1.2/§1.3 三项决策全部按推荐锁定）→ writing-plans 拆 v1.x-A/B/C/D/E

---

## 0. 状态与范围

### 0.1 上游 Wave 状态

| Wave | 状态 | 范围摘要 | 引用 |
|---|---|---|---|
| Wave 0 | ✅ DONE | Core 重写（TrashMover / ResidueDetector / AppCatalogService / BackupManager / CaskParser / AuditLogger）+ Animation tokens + SwiftLint+CI | `.superpowers/sdd/progress-kfresh-wave0.md` |
| Wave 1 | ✅ DONE | 5 核心 feature（Onboarding / AppList / Detail / 卸载确认 / History）+ Startup + DeepClean + StoreKit | `.superpowers/sdd/progress-kfresh-wave1.md` |
| Wave 1.1 | ✅ DONE | 11 项小修（Paywall cancellation / StoreManager 重构 / orphan 删除 / 文件 rename / token / FileManager init split / menu 死代码 / sort nil dates / 测试 hermetic / UI test target） | `.superpowers/sdd/progress-kfresh-wave1-1.md` |
| Wave 0.1 | ✅ DONE | kUninstall→kFresh 重命名 commit + CaskParser M1 修复 + Wave 0/1.1 deferred 清算 | `.superpowers/sdd/progress-kfresh-wave0-1.md` · `progress-kfresh-wave0.md` 末尾 disposition 表 |

**单元测试现状**：166/0 passing（`xcodebuild test -skip-testing:kFreshUITests`）；38 suites。

### 0.2 本 spec 范围（v1.x）

v1.x 是 Wave 0/1/0.1 之后的**收尾 + 增强层**，目标：

1. **关闭 Wave 0 deferred I-4** — "Behavioural change to clean flow; needs design review"（需要本 spec 给出设计）
2. **关闭 Wave 0 deferred m-6 / m-7** — SwiftLint 规则集与 CI 集成（Wave 0 Task 7 已落 CI，但本机无 SwiftLint binary）
3. **关闭 Wave 0 deferred I-3 已完成 + m-2/m-3 stale + m-8..m-10 无 description** — 这些是 plan-text 类，已在 Wave 0.1 记录，无需 v1.x 工作
4. **新增 v1.0 缺失项**（基于 Wave 1 后观察）：
   - 2000+ 中文 App Bundle ID 映射表扩展
   - Apple top-tier 产品对标 gap 分析
   - 性能与稳定性 hardening（Wave 0/1 期间出现的小警告：`AppDetailView.swift:70` non-sendable FileManager 残留等）
5. **明确推迟到 Wave 2 / Wave 3 的功能边界** — Widget / App Intents / Finder 扩展 / MenuBar / 批量 / 多语言 / AI 分析等仍按原 spec §7.2 保留

### 0.3 不在本 spec 范围

- **Wave 2 / Wave 3 主功能**（Widget、Shortcuts、Finder 扩展、MenuBar、批量卸载、多语言、AI 分析）—— v1.x 是 polish / quality / 一项行为变更，不抢 Wave 2 的功能交付
- **App Store 上架动作**（截图、metadata 提交）—— 属于 Wave 3 ship prep
- **其他 App 的工作**（kSpaceClean / kWatch / kSift）—— 各 App 独立，本 spec 仅约束 kFresh

### 0.4 继承约束（来自上游 Wave + CLAUDE.md §5）

- **Bundle ID 全栈一致**：`app.kraftly.kfresh` / `.tests` / `.uitests`
- **No `try?` silent swallow**（生产代码）
- **Design tokens 强制**：`kFoundation/Sources/DesignSystem/*`
- **所有 public API + ViewModifier 必须有 DocC**
- **No `@unchecked Sendable`**（除 NSImage-bearing 类型）
- **Swift 5.9+ / macOS 13.0 / `SWIFT_STRICT_CONCURRENCY = complete`**
- **直推 main**：SDD workflow，per-task commit，单一 squash wave commit 到 main

---

## 1. 决策记录（✅ 已定稿 2026-08-03）

> 用户 2026-08-03 回复「按推荐来」，以下 3 项全部按推荐方案锁定。本节由「待决策」转为「决策记录」，后续 plan 与实施以此为准；如需推翻须新开 spec revision。

### 1.1 I-4 Clean Flow 行为变更方向 — ✅ 锁定 **D + B**

**问题**：当前 clean flow（`TrashMover.moveToTrash` → `BackupManager` → 残留删除 → `UninstallHistory`）已有撤销 + 备份 + 审计日志，但 Wave 0 final review 标 I-4 为"behavioural change, needs design review"。可能的改进方向：

| 方案 | 描述 | 风险 | 用户体验收益 |
|---|---|---|---|
| **A. 永久删除开关** | 在 UninstallConfirmSheet 加"跳过废纸篓，直接删除"选项（默认 off） | 高（不可恢复） | 满足"彻底删除"用户 |
| **B. Dry-run 预览模式** | 加 `--dry-run` App Intent + 详情页"模拟卸载"按钮，只输出将释放什么、不实际删除 | 低 | 增强信任 + 新手友好 |
| **C. 批量原子卸载** | 多选 → 一次备份 → 顺序执行 → 失败时整批回滚 | 中（数据模型扩展） | Wave 2 批量卸载前置 |
| **D. 风险分级默认勾选**（CLAUDE.md §8.6 同模式） | 4 级风险（🟢 Recommended / ⚪ Optional / 🟠 Caution / 🔴 Dangerous），D 级需双确认 + 输入 "DELETE" | 低 | 误删保护 |

**推荐**：D（沿用 CLAUDE.md §8.6 已有的 kSpaceClean 模式）+ B 作为副产物（dry-run 共享同一 preview 路径）

**✅ 决策（2026-08-03）**：采纳 **D + B**。
- 4 级风险标签按 CLAUDE.md §8.6 语义，默认勾选策略见 §2.1
- 🔴 Dangerous 级**必须**双确认 + 输入 `DELETE`（CLAUDE.md §8.6 硬性要求，不放宽）
- Dry-run 与真实执行共享同一 preview 计算路径，禁止两套逻辑
- A（永久删除开关）**不做** — 不可恢复风险与 kFresh「安全卸载」定位冲突
- C（批量原子卸载）**推迟 Wave 2**，与批量卸载功能一起交付

### 1.2 SwiftLint 规则集范围 — ✅ 锁定「推荐集 + 4 条 Kraftly 自定义规则」

**问题**：CLAUDE.md §5.1 要求 SwiftLint 强制。当前仓库只有 `.github/workflows/ci.yml`（Wave 0 Task 7 落），无 `.swiftlint.yml`。本机 `which swiftlint` exit 1。

**推荐配置位置**：`kFoundation/.swiftlint.yml`（共享于 4 个 App，CLAUDE.md §5.4 要求）

**推荐规则集**：
- 默认启用：`opt_in_rules` 全开（caret-only），`disabled_rules` 关掉 `todo` / `fixme` / `line_length`（保留行宽自定义）
- 自定义 Kraftly 规则：
  1. `no_silent_try_question_mark` — 生产代码禁用 `try?`（除了 `Bundle.main.path(forResource:ofType:)` 等明确允许的 API）
  2. `no_hardcoded_design_tokens` — 禁止 `.system(size:)` / 硬编码 hex / 硬编码 padding（指向 `AppFont.*` / `AppSpacing.*` / `Color.*`）
  3. `no_kuninstall_string` — 禁止源码出现字面量 "kUninstall"（除历史归档 spec 文档）
  4. `no_unchecked_sendable` — 禁止 `@unchecked Sendable`（除已记录的 NSImage 例外）

**CI 集成**：`.github/workflows/ci.yml` 已运行 `swiftlint`；本机通过 `brew install swiftlint` 安装后即可本地运行

**待用户决策**：
- 接受推荐规则集？还是精简/扩展？
- 自定义规则的 lint 工具是 SwiftLint 自带语法还是单独脚本？
- 已有违规（166 文件）是一次性清理还是 per-wave 渐进清理？

**✅ 决策（2026-08-03）**：采纳推荐规则集 + 4 条自定义规则。
- 4 条自定义规则一律用 SwiftLint 原生 `custom_rules` 正则语法实现，**不写独立脚本**（保证 CI 与本地同一执行路径）
- 存量违规采用**分级清理**：`severity: error` 的规则（`no_silent_try_question_mark`、`no_kuninstall_string`）在 v1.x-A **一次性清零**；`severity: warning` 的两条（`no_hardcoded_design_tokens`、`no_unchecked_sendable`）在 v1.x-A 只建立基线计数并写入 ledger，渐进清理推迟 v1.x-E
- CI 门禁：v1.x-A 起 `swiftlint lint --strict` 为必过 job

### 1.3 Bundle ID 2000+ 中文 App 映射数据策略 — ✅ 锁定「人工 curated + 自动 fallback」，并**列为长期演进资产**

**问题**：Wave 0 final fix C-1 后，1141 cask rules 中 172 有真 bundle ID，986 落 token fallback（cask ruby 无 extractable signal）。v1.x 目标：补到 ≥ 2000 个中文常用 App 的真 bundle ID 映射。

**推荐方案**：
1. **数据源**：
   - 主源：人工 curated 列表（200 条最常用中文 Mac App：QQ、微信、钉钉、网易云、百度网盘、阿里云盘、有道词典、QQ 音乐、腾讯会议、剪映专业版、搜狗输入法、Chrome 中国版、WPS Office、Foxmail 等）
   - 辅源：Homebrew Cask `zh-*` / `cn-*` token 扫描（自动）
   - 辅源：Apple App Store CN scrape（仅 bundle ID + app name，不抓 icon/desc）
2. **存储**：扩展现有 `cask_rules.json` 格式，新增 `kFresh/Resources/zh_app_mappings.json`（独立文件，便于人工 review）+ `WELL_KNOWN_META` overlay
3. **更新机制**：
   - 人工添加：PR review process，每条需 (app name, bundle ID, 验证方式)
   - 自动同步：cask rule generation pipeline 每 30 天跑一次
4. **质量门**：
   - 每条映射需至少 2 个独立来源（人工 + cask，或人工 + AS scrape）
   - bundle ID 必须经过 `defaults read <path>/Contents/Info CFBundleIdentifier` 验证
   - 错误映射自动 quarantine，下次 generation 排除

**待用户决策**：
- 数据源优先级（人工 vs 自动）？
- 中文 App 的定义边界（仅大陆？含港澳台？含新加坡华人市场？）
- 是否需要自动化测试每个映射的 freshness（运行时探测）？

**✅ 决策（2026-08-03）**：采纳推荐方案，并明确以下三点：
- **数据源优先级**：人工 curated > cask-cn > AS CN scrape。同一 app 冲突时人工条目优先，自动源只能补空、不能覆盖人工
- **中文 App 边界**：以「中国大陆用户日常安装量」为唯一取舍标准，不按地区行政边界切分——港澳台/新加坡华人市场常用 App（如 LINE、Telegram 中文版）若在大陆有可观装机量则收录
- **freshness 校验**：不做全量运行时探测（启动开销不可接受）。改为 **CI 侧静态校验 + 运行时抽样**：CI 校验 schema/重复/格式；运行时仅在用户实际卸载某 app 时比对该条 mapping，不匹配则写入本地 quarantine 待下次 generation 排除

> ⚠️ **本项不是一次性交付，是长期演进资产** — 用户 2026-08-03 明确要求记录该策略并持续优化。演进机制见 **§4.6**。

### 1.4 其他 open questions（可在 review 时追加）

- Apple top-tier parity（AppCleaner / Nektony / TrashMe）— v1.x 是否包含对标 gap closure？
- 性能预算（扫描 < X 秒）— 是否在 v1.x 强制？
- 国际化（zh-Hans / ja）— 推迟到 Wave 2 还是 v1.x 提前？

---

## 2. I-4 Clean Flow 行为变更设计

> 仅在用户确认 §1.1 决策后展开细节。本节提供"如选 D+B" 的设计草案作为参考。

### 2.1 4 级风险标签（沿用 CLAUDE.md §8.6）

| 级别 | 颜色 | 含义 | 默认勾选 | 删除时行为 |
|---|---|---|---|---|
| 🟢 **Recommended** | 绿 | 系统/缓存类残留（`~/Library/Caches/*`） | ✅ ON | 单确认 |
| ⚪ **Optional** | 白 | 应用支持目录（`~/Library/Application Support/*`） | ❌ OFF | 单确认 |
| 🟠 **Caution** | 橙 | 偏好设置（`~/Library/Preferences/*`）、Cookies | ❌ OFF | 单确认 + 警告 |
| 🔴 **Dangerous** | 红 | LaunchAgents（启动即触发）、Keychain、Documents（用户文档） | ❌ OFF | 双确认 + 输入 "DELETE" |

### 2.2 Dry-run 模式（副产物）

**触发**：
- 详情页按钮"模拟卸载"
- App Intent：`UninstallAppIntent(dryRun: true)`

**输出**：
- 将释放的总大小
- 将删除的文件清单（按风险分级聚合）
- 将保留的备份（路径 + 大小）
- 不会触碰任何文件

**实现位置**：`TrashMover.dryRun(app:residues:) async -> DryRunReport`

### 2.3 行为变更影响面

| 文件 | 改动 |
|---|---|
| `kFresh/Features/Detail/UninstallConfirmSheet.swift` | 加 4 级风险分组 + D 级输入框 |
| `kFresh/Core/Clean/TrashMover.swift` | 加 `dryRun` 方法 + 风险过滤参数 |
| `kFresh/Models/ResidueTypes.swift` | `ResidueFile` 加 `riskLevel: ResidueRiskLevel` 字段 |
| `kFresh/Intents/UninstallAppIntent.swift` | 加 `dryRun` 参数 |
| `kFresh/Tests/*` | 新增 4 级风险 + dry-run 测试用例 |

---

## 3. SwiftLint 规则集设计

### 3.1 配置文件位置

- **`kFoundation/.swiftlint.yml`** — 共享配置（4 个 App 都引用）
- **`kFresh/.swiftlint.yml`** — App 级 override（如需禁用某些共享规则）

### 3.2 推荐规则集（draft）

```yaml
# kFoundation/.swiftlint.yml
excluded:
  - kFoundation/Sources/DesignSystem/  # tokens are intentional hardcoded values
  - kFresh/Resources/Localizable.xcstrings  # localization data, not code
  - '**/build/'
  - '**/.build/'

opt_in_rules:
  - array_init
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_first_not_nil
  - convenience_type
  - discouraged_object_literal
  - empty_collection_literal
  - empty_count
  - empty_string
  - explicit_init
  - fatal_error_message
  - file_name
  - first_where
  - flatmap_over_map_reduce
  - identical_operands
  - joined_default_parameter
  - last_where
  - literal_expression_end_indentation
  - lower_acl_than_parent
  - modifier_order
  - multiline_arguments
  - multiline_function_chains
  - multiline_literal_brackets
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - prefer_self_type_over_type_of_self
  - prefer_zero_over_explicit_init
  - prefixed_top_level_constant
  - private_action
  - private_outlet
  - prohibited_super_call
  - protocol_property_accessors_order
  - reduce_boolean
  - redundant_nil_coalescing
  - redundant_type_annotation
  - sorted_imports
  - static_operator
  - toggle_bool
  - unhandled_parenthetical_closure_argument
  - unneeded_override
  - unneeded_break_in_switch
  - unneeded_condition
  - unneeded_paren_in_closure_argument
  - unused_capture_list
  - unused_closure_parameter
  - unused_enumerated
  - unused_control_flow_label
  - vertical_parameter_alignment_on_call
  - yoda_condition

disabled_rules:
  - todo
  - fixme
  - line_length  # 200 char limit, our own rule below
  - file_length
  - type_body_length
  - function_body_length

custom_rules:
  no_silent_try_question_mark:
    name: "No silent try? in production code"
    regex: '\btry\?'
    message: "Use do/catch + Result or explicit error handling. try? silently swallows errors."
    severity: error
    excluded:
      - '**/Tests/**'

  no_hardcoded_design_tokens:
    name: "No hardcoded design tokens"
    regex: '\.(system\(size:)|\.system\(weight:)|padding\(\d+\.0\)|frame\(width: \d+, height: \d+\)'
    message: "Use AppFont / AppSpacing / WindowFrame tokens from kFoundation DesignSystem."
    severity: warning
    excluded:
      - 'kFoundation/Sources/DesignSystem/**'
      - '**/Tests/**'

  no_kuninstall_string:
    name: "No kUninstall literal in source"
    regex: '"kUninstall"|kUninstall/|app\.kraftly\.kuninstall'
    message: "kFresh rename complete; remove all kUninstall literals from source."
    severity: error
    excluded:
      - '**/*.md'
      - 'docs/superpowers/specs/2026-07-26-kraftly-kuninstall-design.md'  # historical archive

  no_unchecked_sendable:
    name: "No @unchecked Sendable"
    regex: '@unchecked\s+Sendable'
    message: "@unchecked Sendable requires explicit justification; see CLAUDE.md §5.1."
    severity: warning
    excluded:
      - 'kFresh/Core/Detect/InstalledApp.swift'  # NSImage exception, documented
```

### 3.3 CI 集成

`.github/workflows/ci.yml` 已有 `swiftlint lint` job（Wave 0 Task 7）。本机：

```bash
brew install swiftlint
cd kFresh && swiftlint lint --strict
```

预期违规数：~50-150 处（166 个 Swift 文件，每文件平均 1 处）。建议 v1.x 一次性清理。

---

## 4. Bundle ID 2000+ 中文 App 映射数据策略

### 4.1 数据格式

```json
// kFresh/Resources/zh_app_mappings.json
{
  "version": 1,
  "generatedAt": "2026-08-03T00:00:00Z",
  "source": "manual + cask-cn + as-cn-scrape",
  "apps": [
    {
      "displayName": "QQ",
      "bundleID": "com.tencent.qq",
      "appName": "QQ",
      "verifiedAt": "2026-08-01T00:00:00Z",
      "verifiedBy": "manual",
      "sources": ["manual", "cask-cn"],
      "deprecated": false
    },
    ...
  ]
}
```

### 4.2 数据源 pipeline

```
[manual curation]  --+--> [validate via Info.plist read] --+--> [zh_app_mappings.json]
[cask-cn scrape]  --+                                        |
[AS CN scrape]    --+                                        |
                                                            v
                                              [WELL_KNOWN_META overlay]
                                                            v
                                              [ResidueScanner lookup path]
```

### 4.3 更新工作流

1. **手动添加**：开发者本地编辑 `zh_app_mappings.json`，PR review 后合并
2. **自动同步**：每月 1 号 cron 跑 `scripts/update_zh_app_mappings.py`
3. **冲突解决**：同一 (displayName, bundleID) 对应多条记录时，以 `verifiedAt` 最新为准
4. **弃用机制**：`deprecated: true` 字段，runtime 跳过

### 4.4 验证策略

- 每条记录必须有 `verifiedAt` 时间戳
- `verifiedBy` 至少 2 个独立来源
- runtime 探测（可选）：启动时探测 50 个最常用 mapping，发现 `defaults read` 返回的 bundle ID 不匹配时报告

### 4.5 工作量估算

| 阶段 | 时间 | 交付 |
|---|---|---|
| 人工 curated 200 条 | 1 working day | 核心中文 App 列表 |
| cask-cn scrape pipeline | 0.5 day | ~300 自动 mapping |
| AS CN scrape | 1 day（需异步 + 反爬处理）| ~800 mapping |
| 验证 + 文档化 | 0.5 day | 映射表 README |
| 集成进 ResidueScanner | 0.5 day | runtime lookup path |
| 测试 + CI | 0.5 day | mapping freshness tests |

合计：4 working days ≈ 0.8 weeks

### 4.6 长期演进策略（LIVING — 持续优化，非一次性交付）

> **决策来源**：用户 2026-08-03「关于 1.3 的实现，要记录下来，后续应该是需要持续优化策略的」。
> 规则库是 kFresh 的**核心竞争壁垒**，不是可交付即封存的静态资源。v1.x-C 只交付 **v1 基线**，此后按下述节奏持续演进。

#### 4.6.1 分期目标（覆盖率阶梯）

| 阶段 | 时间点 | 目标条数 | 主要来源 | 判定口径 |
|---|---|---|---|---|
| **v1 基线** | v1.x-C 交付 | ≥ 2000 | 人工 200 + cask-cn ~300 + AS CN ~800 + 现有 cask 1141 去重 | 有真 bundle ID（非 token fallback） |
| **v1.1** | 上架后 1 个月 | ≥ 2500 | 用户实际卸载遥测缺口（本地 quarantine 聚合，**用户显式同意才上报**） | 同上 |
| **v2** | 上架后 3 个月 | ≥ 4000 | AI 辅助补齐 + 竞品模式对标（CMM / Buho / Lemon 的残留路径*模式*，不复制规则数据） | 同上 + 残留路径规则 |
| **长期** | 每季度 | 每季 +10% 或补齐 top-100 缺口 | 全部来源 | 同上 |

> 对齐既有约定：CLAUDE.md 记载的 kSpaceClean 规则库 release gate 为 500–1000+；kFresh 因卸载场景强依赖 bundle ID 精确匹配，门槛更高（2000 起）。

#### 4.6.2 常态化维护节奏

| 频率 | 动作 | 负责 | 产出 |
|---|---|---|---|
| **每次卸载（runtime）** | 抽样比对当前 app 的 mapping，不符写入本地 quarantine | App | `quarantine.json`（本地，不自动外发） |
| **每月 1 号（cron）** | 跑 `scripts/update_zh_app_mappings.py` 同步 cask-cn / AS CN 增量 | CI | PR diff |
| **每季度** | 人工 review quarantine + 补齐 top-N 缺口 + 淘汰 deprecated | 开发者 | 版本号 +1 |
| **每次 App 大版本** | 覆盖率报告写入 release note 内部记录 | 开发者 | 覆盖率数字 |

#### 4.6.3 演进不变量（后续任何优化都不得破坏）

1. **人工优先**：自动源只能补空，永不覆盖 `verifiedBy: manual` 条目
2. **可追溯**：每条 mapping 必须携带 `sources` + `verifiedAt` + `verifiedBy`，无来源的条目不得合入
3. **零静默外发**：quarantine / 遥测数据默认仅存本地；任何上报必须走用户显式同意（CLAUDE.md §5.3）
4. **不复制他人规则数据**：仅参考竞品的**残留路径模式**（如「App Support 目录以 bundle ID 命名」），禁止导入 CMM / Buho / Lemon 的规则文件内容
5. **版权安全**：AS CN 仅取公开 metadata（bundle ID + display name），不抓描述/截图/评分
6. **schema 向后兼容**：新增字段必须 optional；`version` 字段递增，旧版本 App 读新文件不得崩溃
7. **降级可用**：`zh_app_mappings.json` 缺失或损坏时，`ResidueScanner` 必须优雅回落到现有 cask token 路径，不阻塞卸载

#### 4.6.4 覆盖率度量（每次演进必须报出）

```
覆盖率 = 有真 bundle ID 的条目数 / 总规则条数
top-100 命中率 = 大陆 top-100 Mac App 中有真 bundle ID 的比例   ← 更重要的北极星指标
```

`top-100 命中率` 是主指标（用户实际感知），总条数是副指标（防止刷量式扩充）。CI 每次 generation 后输出两个数字并写入 `.superpowers/sdd/` ledger。


---

## 5. 其他 v1.x 候选（低优先级，可推迟到 Wave 2/3）

### 5.1 Apple top-tier 产品对标 gap closure

基于 spec §1.4 的对标表（AppCleaner / Nektony / TrashMe / Cleaner One），kFresh 仍有 gap：

| Gap | 来源 | 建议 v1.x 处理 |
|---|---|---|
| AppCleaner 风格"磁盘空间可视化饼图" | AppCleaner | 推迟到 Wave 3（kSpaceClean 也做） |
| Nektony "smart selector"（自动推荐残留） | Nektony | **v1.x 可选**（与 AI 分析分开的轻量功能） |
| TrashMe "favorites / batch presets" | TrashMe | 推迟到 Wave 2 批量卸载 |
| Cleaner One "安全中心 / 隐私扫描" | Cleaner One | 推迟（与 kWatch 重叠） |

### 5.2 性能与稳定性 hardening

来自 Wave 1 期间发现：
- `AppDetailView.swift:70:72` non-sendable FileManager warning（Wave 1.1 Task 7 已尝试修，可能有残留）
- 165 测试中 0 个 performance test
- 无 memory leak 监控（OSAllocatedUnpacked）

v1.x 可加：
- 1 个 performance test（scan 100 apps < 5s）
- Instruments 集成（snapshot test 在 CI）

### 5.3 Apple top-tier 设计语言对标

| 维度 | AppCleaner | TrashMe | kFresh 当前 | v1.x 差距 |
|---|---|---|---|---|
| 动效时长 | 200ms | 250ms | 200/350ms | ✅ 已有 |
| 空状态插画 | 矢量插画 | 矢量插画 | SF Symbol | ❌ 需自定义插画 |
| 卸载动画 | 三阶段 | 二阶段 | toast + 撤销 | 中等 |
| 暗色模式 | ✅ | ✅ | ✅（系统跟随） | ✅ |

---

## 6. Wave 划分建议

| Wave | 范围 | 工作量 |
|---|---|---|
| **v1.x-A** | SwiftLint setup + 全仓合规 sweep | 1.5d |
| **v1.x-B** | I-4 Clean Flow 行为变更（D+B 方案） | 2d |
| **v1.x-C** | Bundle ID 2000+ 中文 App 映射 | 4d |
| **v1.x-D** | Apple top-tier gap closure（可选子集） | 1d |
| **v1.x-E** | 性能 + 稳定性 hardening | 1d |

合计：**9.5 working days ≈ 2 calendar weeks**

每个 wave 走 SDD 流程：implementer → task reviewer → fix → final review → squash commit to main。

---

## 7. 验收标准（v1.x 整体）

| 维度 | 标准 |
|---|---|
| **功能** | §1.1 + §1.2 + §1.3 全部决策落地 |
| **性能** | 166/0 测试保留；新增 ≥ 5 个测试覆盖 v1.x 行为 |
| **UX** | 4 级风险标签 UI 落地（§2.1）；dry-run 入口可见 |
| **代码质量** | SwiftLint 0 violation（strict mode）；custom rules 全绿 |
| **设计一致性** | Design tokens 0 硬编码；新增 v1.x feature 走现有 DesignSystem |
| **数据** | zh_app_mappings.json ≥ 2000 条；CI 自动 freshness check |

---

## 8. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| **SwiftLint 一次性清理量大** | 100+ 违规难以短期修完 | 渐进式：v1.x-A 只修 error 级；warning 推迟到 v1.x-E |
| **Bundle ID 人工 curation 工作量大** | 200 条 × 验证时间 = 1d | 利用 cask-cn + AS CN 自动源减少人工量 |
| **I-4 行为变更用户学习成本** | 4 级风险分级比单一勾选复杂 | UI 上保留"高级 / 简单"切换；新手默认高级（推荐级已勾） |
| **性能 budget 加严** | scan < 5s 可能需重写部分 hot path | 推迟到 v1.x-E，先 profile 决定是否需要 |
| **zh_app_mappings.json 版权风险** | AS CN scrape 可能违反 ToS | 仅用公开 metadata（bundle ID + display name），不抓描述/截图 |

---

## 9. 关联文档

- 上游 spec：`docs/superpowers/specs/2026-08-01-kraftly-kfresh-design.md`
- Wave 0/1/1.1/0.1 ledgers：`.superpowers/sdd/progress-kfresh-wave{0,1,1-1,0-1}.md`
- Wave 0 final fix report：`.superpowers/sdd/wave0-final-fix-report.md`
- CLAUDE.md §5.1（SwiftLint 强制）+ §5.4（设计语言）+ §8.6（4 级风险标签）

---

## 10. Review checklist（✅ 用户已 review — 2026-08-03）

- [x] §1.1 I-4 行为变更方向 → **D + B 锁定**（A 不做，C 推迟 Wave 2）
- [x] §1.2 SwiftLint 规则集 → **推荐集 + 4 条自定义锁定**（原生 custom_rules；error 级 v1.x-A 清零，warning 级 v1.x-E 渐进）
- [x] §1.3 Bundle ID 数据策略 → **锁定，且列为长期演进资产**（演进机制见 §4.6）
- [x] §6 Wave 划分 → **A/B/C/D/E 顺序与工作量确认**
- [x] §7 验收标准 → **阈值确认**
- [x] 其他 v1.x 项目 → 无追加

*决策已定稿，进入 writing-plans 拆分 v1.x-A / B / C / D / E 实施计划。*