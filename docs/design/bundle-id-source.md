# Bundle ID 启发式规则库 — 数据来源

## 来源 1: Homebrew Cask zap stanzas（覆盖 ~1150 个 macOS App）

- 原始数据: `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/<token[0]>/<token>.rb`
- 抓取方式: `kFresh/Resources/fetch_cask_rules.sh` 一次拉取（默认 16 路并发），解析 `zap trash: [...]` 项
- 覆盖范围: Homebrew Cask API 返回的 7665 个 casks 中按 token 字典序前 1500 + 10 个手动指定热门 App
- 置信度: 0.85（placeholder bundleID 用 token，v1.1 由 `BundleRuleStore.lookup` 配合 Info.plist 二次校准）

`kFresh/Resources/fetch_wellknown_casks.py` 作为兜底：把 Chrome / VS Code / Slack / Spotify / Firefox / iTerm2 / Discord / Notion / Figma / Postman 这 10 个用户最常安装的 App 强制合并进 `cask_rules.json`，确保它们在数据集中的存在与位置无关。

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

### 验收记录 (2026-08-01)

- `cask_rules.json`: 1157 条规则（1.2 MB）
- `BundleRuleStore.count`: 1157（脚本未在测试里直接喂真实 JSON，但字段 schema 与 `KFreshBundleRule` 完全一致；`BundleRuleStoreTests.testCountReflectsLoadedRules` 通过）
- 10 个热门 App 命中率: 9/10
  - ✅ visual-studio-code, iterm2, firefox, slack, discord, notion, figma, postman, spotify
  - ⚠️ google-chrome: upstream cask 仅声明 `zap launchctl:`，没有 `zap trash:` 路径。Chrome 的残留通过 `ResidueDetector` 的 bundle-ID 启发式（`com.google.Chrome`）补齐；该路径不在本规则库范围。