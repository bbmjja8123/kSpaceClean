# kSpaceClean v1.0 — Design Spec

> **状态**：基于 25 个 grilling 决策锁定的视觉系统
> **日期**：2026-07-29
> **依据**：`CLAUDE.md §8` + `docs/superpowers/specs/2026-07-27-kspaceclean-v2-scan-cleanup-design.md`
> **目标**：SwiftUI 直接实现，不需要 Figma

---

## 0. 设计原则

| 原则 | 说明 |
|---|---|
| 暗色基底 | DaisyDisk 风格 `#0F1012`，避免过家家均匀配色 |
| 系统色 + 强调色 | 风险色用 macOS 系统色（绿/灰/橙/红），强调用系统蓝 |
| 文字驱动 | 数字 + Label 是主视觉，图标辅助 |
| 50fps 流畅 | 所有动画 ≤ 200ms，扫描时只更新文字不重绘布局 |
| 4 级风险徽标 | Recommended / Optional / Caution / Dangerous，徽标随级别变色 |

---

## 1. 颜色 Token

### 1.1 基础色

| Token | Hex | 用途 |
|---|---|---|
| `bg.canvas` | `#0F1012` | 主背景（DaisyDisk 暗色） |
| `bg.surface` | `#1C1C1E` | 卡片表面 |
| `bg.elevated` | `#2C2C2E` | 浮层 / 工具栏 |
| `bg.overlay` | `#000000` + 60% | 模态遮罩 |
| `divider` | `#3A3A3C` | 分割线 |

### 1.2 文字色

| Token | Hex | 用途 |
|---|---|---|
| `text.primary` | `#FFFFFF` | 主文字 |
| `text.secondary` | `#999999` | 次文字 |
| `text.tertiary` | `#666666` | 辅助文字 |
| `text.disabled` | `#3A3A3C` | 禁用 |

### 1.3 品牌色

| Token | Hex | 用途 |
|---|---|---|
| `brand.primary` | `#0A84FF` | macOS 系统蓝（CTA / 主按钮） |
| `brand.accent` | `#5AC8FA` | 亮蓝（高光 / 进度环） |
| `brand.gradientStart` | `#0A84FF` | 渐变起点 |
| `brand.gradientEnd` | `#5AC8FA` | 渐变终点 |

### 1.4 风险色（4 级）

| Token | Hex | 用途 |
|---|---|---|
| `risk.recommended.bg` | `#34C759` | 推荐背景（绿） |
| `risk.recommended.fg` | `#FFFFFF` | 推荐文字 |
| `risk.optional.bg` | `#8E8E93` | 可选背景（灰） |
| `risk.optional.fg` | `#FFFFFF` | 可选文字 |
| `risk.caution.bg` | `#FF9500` | 谨慎背景（橙） |
| `risk.caution.fg` | `#000000` | 谨慎文字 |
| `risk.dangerous.bg` | `#FF3B30` | 危险背景（红） |
| `risk.dangerous.fg` | `#FFFFFF` | 危险文字 |

### 1.5 状态色

| Token | Hex | 用途 |
|---|---|---|
| `state.warning` | `#FFCC00` | 警告（运行中应用 toast） |
| `state.success` | `#34C759` | 成功（清理完成） |
| `state.error` | `#FF3B30` | 错误（权限失败 / 清理失败） |
| `state.scanning` | `#0A84FF` | 扫描中（脉冲动画） |

---

## 2. 字体 Token

### 2.1 字体族

| 用途 | 字体 |
|---|---|
| Display | SF Pro Display |
| Text | SF Pro Text |
| Path | SF Mono |

### 2.2 字号 / 重量

| Token | 字体 | 重量 | 用途 |
|---|---|---|---|
| `title.hero` | SF Pro Display | 600 (32-40pt) | 扫描结果总数字 |
| `title.large` | SF Pro Display | 600 (24pt) | 主标题 |
| `title.medium` | SF Pro Text | 600 (17-20pt) | 模块标题 |
| `body.large` | SF Pro Text | 500 (15pt) | 行标题 |
| `body.regular` | SF Pro Text | 400 (13pt) | 普通文字 |
| `body.small` | SF Pro Text | 400 (11pt) | 辅助说明 |
| `path.default` | SF Mono | 400 (12pt) | 文件路径 |
| `number.size` | SF Pro Display | 600 (17pt) | 文件大小数字 |

---

## 3. 间距 Token

| Token | 值 | 用途 |
|---|---|---|
| `space.xxs` | 2pt | 极小间距 |
| `space.xs` | 4pt | 图标内边距 |
| `space.sm` | 8pt | 行内间距 |
| `space.md` | 16pt | 区块间距 |
| `space.lg` | 24pt | 大区块 |
| `space.xl` | 32pt | 视图间距 |
| `space.xxl` | 48pt | 页面顶部留白 |

### 3.1 圆角

| Token | 值 | 用途 |
|---|---|---|
| `radius.sm` | 4pt | 复选框、徽标 |
| `radius.md` | 8pt | 按钮、卡片 |
| `radius.lg` | 12pt | 模态框 |
| `radius.xl` | 16pt | 大卡片 |

---

## 4. 4 级树 UI 文字 Mockup

### 4.1 完整布局

```
┌────────────────────────────────────────────────────────────────────┐
│ [⚙] kSpaceClean                            [扫] [清] [⚠] [👤]      │  ← Toolbar (64pt)
├────────────────────────────────────────────────────────────────────┤
│ 扫描完成 · 共 24.6 GB                                              │
│ ─────────────────────────────────────────────────────────────────── │
│ ✓ System Junk                                                      │
│ ✓ App Junk                                                         │
│ ✓ Internet Junk                                                    │
│ ✓ Mail Attachments                                                 │
│ ✓ Developer Junk                                                  │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│ ▼ 📁 系统缓存                              12.4 GB    [🟢 推荐]    │  ← Level 1: Category
│   ▼ 系统缓存 (/Library/Caches)               4.2 GB    [🟢 推荐]    │  ← Level 2: SubCategory
│     ☑ com.apple.Safari.cache                2.1 GB    [🟢 推荐]    │  ← Level 4: Result
│     ☑ com.apple.QuickLook.cache             1.8 GB    [🟢 推荐]    │
│     ☑ ...                                                         │
│   ▼ 系统日志 (/var/log)                      320 MB    [⚪ 可选]    │
│     ☐ system.log                            280 MB    [⚪ 可选]    │
│     ☐ install.log                           40 MB     [⚪ 可选]    │
│   ▼ Quick Look 缓存                          80 MB     [🟢 推荐]    │
│     ☑ thumbnail.db                          80 MB     [🟢 推荐]    │
│                                                                    │
│ ▼ 📁 应用缓存                               8.7 GB     [🟢 推荐]    │
│   ▼ 微信 (com.tencent.xinWeChat)            3.1 GB     [🟠 谨慎]    │  ← SubCategory w/ Actions
│     ▼ [💾] 缓存                                 1.8 GB    [🟢 推荐]    │  ← Level 3: Action
│       ☑ ~/Library/Caches/com.tencent...    1.2 GB    [🟢 推荐]    │
│       ☑ ~/Library/Application Support/...  600 MB    [🟢 推荐]    │
│     ▼ [📝] 日志                                 200 MB    [⚪ 可选]    │
│       ☐ ~/Library/Logs/com.tencent...      200 MB    [⚪ 可选]    │
│     ▼ [💿] 数据库                              1.1 GB    [🟠 谨慎]    │
│       ☐ ~/Library/Application Support/...  1.1 GB    [🟠 谨慎]    │
│   ▼ Chrome (com.google.Chrome)              1.2 GB     [🟢 推荐]    │
│     ☑ ~/Library/Caches/com.google.Chrome   1.0 GB    [🟢 推荐]    │
│     ☐ ~/Library/Cookies                     80 MB     [🟠 谨慎]    │
│   ...                                                              │
│                                                                    │
│ ▼ 📁 上网垃圾                                4.5 GB     [🟠 谨慎]    │
│   ▼ Safari 历史                              240 MB     [⚪ 可选]    │
│   ▼ Chrome Cookies                           80 MB      [🟠 谨慎]    │
│   ▼ ...                                                          │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│ 已选 18.2 GB · 327 项                [全选] [反选]  [清 理]        │  ← Summary Bar (sticky 64pt)
└────────────────────────────────────────────────────────────────────┘
```

### 4.2 关键行视觉规格

每行 48pt 高，padding 12pt，结构：

```
┌─────────────────────────────────────────────────────────────────────┐
│ [☐] [📁] 系统缓存         /Library/Caches       12.4 GB  [🟢]   [▶]  │
└─────────────────────────────────────────────────────────────────────┘
 ↑     ↑      ↑                  ↑                  ↑       ↑      ↑
checkbox icon  title(17pt)    path(11pt)        size(13pt) badge  chevron
 18pt  24pt   15pt Medium      SF Mono          right-aligned 8pt   8pt
       NSWorkspace
```

行内间距：12pt（left padding）+ 8pt（checkbox → icon）+ 8pt（icon → title）+ flex（title → path）+ 8pt（path → size）+ 8pt（size → badge）+ 12pt（right padding）

### 4.3 状态视觉

| 状态 | 视觉 |
|---|---|
| 未扫描 | 行 50% 透明，placeholder text "..." |
| 扫描中 | 行背景 `bg.surface`，spinner 替代 chevron，文字 `text.secondary` |
| 扫描完成 | 行 100%，数字稳定 |
| 选中 | checkbox `☑` 状态，行左边 2pt `brand.primary` 强调条 |
| Hover | 行背景 `bg.surface`，200ms easeOutQuart |

---

## 5. 风险徽标视觉

### 5.1 4 级徽标

| 级别 | 颜色 | Icon | Label | 默认状态 |
|---|---|---|---|---|
| 🟢 Recommended | `#34C759` | `checkmark.circle.fill` | "推荐" | ✅ On |
| ⚪ Optional | `#8E8E93` | `circle` | "可选" | ⬜ Off |
| 🟠 Caution | `#FF9500` | `exclamationmark.triangle.fill` | "谨慎" | ⬜ Off |
| 🔴 Dangerous | `#FF3B30` | `flame.fill` | "危险" | ⬜ Off |

### 5.2 徽标组件规格

```swift
struct RiskBadge: View {
    let level: RiskLevel
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(level.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(level.foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(level.backgroundColor.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(level.backgroundColor.opacity(0.4), lineWidth: 0.5)
        )
    }
}
```

尺寸：动态宽（≈ 50-60pt 宽 × 18pt 高），右上角 8pt 边距。

---

## 6. 级联 Checkbox 视觉

### 6.1 3 态设计

| 状态 | 视觉 |
|---|---|
| Off | 空心方框，1.5pt 边框，`text.tertiary` 色 |
| On | 填充 `brand.primary`，白色勾 |
| Mixed | 填充 `brand.primary`，白色勾 + 中横线 |

### 6.2 组件规格

```swift
struct IndeterminateCheckbox: View {
    let state: CheckState
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(state == .off ? Color.clear : Color.brand.primary)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(state == .off ? Color.text.tertiary : Color.clear, lineWidth: 1.5)
                )
            if state == .mixed {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else if state == .on {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.easeOut(duration: 0.15), value: state)
    }
}
```

尺寸：18pt × 18pt，圆角 4pt。

### 6.3 Hover 反馈

鼠标 hover 时边框色变 `text.secondary`，200ms easeOutQuart。

---

## 7. DaisyDisk 动画曲线

| 场景 | SwiftUI 实现 | 时长 |
|---|---|---|
| Hover | `.animation(.easeOut(duration: 0.24), value: isHovered)` | 240ms |
| 树展开/折叠 | `.animation(.easeInOut(duration: 0.20), value: isExpanded)` | 200ms |
| 风险徽标出现 | `.transition(.scale.combined(with: .opacity))` + spring | 300ms |
| 选中状态切换 | `.animation(.easeOut(duration: 0.15), value: state)` | 150ms |
| 数字滚动 | `numericText(countsUp: true)` + linear | 400ms |
| 删除完成 | `.animation(.timingCurve(0.7, 0, 0.3, 1).speed(1.2), value: isDeleted)` | 1200ms |
| 进度环填充 | `.animation(.linear(duration: 0.1), value: progress)` | 100ms / 帧 |
| Warning Toast 出现 | spring(response: 0.4, dampingFraction: 0.7) | - |

---

## 8. 关键组件清单

| 组件 | 路径 | 备注 |
|---|---|---|
| `RiskBadge` | `Features/Common/RiskBadge.swift` | 4 级徽标 |
| `IndeterminateCheckbox` | `Features/Common/IndeterminateCheckbox.swift` | 3 态复选框 |
| `ScanTreeRow` | `Features/SmartScan/Views/ScanTreeRow.swift` | 通用 4 级树行（按 Level 区分） |
| `ScanResultsView` | `Features/SmartScan/Views/ScanResultsView.swift` | 4 级树主视图 |
| `ScanProgressRing` | `Features/SmartScan/Views/ScanProgressRing.swift` | 圆环进度 |
| `ScanProgressView` | `Features/SmartScan/Views/ScanProgressView.swift` | 圆环 + 阶段列表 + 当前路径 |
| `WarningToast` | `Features/Cleanup/WarningToast.swift` | 运行中应用警告 |
| `WarnItemSheet` | `Features/Cleanup/WarnItemSheet.swift` | 警告项 sheet（跳过/强制 terminate/取消） |
| `CleanupConfirmSheet` | `Features/Cleanup/CleanupConfirmSheet.swift` | 风险分级确认 sheet |
| `DangerousConfirmDialog` | `Features/Cleanup/DangerousConfirmDialog.swift` | 输入 DELETE 二次确认 |
| `SummaryBar` | `Features/SmartScan/Views/SummaryBar.swift` | 底部 sticky |

---

## 9. 布局原则

### 9.1 窗口结构（macOS）

```
┌─────────────────────────────────────────────────────────┐
│ [● ● ●]      kSpaceClean                                  │  ← Title bar (28pt, traffic light)
├─────────────────────────────────────────────────────────┤
│ [⚙] kSpaceClean                  [扫] [清] [⚠] [👤]      │  ← Toolbar (64pt)
├─────────────────────────────────────────────────────────┤
│                                                          │
│                                                          │
│           4 级树主内容区（滚动）                          │  ← Content (flex)
│                                                          │
│                                                          │
├─────────────────────────────────────────────────────────┤
│ 已选 18.2 GB · 327 项    [全选] [反选]  [清 理]         │  ← Summary bar (sticky 64pt)
└─────────────────────────────────────────────────────────┘
```

### 9.2 窗口尺寸

- 最小宽度：720pt
- 推荐宽度：960pt
- 默认宽度：960pt
- 默认高度：720pt
- 最小高度：480pt

### 9.3 Toolbar 规格

- 高 64pt，背景 `bg.elevated`
- 左：Logo + App 名
- 右：扫描 / 清理 / 警告 / 用户头像
- 按钮：32pt × 32pt 圆角图标按钮

### 9.4 Summary Bar 规格

- 高 64pt，sticky 底部，背景 `bg.elevated`
- 左：已选总大小 + 项数（17pt Medium）
- 中：全选 / 反选（按钮组）
- 右：清理按钮（高亮 `brand.primary`，44pt × 32pt 圆角）

---

## 10. Warning 流程视觉

### 10.1 Warning Toast（用户在结果页点击"清理"）

```
┌──────────────────────────────────────────────────────────────┐
│ ⚠ 检测到 3 个运行中应用涉及您选择的清理项                       │
│                                                              │
│   • 微信 (com.tencent.xinWeChat) - PID 12345                 │
│     冲突路径 12 个 · 共 1.2 GB                                │
│   • Chrome (com.google.Chrome) - PID 23456                    │
│     冲突路径 3 个 · 共 80 MB                                  │
│   • QQ (com.tencent.qq) - PID 34567                          │
│     冲突路径 5 个 · 共 240 MB                                 │
│                                                              │
│   [跳过这些项]  [强制关闭并清理]  [取消清理]                   │
└──────────────────────────────────────────────────────────────┘
```

样式：
- 居中弹出，480pt 宽
- 背景 `bg.elevated`，边框 1pt `state.warning`
- 标题 17pt Medium 黄色
- 项列表：13pt Regular
- 按钮：3 个等宽

### 10.2 清理分级确认 Sheet

```
Recommended + Optional 项 → 不弹，直接清理
包含 Caution 项 → 单确认 sheet
包含 Dangerous 项 → 双确认 + 输入 DELETE
永久删除 → 三确认 + 高亮按钮
```

---

## 11. 与 Apple HIG 对齐

| 项 | Apple HIG | 我们的实现 |
|---|---|---|
| 暗色 | System Materials | `#0F1012` + 60% 透明材质 |
| 字体 | SF Pro | SF Pro Display / Text / Mono |
| 间距 | 4pt grid | 4pt / 8pt / 16pt / 24pt |
| 圆角 | System 8pt | 4pt / 8pt / 12pt / 16pt |
| 复选框 | iOS 风格 | 18pt × 18pt 圆角 4pt |
| 按钮 | 32pt × 32pt | 32pt × 32pt 圆角图标按钮 |

---

## 12. 实施检查清单

- [ ] DesignSystem/Colors.swift 定义所有 token
- [ ] DesignSystem/Typography.swift 定义所有字体 token
- [ ] DesignSystem/Spacing.swift 定义所有间距 token
- [ ] RiskBadge 组件实现（4 级）
- [ ] IndeterminateCheckbox 组件实现（3 态）
- [ ] ScanTreeRow 组件实现（4 级差异化）
- [ ] ScanResultsView 主视图
- [ ] ScanProgressRing / ScanProgressView
- [ ] Warning 流程（W18 + W19）
- [ ] 清理分级确认 sheet
- [ ] Summary Bar
- [ ] Toolbar
- [ ] 暗色 / 亮色 / 高对比度模式（系统设置自动跟随）

---

## 13. 状态设计三态

### 13.1 空状态（Empty State）

**场景 1：首次启动**

```
       ╭─────────────╮
       │   3D 星系   │
       │   占位图    │
       ╰─────────────╯

    Mac 存储清理，从这里开始

    kSpaceClean 会扫描你 Mac 上可以安全清理的文件，
    给你一个详细列表。

              [ 开 始 扫 描 ]
```

**场景 2：扫描结果为 0**

```
       ╭─────────────╮
       │  ✓ 笑脸     │
       ╰─────────────╯

       Mac 已经干干净净

    没有发现可以安全清理的文件。下次扫描建议在 7 天后。

              [ 重 新 扫 描 ]
```

**场景 3：清理完成**

```
       ╭─────────────╮
       │ ✓ 大对勾    │
       ╰─────────────╯

    清理完成 · 释放了 24.6 GB

    包含 327 项 · 耗时 18 秒 · 可在清理历史中恢复

    [ 查看清理历史 ]   [ 完 成 ]
```

**场景 4：无清理历史**

```
       ╭─────────────╮
       │   时钟      │
       ╰─────────────╯

       还没有清理记录

    你的第一次清理完成后，30 天内的清理记录会在这里显示。
```

### 13.2 错误状态（Error State）

**场景 1：无 FDA 权限**

```
       ╭─────────────╮
       │  盾牌 + 锁  │
       ╰─────────────╯

    需要 Full Disk Access 权限

    kSpaceClean 需要 Full Disk Access 才能扫描
    你 Mac 上的所有可清理文件。

    [ 打开系统设置 ]   [ 了解 FDA ]
```

**场景 2：扫描失败**

```
       ╭─────────────╮
       │ ⚠ 警告三角  │
       ╰─────────────╯

       扫描未完成

    扫描过程中遇到 3 个错误，部分文件未扫描。

    [ 查看错误详情 ]   [ 重新扫描 ]
```

**场景 3：清理失败（部分文件被占用）**

```
       ╭─────────────╮
       │  碎文件     │
       ╰─────────────╯

       清理未完成

    324 项清理成功，3 项失败（文件被其他应用占用）。

    [ 查看失败列表 ]   [ 重新尝试 ]
```

**场景 4：磁盘满**

```
       ╭─────────────╮
       │  磁盘警告   │
       ╰─────────────╯

    无法清理 · 磁盘空间不足

    需要至少 1 GB 可用空间执行清理。

              [ 了 解 详 情 ]
```

### 13.3 加载状态（Loading State）

**场景 1：扫描开始（0 结果到第一个结果）**

- 圆环进度环：0% → 当前进度（线性增长）
- 当前路径："准备扫描 ~/Library/Caches..."
- 阶段列表：✓ System Junk / ● Mail Attachments / ○ Photo Junk / ○ iOS Backups

**场景 2：清理执行中**

- 圆环进度环：0% → 100%
- 实时日志："已清理 18 / 327 项 · 4.2 GB / 24.6 GB"
- 速度："40 MB/s"
- 取消按钮：[取消清理]

**场景 3：清理历史加载**

- 顶部骨架屏（Skeleton Row）
- 行级占位：图标 + 灰条 + 灰条 + 灰条
- 占位条背景：`bg.surface`，动画：1.5s linear 透明度 0.3 → 0.6 → 0.3

---

## 14. 无障碍（Accessibility）

### 14.1 VoiceOver

所有 UI 元素必须有 `accessibilityLabel`：

| 元素 | VoiceOver Label |
|---|---|
| Checkbox | "系统缓存，4.2 GB，已勾选，推荐" |
| 风险徽标 | "风险等级，谨慎，建议不勾选" |
| 文件路径 | "路径：~/Library/Caches/com.tencent.xinWeChat/file.bin" |
| Category 行 | "系统缓存分类，共 12.4 GB，已展开" |
| Action 行 | "缓存动作，1.8 GB，未勾选" |

### 14.2 Dynamic Type

字体大小支持 macOS 系统设置：
- Standard / Large / Extra Large / Huge
- 行高自动调整（1.2x → 1.4x）
- 间距不变（避免布局错乱）

### 14.3 高对比度模式

跟随系统设置：
- Increase Contrast: 边框 1.5pt → 2.5pt
- Reduce Transparency: 背景从半透明 → 实色
- Differentiate Without Color: 风险徽标加边框区分

### 14.4 Reduce Motion

系统设置开启 Reduce Motion 时：
- 取消 scale / rotate 动画
- 仅保留 fade + linear 移动
- 圆环进度用线性渐变而非旋转
- 树展开 / 折叠用 fade 而非 slide

---

## 15. 键盘快捷键全谱

| 快捷键 | 功能 | 场景 |
|---|---|---|
| ⌘ N | 新建 Smart Scan | 全局 |
| ⌘ R | 重新扫描 | 扫描页 |
| ⌘ ⏎ | 开始扫描 / 确认清理 | 扫描页 / 确认 sheet |
| ⌘ . | 取消 | 全局 |
| ⌘ 0 | 4 级树全部展开 | 结果页 |
| ⌘ 1 | 仅显示 Recommended | 结果页 |
| ⌘ 2 | 仅显示 Caution | 结果页 |
| ⌘ 3 | 仅显示 Dangerous | 结果页 |
| ⌘ 4 | 全部显示 | 结果页 |
| ⌘ F | 搜索 / 筛选 | 结果页 |
| ⌘ A | 全选 | 结果页 |
| ⌘ ⇧ A | 反选 | 结果页 |
| ⌘ Delete | 清理选中项 | 结果页 |
| Space | 展开 / 折叠当前行 | 结果页 |
| ↑ / ↓ | 上下移动焦点 | 结果页 |
| ← / → | 折叠 / 展开 | 结果页 |
| Tab | 焦点切换 | 全局 |
| Esc | 关闭 sheet | sheet |
| ⌘ , | 偏好设置 | 全局 |
| ⌘ Q | 退出 | 全局 |

**原则**：
- 所有主功能都有快捷键
- 与 macOS 标准快捷键一致（⌘A 全选、⌘F 搜索等）
- 不与系统快捷键冲突（⌘ Space / ⌘ Tab 等）

---

## 16. 空状态插画（Empty State Illustration）

### 16.1 设计原则

- **SF Symbols 优先**（Apple HIG 推荐）
- 不使用第三方插画库
- 矢量、单色、跟随系统 accent color
- 视觉风格统一（即便 v1.0 不做星系图）

### 16.2 插画清单

| 插画场景 | SF Symbol | 颜色 |
|---|---|---|
| 首次启动 | `sparkles` 或自绘 3D 球 | brand.primary |
| 扫描结果为 0 | `checkmark.seal.fill` | risk.recommended |
| 清理完成 | `checkmark.circle.fill` | risk.recommended |
| 无清理历史 | `clock.arrow.circlepath` | text.secondary |
| 无 FDA 权限 | `lock.shield.fill` | state.warning |
| 扫描失败 | `exclamationmark.triangle.fill` | risk.caution |
| 清理失败 | `xmark.octagon.fill` | state.error |
| 磁盘满 | `internaldrive.fill` | state.error |

### 16.3 插画规格

- 尺寸：96pt × 96pt 主插画
- 颜色：跟随系统 accent color（用户在系统设置里改 → 插画跟着改）
- 位置：视图中央偏上 40%
- 标题：24pt Medium，1.3× 行高，最大宽度 480pt
- 副标题：15pt Regular，1.4× 行高，最大宽度 400pt
- 主按钮：44pt × 32pt 圆角，`brand.primary` 背景
- 次按钮：44pt × 32pt 圆角，`bg.elevated` 背景

### 16.4 自定义插画（首次启动）

首次启动的 3D 球自绘插画规格：
- SceneKit 渲染（不实际部署 v1.0，但设计稿占位）
- 球体直径 80pt
- 6 个小球围绕（代表 6 个 Category）
- 颜色：brand.gradientStart → brand.gradientEnd
- 旋转：3 秒 / 圈，linear

---

## 17. 实施检查清单（修订）

- [ ] DesignSystem/Colors.swift 定义所有 token
- [ ] DesignSystem/Typography.swift 定义所有字体 token
- [ ] DesignSystem/Spacing.swift 定义所有间距 token
- [ ] DesignSystem/Accessibility.swift 定义 VoiceOver / Dynamic Type / Reduce Motion 检测
- [ ] DesignSystem/KeyboardShortcuts.swift 定义所有快捷键
- [ ] RiskBadge 组件实现（4 级）
- [ ] IndeterminateCheckbox 组件实现（3 态）
- [ ] ScanTreeRow 组件实现（4 级差异化）
- [ ] ScanResultsView 主视图
- [ ] ScanProgressRing / ScanProgressView
- [ ] Warning 流程（W18 + W19）
- [ ] 清理分级确认 sheet
- [ ] Summary Bar
- [ ] Toolbar
- [ ] **空状态插画**（8 个场景）
- [ ] **错误状态**（4 个场景）
- [ ] **加载骨架屏**
- [ ] **VoiceOver 标签**（全 UI 元素）
- [ ] **Dynamic Type**（4 档）
- [ ] **Reduce Motion 检测**
- [ ] **高对比度模式**
- [ ] **键盘快捷键实现**（20 个）
- [ ] 暗色 / 亮色 / 高对比度模式（系统设置自动跟随）

---

最后更新：2026-07-29（基于 25 个决策 + Apple HIG 4 项补全）