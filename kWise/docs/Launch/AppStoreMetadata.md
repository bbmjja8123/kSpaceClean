# Klaris — App Store Connect Metadata

> ⚠️ 2026-10-25 修订：身份与定价字段已对齐 P0 迁移 + P1 买断制 + P3 双渠道。
> **描述正文（下方 EN/zh/ja 长文案）仍是 v1 旧模块叙事，提审前需按 P2
> 单一画布 IA 重写** —— 标注 `[TODO v1.6]` 的区块不得原样提交。

> All fields below are pre-filled; copy each block verbatim into App Store Connect.
> Re-verify character counts (App Store Connect validates live).

## App Name
Klaris

## Subtitle (30 chars max, EN)
The Smarter Mac Disk Cleaner

## Subtitle (30 chars max, zh-CN)
最聪明的 Mac 磁盘清理工具

## Subtitle (30 chars max, ja)
賢い Mac ディスククリーナー

## Bundle ID
app.kraftly.klaris

## SKU
klaris-mas-2026

## Primary Locale
English (en-US)

## Category
Primary: Utilities
Secondary: Productivity

## Promotional Text (170 chars max, EN)
Free up space in one click. 4-level risk scoring protects your important files. Built for Apple Silicon. Zero data ever leaves your Mac.

## Promotional Text (170 chars max, zh-CN)
一键释放磁盘空间。四级风险评分保护重要文件。为 Apple Silicon 打造。零数据上传。

## Promotional Text (170 chars max, ja)
ワンクリックで空き容量を確保。4段階のリスクスコアリングが大切なファイルを守ります。Apple Silicon 専用設計。データは外部送信しません。

## Description (4000 chars max, EN)
kWise is the smartest way to reclaim disk space on your Mac — without the risk of nuking something you'll need tomorrow.

We built kWise because every other cleaner treats your files as disposable. Ours doesn't.

FOUR-LEVEL RISK SCORING
Every file we surface is graded:
• Recommended — safe to remove; selected by default
• Optional — likely safe but check first
• Caution — may affect app behavior
• Dangerous — requires double confirmation + typed DELETE

You see exactly what's at stake, file by file. No surprises.

SMART CATEGORIES, NOT A FLAT LIST
Six top-level categories — System Cache, Application Leftovers, Logs, Old Downloads, Mail Attachments, Browser Caches — each revealing a tree of subcategories as the scan discovers items. Like Finder, but purpose-built.

PROTECTION BEFORE DESTRUCTION
If we detect an app you have open is touching a file we want to clean, we stop and warn you. You decide: skip, force-terminate, or cancel.

ONE-CLICK CLEANUP, 30-DAY UNDO
Cleaned items move to the macOS Trash, not oblivion. A full 30-day cleanup history lets you restore anything you regret. (Pro feature.)

BUILT FOR APPLE SILICON
Hashing and perceptual classification use Apple's Neural Engine where available — scans that took minutes on other apps finish in under two.

ZERO NETWORK
No analytics, no telemetry, no "anonymous usage stats" — because truly anonymous doesn't exist. Every byte stays on your Mac. Period.

APP STORE INTEGRATION
• Shortcuts: trigger a scan or cleanup with one tap from your phone
• Finder: right-click any folder to scan it
• Spotlight: search "Mac space" to find cleanup actions

[TODO v1.6 — 免费层/买断权益区块按 P1 T7 买断制重写，以下为替换基准]
WHAT YOU GET FOR FREE (FOREVER)
• Full anatomy scan of your Mac's storage
• On-device attribution (rule engine + semantic inference, zero network)
• The honest refusal list — files we won't touch and why

ONE-TIME BUYOUT ($9.90 — no subscription, no trial)
• Perform the suggested cleanups (30-day restorable trash)
• Startup item management
• App uninstall with residue detail
• File shredder

PRIVACY FIRST
kWise collects nothing. The App Privacy nutrition label on this listing is empty. Read our privacy policy at kraftly.app/privacy.

REQUIREMENTS
macOS 13.0 or later. Full Disk Access required for system cache cleanup (Apple-mandated, not optional). Apple Silicon or Intel.

## Description (4000 chars max, zh-CN)
[kWise is the smartest way to reclaim disk space on your Mac — without the risk of nuking something you'll need tomorrow. Use the same English description translated. Keep within 4000 chars.]

## Description (4000 chars max, ja)
[Same English description translated to Japanese. Keep within 4000 chars.]

## Keywords (100 chars max, comma-separated)
mac cleaner,disk cleaner,storage,cache,junk,free up space,apple silicon,metal,4-level risk

## Support URL
https://kraftly.app/support/klaris

## Marketing URL (optional)
https://kraftly.app/klaris

## Version 1.0.0 — What's New (4000 chars max, EN)
First release. Smart 4-level scan, risk-graded cleanup, 30-day undo, menu bar widget, Shortcuts integration, full localization (English, Simplified Chinese, Japanese).

## Copyright
© 2026 Kraftly Inc.

## Pricing
Free download; single non-consumable buyout IAP
`app.kraftly.klaris.buyout`: US $9.90 · CN ¥68（其余区域 App Store Connect
tier 对齐，无订阅、无试用、无额度）