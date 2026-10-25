# Submission Checklist — Klaris v1.6（Kraftly）

> 2026-10-25 重写：与 P0 bundle 迁移（app.kraftly.klaris）、P1 买断制、
> P3 双渠道现状对齐。旧版 ProAnnual / 7 天试用 / kWise 命名已全部作废。

产品事实（代码即真相）：
- 名称 **Klaris**（zh-Hans 显示名：明澈）；bundle `app.kraftly.klaris`
- 定价 **免费下载 + $9.90 非消耗买断**（`app.kraftly.klaris.buyout`），
  无订阅、无试用。美 $9.90 / 中 ¥68
- 双渠道：MAS（沙盒 + PowerScope 主目录授权）/ 直营 Developer ID
  （无沙盒，公证 + staple）。两渠道共用 bundle ID，不可并存
- 零网络、零数据收集；MetricKit 仅本地

## 代码与构建（MAS 版）
- [ ] `scripts/upload_to_testflight.sh` 产出的 archive 构建成功
- [ ] Release 配置含真实 entitlements（沙盒 + App Group
      `group.app.kraftly.klaris`）与 Team TC973L6HPC
- [ ] App 图标：1024×1024 8-bit（icon_1024.png；master 在 Tools/branding/）
- [ ] 三个 target 的隐私清单齐备（app / widget / finder）
- [ ] `xcodebuild test`（scheme kWise）全量绿；LocalizationCompletenessTests 绿
- [ ] 直营渠道冒烟：scheme KlarisDirect 构建 + 启动（Full Disk Access 行为）
- [ ] 无 "Missing compliance"（零加密，出口合规答 No）

## MAS 扫描范围叙事（审核备注用，详见 docs/Launch/MasScanScope.md）
- [ ] 审核备注写明：沙盒应用**不能**获得 Full Disk Access；Klaris 采用
      一次性「主目录授权」（NSOpenPanel + security-scoped bookmark），
      未授权时应用显示授权引导而非空结果
- [ ] 预防 2.4.1/2.4.5 问询：说明为什么需要主目录（清理缓存/日志/残留）

## 元数据
- [ ] App name: Klaris（副标题 ≤30 字符 ×3 语）
- [ ] 描述 ≤4000 字符 ×3 语；关键词 ≤100 字符（mac cleaner 等见 CLAUDE.md §3.7，
      禁用 CleanMyMac 商标）
- [ ] Copyright: © 2026 Kraftly
- [ ] Support URL（https://kraftly.app/support）与 Privacy URL（/privacy）200
- [ ] 分类：Utilities

## 截图
- [ ] ≥3 张 2560×1600 + ≥1 张 2880×1800（ScreenshotsSpec.md）
- [ ] 场景覆盖：解剖画布 / 组卡下钻 / 预演确认 / 磁盘健康 / 启动项·卸载
- [ ] 仅合成数据；zh-CN 与 ja 文案本地化版本

## 隐私
- [ ] App Privacy：所有类目 = Data Not Collected
- [ ] 隐私政策三语页面在线（docs/legal/privacy.*.html）
- [ ] 无网络权限（entitlements network.client=false）、无追踪、无遥测

## 内购
- [ ] IAP `app.kraftly.klaris.buyout`（Non-Consumable, $9.90/¥68）在
      App Store Connect 创建并与代码一致
- [ ] 恢复购买流程可用（Paywall + 设置页）
- [ ] 审核说明：未购买 = 免费层（扫描/归因/拒答清单永久免费），清理动作
      弹买断墙

## 年龄分级
- [ ] 全部 9 项作答（预期 4+）

## App Review 信息
- [ ] 无需演示账号（无登录）
- [ ] 审核联系人已填
- [ ] 审核备注：主目录授权模型（见上）+ 买断制说明

## 直营渠道（不阻塞 MAS 提审）
- [ ] `scripts/release_direct.sh`：archive → Developer ID 签名 →
      notarytool submit --wait → stapler staple
- [ ] Hardened Runtime 开启（project.yml KlarisDirect target）
- [ ] 过渡期付费：免费层 + 买断墙「在 Mac App Store 购买 Klaris」引导

## 最终
- [ ] App Store Connect 提交页逐项复核
- [ ] Submit for Review + 确认邮件
