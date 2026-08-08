# Domain Docs

工程技能在探索代码库时，应如何消费本仓库的领域文档。

## 探索前先读

- 根目录的 **`CONTEXT.md`**，或
- 若存在 **`CONTEXT-MAP.md`** —— 它指向每个上下文各自的 `CONTEXT.md`，读取与主题相关的每一个。

这些文件不存在时**静默继续**。不要标注缺失，也不要在初期建议创建。`/domain-modeling` 技能（经 `/grill-with-docs` 与 `/improve-codebase-architecture` 触达）会在术语或决策真正落地时惰性创建它们。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

## 使用词汇表里的术语

当你的输出命名一个领域概念（issue 标题、重构提案、假设、测试名）时，使用 `CONTEXT.md` 中定义的说法，不要滑向词汇表明确避开的同义词。

如果所需概念不在词汇表中，这是一个信号 —— 要么你在发明项目未使用的语言（三思），要么存在真实缺口（记下，交给 `/domain-modeling`）。

## 标注 ADR 冲突

若你的产出与既有 ADR 矛盾，显式标注而不是静默覆盖：

> _与 ADR-0007（event-sourced orders）冲突 —— 但值得重新审视，因为…_
