## Phase 0：记忆查询（前置步骤）

在正式分析之前，查询历史 bug 经验，避免重复踩坑。

### 0.1 提取搜索关键词

从用户输入的 bug 描述中提取 2-3 个核心关键词：
- 模块名（如 `模块名`、`服务名`）
- 错误类型（如 `panic`、`nil pointer`、`deadlock`）
- 功能名（如 `功能名`、`接口名`）

### 0.2 搜索历史记忆

使用 claude-mem 的 MCP 工具执行三层搜索：

**第 1 层：索引搜索** — 快速发现相关记录

```
search(query="<关键词1> bug", limit=10)
search(query="<关键词2> fix", limit=10)
```

**第 2 层：时间线上下文** — 对命中结果获取前后文

```
timeline(anchor=<id>, depth_before=3, depth_after=3)
```

**第 3 层：获取详情** — 只对确认相关的记录拉取完整内容

```
get_observations(ids=[<id1>, <id2>])
```

### 0.3 查阅项目记忆

除 claude-mem 外，还需查阅：
- **Auto Memory**（`MEMORY.md`）中的"已知问题"章节
- **项目调试文档**（如有，参照项目 `CLAUDE.md` 或 `docs/knowledge/` 目录下的文档）

### 0.4 输出记忆摘要

如果有命中相关记录：

```
历史 bug 经验：
- [来源] 曾遇到过类似的 XXX 问题，根因是 YYY
- [来源] 解决方案：ZZZ
- 需要注意的坑：...
```

如果没有命中，输出"未找到相关历史 bug 经验"并继续。

### 容错规则

- 如果 claude-mem MCP 工具不可用，**跳过 claude-mem 搜索**，仅查阅项目记忆
- Phase 0 不阻塞主流程，搜索失败不影响后续阶段
