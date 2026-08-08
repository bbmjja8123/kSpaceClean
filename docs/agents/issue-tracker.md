# Issue tracker: GitHub

本仓库的问题与 spec 均作为 GitHub issue 托管，所有操作使用 `gh` CLI。

## 约定

- **创建 issue**：`gh issue create --title "..." --body "..."`，多行正文用 heredoc。
- **读取 issue**：`gh issue view <number> --comments`，可用 `jq` 过滤评论，并同时拉取标签。
- **列出 issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，配合 `--label` / `--state` 过滤。
- **评论 issue**：`gh issue comment <number> --body "..."`
- **打 / 去标签**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **关闭**：`gh issue close <number> --comment "..."`

从 `git remote -v` 推断仓库 —— 在 clone 内运行 `gh` 会自动完成。

## 将 PR 作为分诊入口

**PR 作为请求入口：否**（若本仓库把外部 PR 视作功能请求，可改为 `yes`，`/triage` 会读取该标志。）

设为 `yes` 时，PR 与 issue 走同样的标签与状态，使用 `gh pr` 对应命令：

- **读取 PR**：`gh pr view <number> --comments`，diff 用 `gh pr diff <number>`。
- **列出待分诊的外部 PR**：`gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`，仅保留 `authorAssociation` 为 `CONTRIBUTOR` / `FIRST_TIME_CONTRIBUTOR` / `NONE` 的（丢弃 `OWNER` / `MEMBER` / `COLLABORATOR`）。
- **评论 / 打标签 / 关闭**：`gh pr comment`、`gh pr edit --add-label` / `--remove-label`、`gh pr close`。

GitHub 上 issue 与 PR 共享同一编号空间，裸 `#42` 可能是二者之一 —— 先用 `gh pr view 42` 解析，回退到 `gh issue view 42`。

## 当技能说"发布到 issue tracker"

创建一个 GitHub issue。

## 当技能说"获取相关 ticket"

运行 `gh issue view <number> --comments`。

## Wayfinding 操作

供 `/wayfinder` 使用。**map** 是单个 issue，**child** 是作为 ticket 的子 issue。

- **Map**：带 `wayfinder:map` 标签的单个 issue，承载 Notes / Decisions-so-far / Fog 正文。`gh issue create --label wayfinder:map`。
- **子 ticket**：以 GitHub sub-issue（`gh api` 的 sub-issues 端点）关联到 map 的 issue。若未启用 sub-issues，则把子项加进 map 正文的任务清单，并在子项正文顶部写 `Part of #<map>`。标签：`wayfinder:<type>`（`research` / `prototype` / `grilling` / `task`）。认领后 ticket 指派给负责开发者。
- **阻塞**：GitHub 原生 issue 依赖 —— 规范、UI 可见的表示。用 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>` 加边，`<blocker-db-id>` 是阻塞方的**数据库 id**（`gh api repos/<owner>/<repo>/issues/<n> --jq .id`，不是 `#number` 或 `node_id`）。GitHub 上报 `issue_dependencies_summary.blocked_by`（仅未关闭的阻塞方，即实时闸门）。依赖不可用时，退化为在子项正文顶部写 `Blocked by: #<n>, #<n>`。所有阻塞方关闭后 ticket 才解除阻塞。
- **前沿查询**：列出 map 未关闭的子项（`gh issue list --state open`，限定到 map 的 sub-issues / 任务清单），剔除有未关闭阻塞方（`issue_dependencies_summary.blocked_by > 0`，或 `Blocked by` 行中有未关闭 issue）或已有 assignee 的；按 map 顺序取第一个。
- **认领**：`gh issue edit <n> --add-assignee @me` —— 会话的第一次写操作。
- **解决**：`gh issue comment <n> --body "<answer>"`，然后 `gh issue close <n>`，再往 map 的 Decisions-so-far 追加上下文指针（gist + 链接）。
