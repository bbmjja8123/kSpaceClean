# Klaris P0 归因引擎 — 真机验收操作手册

日期：2026-09-28 ｜ 对应 spec §8 四条验收（经最终评审修订：验收 2 口径已改）
前置：P0 已实现（commits `8e21a8e..2fa57b7`），全量测试 564+/0 绿
预计耗时：45–60 分钟 ｜ 结果记录：文末模板，填完贴回 PR / 汇报

---

## 0. 准备（5 分钟）

```bash
# 1. 构建并运行（Xcode 中选 kWise scheme → Cmd+R，或命令行确认编译干净）
cd kWise && xcodegen generate   # 仅当 pbxproj 有未提交变更时才需要
xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWise 2>&1 | tail -3
```

- [ ] 编译零错误（Task 5 遗留 warning 1 条为已知）
- [ ] App 启动后菜单栏/关于窗口显示 **Klaris**（CFBundleName 已改；若仍显示 kWise → 记缺陷）

## 1. 验收一：Top-20 归因全 L0 + 理由链（北极星，30 分钟）

**步骤**
1. 首次启动走完 Onboarding / PowerScope 主目录授权
2. 主界面跑一次完整扫描（等待完成）
3. 工具箱 → **归因透视** → 点「重新归因」
4. 看「占用最大的项目」列表，逐项展开「理由」

**判定**
- [ ] Top-20 中**每一项**都有：归属（App 名/macOS/未知）+ 原因标签 + 可回收性徽章 + ≥2 条可展开的证据（路径规则/依据规则 ID/最后修改）
- [ ] 「依据规则 xxx」里的规则能在「归因规则」页找到对应条目
- [ ] **没有**出现「最后修改：」空参数行（T5 契约）
- [ ] 没有任何清理按钮/入口（归因是纯描述）

**本机特有的大项若归因错误或缺失** → 记录路径，P0 验收后补语料规则（每条需 owner/cause/reclaim/notesKey 四件套，审计测试会拦不完整条目）。**这就是「语料深度」假设的直接验证——记录你作为第一个用户的真实感受：这些解释值不值得信。**

## 2. 验收二（口径已修订）：扫描外空间对账（10 分钟）

> ⚠️ 原定「残差 <5%」**作废**（最终评审 I1：扫描树只覆盖 8 个清理类目，残差天然大）。新口径：黑盒卡 = 扫描外空间，须与独立工具对账一致且**文案诚实**。

**步骤**
```bash
df -h /                                   # 记录卷用量（Used）
diskutil info -plist / | grep -A1 -i available   # 备用
```
1. 对比黑盒卡「扫描未覆盖的空间 ≈ X」与 `df` 的 Used − 你直觉已知的大头（用 DaisyDisk/GrandPerspective 抽查 1-2 个目录佐证）
2. 量级应一致（黑盒 ≈ 卷用量 − 8 类目合计）；**允许大**，因为文档/照片/应用本来就在扫描外
3. 卡片必须出现**「不是垃圾」字样**（I1 修订的诚实文案）——若显示旧版「黑盒空间（快照与系统保留）」→ 记缺陷

## 3. 快照核对（5 分钟）

```bash
diskutil apfs listSnapshots /             # 人工数个数
diskutil apfs listSnapshots -plist / > /tmp/snaps.plist
plutil -p /tmp/snaps.plist | head -30     # 核对字段名（Name/CreationDate?）
```
- [ ] 黑盒卡「本地快照 N 个」与人工计数一致
- [ ] **fixture 校准**：`plutil -p` 输出的字段名与 `kWise/Tests/Fixtures/apfs_snapshots.plist` 一致？不一致 → 改 fixture + `VolumeLayerReader.parseSnapshotPlist` 的键名，重跑 `VolumeLayerReaderTests`（这是计划标注的执行期校准点）
- [ ] 无快照时卡片不显示快照行（不为 0 而显示）

## 4. 验收三：拒答诚实性（10 分钟）

**场景 A（正常）**
- [ ] 微信/未匹配大项出现在「我不敢判的（N 项）」，横幅「这些项我们判断不了安全性…」完整
- [ ] 有规则的拒答项（如微信）显示其 notes 说明；未匹配大项不显示 notes 行（T8 契约）

**场景 B（撤权）**
1. 系统设置 → 隐私与安全性 → 文件与文件夹 → 撤销 Klaris 的主目录授权（或在 App 内重置 PowerScope）
2. 重扫 + 重新归因
- [ ] 结果诚实：拒答清单变化有解释 / 空态不冒充「一切干净」
- [ ] **绝不能**出现数字凭空变小装作「清理生效」

**场景 C（负残差）**——若 `df` 的 Used 小于扫描合计（少见）：
- [ ] 卡片显示「样本不足」类诚实文案，**不显示「约 0 B」**（I3 修复验证）

## 5. 验收四：自动化审计（已绿，记录即可）

```bash
xcodebuild test-without-building -workspace KraftlyWorkspace.xcworkspace -scheme kWise \
  -only-testing:kWiseTests/AttributionCopyAuditTests \
  -only-testing:kWiseTests/LocalizationCompletenessTests \
  -only-testing:kWiseTests/NewCopyAuditTests 2>&1 | grep -E "Executed|TEST"
```
- [ ] 三套件全绿（恐吓禁语双层 + 三语完整性）

## 6. 语料真机校正（随验收一顺带）

逐条 `ls` 检查语料路径在本机是否存在（存在且未被归因 = 扫描根缺口；不存在 = 记录，勿删规则）：

| 规则 | 命令 | 存在? |
|---|---|---|
| xcode.derived-data | `ls ~/Library/Developer/Xcode/DerivedData` | |
| docker.disk-image | `ls ~/Library/Containers/com.docker.docker/Data/vms` | |
| ai.models-intelligence | `ls /System/Library/AssetsV2/com.apple.appleintelligence` | |
| wechat.files | `ls ~/Library/Containers/com.tencent.xinWeChat` | |
| imessage.attachments | `ls ~/Library/Messages/Attachments`（预期沙箱不可读→拒答/黑盒） | |
| podcasts.downloads | `ls ~/Library/Containers/com.apple.podcasts` | |
| feishu.files（bundleID 真机核对） | `ls ~/Library/Containers | grep -i lark` | |

## 7. 已知注意事项

- **测试环境 wedge**：全量测试可能挂起（首测宿主启动相关，重启即消）——验收只跑上面的聚焦批次即可
- 归因页刷新依赖 diskutil（无超时，deferred）——若长时间转圈记入报告，属已知 M3
- 三条规则（ai.models / imessage / xcode.device-support）为显式豁免的「卷层引导规则」，文件树不可达是**设计内**行为（P1 经黑盒分解接线）

## 结果记录模板

```
验收人 / 机型 / 系统版本：
1. Top-20 L0 覆盖：__/20 通过；补充语料规则数：__
   「解释可信度」主观评分（1-5）：__ 一句话：__
2. 扫描外空间对账：df Used=__，黑盒卡=__，量级一致? Y/N
3. 快照：diskutil=__，卡片=__，fixture 字段一致? Y/N
4. 拒答：场景A Y/N，场景B Y/N，场景C（如适用）Y/N
5. 审计三套件：绿? Y/N
6. 语料校正发现：
缺陷清单（编号/路径/截图）：
结论：P0 验收通过？ Y / N+理由
```
