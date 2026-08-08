# Kraftly 4-Worktree 合并节奏

> 本文件定义 4 个永久 worktree（kWise / kWatch / kSift / kFresh）如何向 `main` 合并的策略、节奏与冲突处理。

## 1. 布局

| App | 分支 | Worktree 路径 |
|---|---|---|
| kWise | `worktree-kwise-v1` | `/Users/torsys/Documents/aicoding/kWise` |
| kWatch | `worktree-kwatch-v1` | `/Users/torsys/Documents/aicoding/kWatch` |
| kSift | `worktree-ksift-v1` | `/Users/torsys/Documents/aicoding/kSift` |
| kFresh | `worktree-kfresh-v1` | `/Users/torsys/Documents/aicoding/kFresh` |

主 worktree：`/Users/torsys/Documents/aicoding/kSpaceClean`（在 `main` 上，用于跨 App 整合 / 合并触发 / 上架准备）。

每个 worktree 共享同一个 `.git` 数据库，但 working tree 独立 —— 切到任意 worktree，状态相互可见但不会冲突。

## 2. 边界规则（严格）

每个 worktree **只能** commit 自己 App 目录下的改动：

| Worktree | 允许改动 | 禁止改动 |
|---|---|---|
| kWise/ | `kWise/` 全部 | `kWatch/`、`kSift/`、`kFresh/` |
| kWatch/ | `kWatch/` 全部 | `kWise/`、`kSift/`、`kFresh/` |
| kSift/ | `kSift/` 全部 | `kWise/`、`kWatch/`、`kFresh/` |
| kFresh/ | `kFresh/` 全部 | `kWise/`、`kWatch/`、`kSift/` |

**例外 —— 共享区域（需特别协调）**：

- `kFoundation/` —— 4 个 App 共用的 Swift 包
- `KraftlyWorkspace.xcworkspace` —— 顶层 workspace
- 根目录 `CLAUDE.md` / `.gitignore` / `.github/` —— 横切配置

任何对共享区域的改动，**必须**先在自己的 App 分支 commit，**先** merge 到 main，**再**让其他 worktree 拉取，避免分叉。

工具支持：`scripts/commit-app.sh <app>` 在试图 stage 越界路径时会拒绝；`kFoundation/` 需要 `--allow-kfoundation` 显式声明。

## 3. 合并节奏（3 种可选）

| 选项 | 触发 | 频率 | 适合 |
|---|---|---|---|
| **A. Feature 完成即合并** | 每个 App 完成一个 feature 后立刻 merge | 不定 | 团队协作 / CI 频繁集成 |
| **B. 周合并** | 每周固定日（如周五下午）批量 merge | 每周一次 | 独立开发者 / 节奏稳 |
| **C. 上架前集中合并** | App Store 提交前一周 | 季度级 | 准备上架 |

**当前默认：选项 B（每周五下午 16:00 merge window）**。节奏调整由开发者决定，更新到本文件 §3 即可。

## 4. 合并操作流程

从**主 worktree**（`kSpaceClean/`，在 `main` 上）执行：

```sh
cd /Users/torsys/Documents/aicoding/kSpaceClean

# 4.1 预检：当前在 main 分支、working tree 干净
git status
git rev-parse --abbrev-ref HEAD  # 应输出 main

# 4.2 执行合并
./scripts/merge-app-to-main.sh kWise    # 默认 --no-ff，可加 --squash / --ff-only / --abort

# 4.3 如果发生冲突
# 4.3.1 在主 worktree 解决冲突（编辑器 / git add / git commit）
# 4.3.2 手动 push：git push origin main
# 4.3.3 其他 worktree 拉取：cd ../kWatch && git pull origin main
```

合并成功后，工作流：

- 主 worktree 的 `main` 前进 N 个 commit
- 其他 worktree 在下一次 `git pull origin main` 时拉取（边界脚本 + 冲突解决后再继续工作）
- 远程 `worktree-<app>-v1` 分支保留所有历史，**不删除**

## 5. kFoundation 改动合并（特殊路径）

任何工作分支改了 `kFoundation/`，必须先单独 merge 到 main 后再继续：

```sh
# 在改了 kFoundation 的 worktree
cd ../kWatch
git add kFoundation/...
git commit -m "feat(kFoundation): add MultiProgress component"
git push origin worktree-kwatch-v1

# 回到主 worktree 立刻合并（不等合并窗口）
cd ../kSpaceClean
./scripts/merge-app-to-main.sh kWatch

# 其他 worktree 拉取
cd ../kWise && git pull origin main && swift build
cd ../kSift && git pull origin main && swift build
cd ../kFresh && git pull origin main && swift build
```

## 6. 冲突处理 SOP

### 6.1 主 worktree 内冲突（merge 时）

最常见。处理步骤：

1. `git status` 查看冲突文件
2. 编辑器打开冲突文件，搜索 `<<<<<<<` 标记
3. 手动决定保留哪一侧（或合并两侧）
4. `git add <resolved-files>`
5. `git commit` 完成 merge
6. `git push origin main`

### 6.2 共享文件分叉冲突（kFoundation / workspace / CLAUDE.md）

最容易出问题，因为两个 worktree 同时改了同一个共享文件。

**预防**：任何共享改动走 §5 的"先 merge kFoundation"路径。

**事后解决**：回到主 worktree，用 `git log --all --oneline -- <file>` 查两边历史，按时间顺序和语义合并。

### 6.3 二进制冲突（xcodeproj / xcassets）

低概率（因为每个 App 有自己的 xcodeproj）。如果发生：

```sh
# 取远程版本（丢弃本地）
git checkout --theirs path/to/file
git add path/to/file

# 或取本地版本
git checkout --ours path/to/file
git add path/to/file

# 重新打开 Xcode 让 pbxproj 重建索引
```

## 7. 紧急回滚

```sh
# 撤销最近一次 merge（保留改动在工作区）
git merge --abort

# 或撤销最近一次 merge（已 commit）
git reset --hard HEAD~1
git push --force-with-lease origin main  # ⚠️ 影响其他 worktree，需先通知
```

## 8. 验证清单（每次合并后跑一遍）

```sh
# 主 worktree
cd /Users/torsys/Documents/aicoding/kSpaceClean
./scripts/merge-app-to-main.sh kWise  # 假设刚 merge kWise
git log --oneline -5                   # 确认 main 前进
git worktree list                       # 5 行全在

# 其他 worktree
for d in kWise kWatch kSift kFresh; do
    (cd /Users/torsys/Documents/aicoding/$d && \
     echo "=== $d ===" && \
     git rev-parse --abbrev-ref HEAD && \
     git status --short && \
     swift build 2>&1 | tail -3)        # 各 App 自带 swift build 验证
done
```

## 9. 长期保留约定

**所有 4 个 worktree 永久保留**，不允许 `git worktree remove`。原因：

- 历史追溯：哪个 App 在哪个 commit 改了什么东西一目了然
- 紧急回滚：任何时候切回任一 worktree 重建状态
- 跨机器同步：第二台机器直接 `git fetch + worktree add` 即可复刻
- 合并演练：可以模拟 merge to main 而不污染当前工作

如果某个 App 长期无活动，分支保留，worktree 目录可以临时归档（`tar czf`）但不删除。