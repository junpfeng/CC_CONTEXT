# Phase 7：经验沉淀

> 领域依赖：无

## 7.1 结构化 Meta-Review

读取 progress.json 和 `{design_doc_dir}/results.tsv`，对整个工作流进行定量分析。

> **注**：P4 波次间 Meta-Review（4.1.6）可能已生成部分规则和分析。P7 的 Meta-Review 是**累积性**的：跳过已在 `meta-review.md` 中记录的模式，只分析新增/全局模式。

### 统计汇总（优先从 results.tsv 提取）

**上下文控制**：仅读取 results.tsv 的**最近 50 行**进行模式检测（防止大文件膨胀主 agent 上下文）。全量统计（总任务数等）通过 `wc -l` + `grep -c` 完成，不将全文读入。

- 总任务数 / Keep 数 / Discard 数（results.tsv 的 decision 列）
- 平均修复轮次（results.tsv 的 attempt 列）
- 每个 wave 的耗时分布（results.tsv 的 duration_s 列，按 wave 分组）
- 审查质量趋势（results.tsv 的 review_critical / review_high 列，仅 phase=P6 的行）

### 模式检测

扫描以下重复模式：

| 模式类型 | 触发阈值 | 检测方法 |
|----------|----------|----------|
| 同类编译错误 | ≥2 个 task 出现相同错误类型（如 CS0104、undefined reference） | 按错误码/关键词聚类 |
| 同类 review issue | ≥2 轮审查出现相同类型问题（如"缺少错误处理"、"日志格式"） | 按问题描述关键词聚类 |
| Discard 率高 | discarded_tasks / total_tasks > 30% | 直接计算 |
| 修复轮次触顶 | ≥2 个 task 的 fix_rounds 达到上限（P5=3，P6=10） | 读 progress.json |

### 自动生成规则

对每个检测到的 pattern：
1. 草拟 `.claude/rules/auto-work-lesson-*.md` 规则内容（触发条件 + 规则 + 来源）
2. **去重检查**（机械化算法）：
   - 提取新规则标题的关键词（去掉停用词后的名词/动词，如"编译""日志""格式""截断"）
   - `grep -l` 在 `.claude/rules/auto-work-lesson-*.md` 的 `# ` 标题行中搜索这些关键词
   - 若某已有规则标题与新规则标题有 **≥3 个关键词重叠** → 视为重复，更新已有规则而非新增
   - 同时 `grep` `meta-review.md` 中 P4 波次间已记录的模式描述（搜索"模式"/"根因"/"规则"段落），若关键词命中 ≥3 个 → 已覆盖，跳过
3. **最多生成 3 条新规则**，避免过度规范化
4. 规则写入后记录到 progress.json

### 经验沉淀索引追加

将 7.1 中新生成的规则和经验追加到 `docs/knowledge/consolidation-index.md` 对应 section：
- 新增 auto-work-lesson → 追加到 `## Coding Rules` section：`- [lesson-NNN] {标题} → .claude/rules/auto-work-lesson-NNN.md`
- 新增知识库文档 → 追加到 `## Architecture Decisions` section：`- [AD-NNN] {标题} → docs/knowledge/{文件名}`
- 新增 review 检查项 → 追加到 `## Review Checklist Additions` section：`- [RC-NNN] {检查项}（来源：dev-workflow P7）`

> 若 consolidation-index.md 不存在则跳过。

### 正向模式检测

除了检测失败模式，也扫描成功模式：

| 模式类型 | 检测条件 | 记录方式 |
|----------|----------|----------|
| 一次通过 | task Keep 且 attempt=1（无修复轮） | 记录该 task 使用的设计模式和代码结构到 consolidation-index.md `## Architecture Decisions` |
| 高效波次 | 整个 wave 所有 task 均 Keep | 记录 wave 的任务组合策略到 meta-review.md |

正向模式不生成 rule 文件（rule 用于约束，不用于鼓励），仅记录到 consolidation-index.md 和 meta-review.md，供未来设计参考"什么做对了"。

## 7.2 经验分类沉淀

| 经验类型 | 沉淀目标 |
|----------|----------|
| 编码规范 | 对应子工程编码规范 |
| 领域知识 | 知识库中相关文档 |
| 架构约定 | 对应子工程项目说明 |
| Agent 优化 | Agent Memory |

### 流程

1. 识别经验类型 → 匹配目标文档 → Edit 追加 → 验证一致性
2. 自行判断是否有需记录的经验、需新增/修改的 Rules、需更新的知识库文档，直接执行

### 自动沉淀提醒

| 触发条件 | 建议沉淀到 |
|----------|-----------|
| 新存储限制/约束 | 知识库中数据库相关文档 |
| 新接口规范 | 知识库中协议相关文档 |
| 新测试技巧/工具 | 知识库中测试相关文档 |
| 重复编码问题 | 对应子工程编码规范 |
| 新架构约定 | 对应子工程项目说明 |

## 7.3 模块文档归档

将完成的功能总结归档到 `docs/knowledge/` 对应目录：
1. 确定模块归属（优先归入已有目录，全新领域创建新目录）
2. 基于实际代码生成：架构总览、核心流程、关键文件索引、网络协议（如有）
3. 已有文档采用追加/更新方式，不覆盖已有信息
4. 文档变更独立提交一个 Git commit

## 7.4.0 遗留 Bug 修复

检查 `{design_doc_dir}/p5-residual-bugs.md` 是否存在且有 OPEN 条目。若有：

1. 启动独立进程修复：
   ```bash
   claude -p "读取 {design_doc_dir}/p5-residual-bugs.md，对每个 OPEN 的 Bug 按 /dev-debug --mode acceptance --caller direct 修复。
   修复完成后更新 p5-residual-bugs.md 状态列，并更新 docs/bugs/ 归档状态。" \
     --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 60
   ```
2. 进程完成后检查结果——仍为 OPEN 的条目保留在 bug 追踪中，不阻塞推送

若文件不存在或无 OPEN 条目，跳过本步骤。

## 7.4 自动推送

> **提交时机**：P4（4.1.8）已在每个 task 编译通过后创建原子 commit。P7 只负责推送，不再重复提交。
> **例外**：P6 修复可能产生未提交的变更 → P7 先检查 `git status`，有未提交变更则为 P6 修复创建补充 commit 后再推送。

将 Client、Server、Proto 三个仓库的当前分支推送到各自远程：
- 仅推送有新 commit 的仓库，无新 commit 则跳过
- 禁止 force push
- 推送失败自动重试一次（参考 feedback_git_auth_retry）

## 7.4.1 生成引擎结果摘要

在推送完成后，生成 `{design_doc_dir}/engine-result.md` 供 new-feature Step 5 统一读取：

```markdown
## 引擎执行结果

- 引擎: dev-workflow
- 总任务数: {从 progress.json 读取}
- Keep: {keep 数}, Discard: {discard 数}
- 编译状态: {PASS/FAIL}
- 运行时验证: {PASS/FAIL/SKIPPED（P5 是否执行了 MCP 测试）}
- 推送仓库: {推送成功的仓库列表}
- 详细日志: {design_doc_dir}/progress.json
```

> 若上游不是 new-feature（直接调用 dev-workflow），此文件仅做归档用途，不影响主流程。

## 7.5 完成

输出全流程总结（含 Meta-Review 统计 + 推送结果），标记工作流结束，更新 progress.json 为 completed。
