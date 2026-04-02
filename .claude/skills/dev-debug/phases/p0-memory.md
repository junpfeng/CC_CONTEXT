## Phase 0：记忆查询（前置步骤）

在正式分析之前，查询历史 bug 经验，避免重复踩坑。

### 0.1 提取搜索关键词

从用户输入的 bug 描述中提取 2-3 个核心关键词：
- 模块名（如 `模块名`、`服务名`）
- 错误类型（如 `panic`、`nil pointer`、`deadlock`）
- 功能名（如 `功能名`、`接口名`）

### 0.2 查阅项目记忆

- **Auto Memory**（`MEMORY.md`）中的"已知问题"章节
- **项目调试文档**（如有，参照项目 `CLAUDE.md` 或 `docs/knowledge/` 目录下的文档）

### 0.3 查阅错误模式库

- 检查 `docs/knowledge/error-patterns.md` 是否存在
- 存在则按关键词搜索匹配的已知错误模式（EP 条目）
- 命中则列出匹配的模式编号、症状、根因、解决方案
- 不存在则跳过（不阻塞流程）

### 0.4 输出记忆摘要

如果有命中相关记录：

```
历史 bug 经验：
- [来源] 曾遇到过类似的 XXX 问题，根因是 YYY
- [来源] 解决方案：ZZZ
- 需要注意的坑：...

错误模式匹配结果：
- [EP-XXX] 症状：... | 根因：... | 解决方案：...
```

如果没有命中，输出"未找到相关历史 bug 经验"并继续。

### 0.5 Bug 追踪登记检查

当 `--caller` 为 `direct`（或未指定）且 `--mode` 不是 `acceptance` 时：

1. 从 bug 描述中提取关键词，尝试匹配 `docs/bugs/` 下的已有条目（grep `- [ ]` 行）
2. 若已有匹配条目 → 记录 bug 路径，供 P4.6 修复后更新状态
3. 若无匹配条目 → 自动推导 version 和 feature：
   - **version**：优先读 `docs/bugs/` 下最新的 semver 目录名（如 `0.0.3`）。仅当 git branch 名匹配 `\d+\.\d+\.\d+/` 格式时从分支提取。版本号必须是 `X.X.X` 数字格式
   - **feature**：从 bug 描述模块推断（如 `BigWorld_NPC`），使用下划线命名
   - 调用 `bug:report {version} {feature} {bug 描述一句话}` 登记
   - 记录新建的 bug 路径，供 P4.6 使用

**跳过条件**（任一满足则跳过）：
- `--caller bug-explore`：已由 bug-explore Phase 4 Step 1 登记
- `--caller new-feature`：已由 new-feature Step 5.4.1 登记
- `--mode acceptance`：验收模式，bug 已由上游登记

### 0.6 严重度快速路径判定

从 bug 描述或已登记的 bug 条目中提取严重度标签（`compile-error` / `config-missing` / `logic-bug` / `visual-bug`）。

**快速路径**（severity 为 `compile-error` 或 `config-missing` 时）：
1. 跳过 P0 的历史记忆查询（0.3/0.4 节）— 编译/配置问题无需历史经验匹配
2. 在 P1 中跳过 Stage 2 深度采集（仅执行 Stage 1 轻量采集）
3. 直接进入 P2 定位 → P3 修复

**完整路径**（severity 为 `logic-bug` 或 `visual-bug` 时）：
- 正常执行 P0-P4 全流程

> 注意：严重度由 bug:report 自动分类写入，dev-debug 只读取不修改。若 bug 条目中无严重度字段，默认按 `logic-bug` 处理（完整路径）。

### 容错规则

- Phase 0 不阻塞主流程，搜索失败或登记失败不影响后续阶段
