# App Store Submission Runbook — Klaris v1.6（2026-10-25 修订）

> 2026-10-25 重写：对齐 P0 bundle 迁移、P1 买断制、P3 双渠道与
> MasScanScope.md。旧 v1.0 runbook（ProAnnual / FDA / 旧 worktree 路径）作废。

## Prerequisites
- [ ] Apple Developer Program 有效；Team TC973L6HPC（见 project.yml）
- [ ] Release 配置 = 真实 entitlements（project.yml configs.Release）；
      Debug 构建 = ad-hoc 无 entitlements（本地开发口径，不影响提审）
- [ ] 截图按 ScreenshotsSpec.md 备齐（2560×1600 ≥3 + 2880×1800 ≥1）
- [ ] 隐私政策 https://kraftly.app/privacy 在线（三语）
- [ ] 支持 URL 在线
- [ ] IAP 已创建：`app.kraftly.klaris.buyout`（Non-Consumable，
      $9.90 / ¥68，无订阅无试用）
- [ ] App Store Connect 记录：bundle `app.kraftly.klaris`，SKU klaris-mas
- [ ] 全量测试基线绿（见 MAS scan scope 契约测试与 Localization 门禁）

## Steps

### 1. 版本号与归档
```bash
Tools/version-bump.sh 1.6.0 <build#>     # 写 project.yml + 重新生成工程
scripts/upload_to_testflight.sh          # archive + export + 上传一条龙
```
（脚本内部：`xcodebuild -project kWise/kWise.xcodeproj -scheme kWise
-configuration Release ... archive` → app-store-connect export → altool 上传）

### 2. 上传构建
- xcodebuild/altool 报 "Upload succeeded"，或用 Transporter 拖入
  `kWise/build/export/` 产物
- App Store Connect 处理 5–15 分钟；出口合规答 **No**（零加密）

### 3. 版本页填写
- 元数据逐块复制 AppStoreMetadata.md（名称 Klaris / 明澈，副标题三语）
- 截图按展示顺序挂载
- App Privacy 按 PrivacyDetails.md：全部 Data Not Collected
- 审核备注（关键 —— 预防 2.4.1/2.4.5）：
  > Klaris is sandboxed per MAS requirements. It cannot obtain Full Disk
  > Access; instead the user grants the home folder once via NSOpenPanel
  > (security-scoped bookmark, revocable in Settings). Without the grant the
  > app honestly shows a grant prompt instead of empty results. Zero network
  > access (network entitlements disabled), zero data collection. Cleanup
  > actions require a one-time non-consumable purchase ($9.90); scanning,
  > attribution and the refusal list are free forever.

### 4. 年龄分级
9 项全 No → 4+。

### 5. 定价与可用性
- 免费下载；美区 tier 与 $9.90 对齐；中国 ¥68
- 全区可用（无禁售区）

### 6. 内购
- 核对 `app.kraftly.klaris.buyout` 与 StoreManager.productID 一致
- 附内购审核截图（PaywallView 买断墙）

### 7. 提审
- Add for Review → 出口合规 No → Submit

## Failure Modes
- **"Missing compliance"**：重跑 export，出口合规答 No
- **"Invalid binary"**：清 DerivedData 重新归档（先查图标 1024 8-bit、
  appex 隐私清单齐备）
- **Metadata rejected**：描述中禁用 CleanMyMac 等商标词
- **2.4.1/2.4.5 问询（最可能）**：用审核备注的授权模型段落回复 +
  指出 app 内「系统状态条」的诚实降级 UI（AnatomyView systemStatusSection）
- **测试宿主挂起（本机环境）**：重启后复跑全量基线（见 CLAUDE.md 已知问题）

## 直营渠道（独立流程，不阻塞 MAS）
```bash
scripts/release_direct.sh   # archive → Developer ID → notarytool → staple
```
- Hardened Runtime 必开（project.yml KlarisDirect 已设）
- 过渡期付费：买断墙引导去 MAS 购买

## Post-Approval
- 手动 Release 或 auto-release
- ProductHunt / 评测博主（营销文档待写）
- 直营版部署官网下载页（公证产物）
