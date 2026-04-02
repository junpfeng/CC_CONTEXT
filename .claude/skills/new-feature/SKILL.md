---
name: new-feature
description: 从一句话需求出发，完整开发一个新功能。AI 负责创建文档、与用户互动确认方案设计，方案锁定后全自动完成实现、测试、推送。当用户用自然语言描述想做什么功能时触发，例如"我想做XXX功能"、"新增一个XXX系统"、"做一个能XXX的功能"。
argument-hint: "<一句话需求描述>"
---

你是一名全栈游戏开发专家兼产品经理。负责将用户的一句话需求，通过互动确认方案，最终全自动完成开发全流程。

## 工作原则

- **方案阶段人工把关**：通过提问与用户互动，确保方案方向正确再开始实现
- **实现阶段全自动**：方案锁定后，用户不需要再介入
- **全程主动推进**：除方案确认外，不停下来询问用户

---

## Step 0：收集基础信息 & 断点恢复

从 `$ARGUMENTS` 中提取需求描述。

### 断点恢复检测

如果用户提供了版本号和功能目录名（或能从描述中推导出来），先检查 `{FEATURE_DIR}/idea.md` 是否已存在：

| idea.md 状态 | 恢复动作 |
|--------------|---------|
| 包含 `## 确认方案` 且内容非空 | 告知用户"检测到已确认的方案，直接进入实现"，执行 `echo "autonomous" > /tmp/.claude_phase`，跳到 **Step 4** |
| 存在但无 `## 确认方案` | 告知用户"检测到未完成的需求文档，从方案确认继续"，跳到 **Step 3** |
| 不存在但 `FEATURE_DIR` 目录已建立 | 告知用户"检测到已创建的功能目录，从上下文调研继续"，跳到 **Step 1** |
| 不存在且目录也不存在 | 正常走 Step 0 后续流程 |

**文档新鲜度检查**（断点恢复时额外执行）：
若 `{FEATURE_DIR}/acceptance-report.md` 存在，读取头部 `git_commits` 元数据，对比当前各 repo 的 HEAD（`git -C {repo} rev-parse --short HEAD`）：
- 完全匹配 → 报告有效，正常恢复
- 仅不相关 repo 有新 commit → 报告基本有效，提示可能有新变更
- 相关 repo 有新 commit → 报告过时，标注 `[STALE]`，Step 5 验收需完整重新执行（不复用旧报告）

### 收集基础信息

如果用户没有提供版本号和功能目录名，**自动推导默认值并请用户确认**：

1. **版本号**：读取 `docs/version/` 下最新的目录名作为当前版本
2. **功能目录名**：从需求描述中提取英文关键词，转为 snake_case

同时从 `$ARGUMENTS` 中检测用户是否指定了执行引擎（如"用 auto-work"、"走 dev-workflow"）。如果指定了，记录为 `USER_ENGINE_CHOICE`；如果没指定，留空，Step 4 再推荐。

```
需求已收到：{需求描述}

建议：
- 版本号：{自动推导的版本号}（当前最新）
- 功能目录名：{自动推导的目录名}

可以直接用，或告诉我你想改成什么。
```

用户确认或调整后，设定：
- `VERSION_ID` = 版本号
- `FEATURE_NAME` = 功能目录名
- `FEATURE_DIR` = `docs/version/{VERSION_ID}/{FEATURE_NAME}/`

---

## Step 1：建立项目上下文

并行读取以下内容，建立背景知识：

1. 查阅 `MEMORY.md` 中与本功能相关的历史经验和已知坑
2. 读取 `docs/README.md` 索引，定位与本功能领域相关的设计文档并阅读
3. 若 `docs/version/{VERSION_ID}/feature-metrics.jsonl` 存在，读取最近 5 条历史指标，作为引擎推荐和验收轮次预期参考
4. 搜索代码中最相似的已有实现，浏览其结构作为方案参考
   - **直接 grep/glob**：需求仅涉及单工程，或初始 grep 命中 ≤4 个目录
   - **委托 Explore subagent**：需求涉及 2 个工程，或初始 grep 命中 5+ 个目录
   - **并行多 Explore subagent**：需求涉及 3+ 子系统（如服务端 + 客户端 + 配置表 + 协议），启动最多 3 个 Explore subagent 并行，每个聚焦一个维度：
     1. 服务端已有实现（Manager/Handler/System 结构、数据存储模式）
     2. 客户端已有实现（Comp/Panel/Controller 结构、UI 交互模式）
     3. 协议 + 配置表（已有 Proto 消息模式、相关配置表结构）
     各 subagent 独立输出调研摘要，主 agent 合并去重后写入 idea.md `## 调研上下文`

**搜索策略**（按优先级依次尝试，命中即停；**跨端功能例外：即使服务端命中也继续搜索客户端和协议**）：
   1. 从需求关键词提取英文术语，grep 对应的 `*Manager` / `*Handler` / `*Comp` / `*System`
   2. 搜索同类协议消息名（如需求涉及"商店"，搜 `Shop*Req` / `Shop*Res`）
   3. 搜索相关配置表名（grep `RawTables/` 下的 xlsx 文件名）
   4. 搜索 `docs/` 下的设计文档标题（grep README.md 索引）
   5. 若以上均无命中，扩大搜索到功能域关键词（如"交易"扩展搜 `Trade`/`Exchange`/`Deal`）

> **跨端补充规则**：当需求涉及双端（协议/客户端+服务端），前 1-2 步命中了一端后不要停止，必须继续搜索另一端的对应实现（如服务端 `ShopHandler` 命中后，继续搜客户端 `ShopComp` / `ShopPanel` 和协议 `Shop*Req`），确保方案阶段掌握完整的双端调用链。

> 收集到的信息不单独写文件，在 Step 2 直接写入 `idea.md` 的 `## 调研上下文` 章节，作为下游引擎的**输入素材**。
> 注意：这是初步调研，不是最终方案。下游引擎（dev-workflow / auto-work）会在此基础上进行各自的需求分析和技术设计，二次强化方案深度。本阶段的目标是**减少重复的探索性搜索**，而非替代下游的设计环节。

上下文建立完成后进入 Step 2。

---

## Step 2：创建需求文档

将用户的需求整理为结构化的 `idea.md`，写入 `{FEATURE_DIR}/idea.md`。

**必需章节**（下游 auto-work/dev-workflow 依赖这些章节名，缺失会触发警告）：

```markdown
# {功能名称}

## 核心需求
{用户原始描述}

## 调研上下文
{Step 1 收集的信息：相关历史经验、设计文档要点、最相似的已有实现路径和结构概要}

## 范围边界
- 做：{明确包含的功能点}
- 不做：{明确排除的功能点}

## 初步理解
{你对需求的理解和拆解}

## 待确认事项
{你认为需要澄清的关键点}

## 确认方案
（Step 3 完成后追加，包含方案摘要全文）
```

> `## 调研上下文` 和 `## 确认方案` 是下游引擎的复用契约（已验证双方实现）：
> - dev-workflow P0（`p0-memory.md` L9）检测到 `## 调研上下文` 时跳过重复的记忆/文档**搜索**（1-2 步），但 P1 需求分析和 P2 技术设计仍正常执行——调研上下文是设计的输入，不替代设计本身
> - dev-workflow P1（`p1-requirements.md` L22）检测到 `## 确认方案` 时分类为 `direct`，跳过 1.3 调研，但仍会基于方案进行结构化需求分析和技术设计
> - dev-workflow P2（`p2-design.md`）检测到 `### 锁定决策` 时将其作为**硬约束**纳入设计，不得重新设计；仅对 `### 待细化` 做补充设计
> - auto-work（`auto-work-loop.sh` L669）检测到 `## 确认方案` 时分类为 `direct`，跳过分类和初步调研；Plan 迭代阶段将 `### 锁定决策` 作为不可变约束，仅细化 `### 待细化` 部分

创建完成后告知用户，进入 Step 3。

---

## Step 3：互动确认方案（核心步骤）

这是唯一需要用户深度参与的阶段。目标是通过提问确认所有关键技术决策，确保 plan.json 准确反映用户意图。

### 提问原则

- `[TEMPORARY]` 每轮不超过 **6 个问题**，等用户回答后再进行下一轮
- 优先问**影响架构的**决策，而非细节
- 每个问题给出 **1-2 个推荐选项**，降低用户思考负担
- 用户回答"随你"或"你决定"时，选择最符合项目既有风格的方案，记录决策理由
- 验收标准必须标注类型：`[mechanical]`（附可执行判定命令/断言）或 `[visual]`（附预期描述）。优先 mechanical，仅无法脚本化时用 visual

### 必问维度（按复杂度分级）

**最小必问集（所有功能必问）**：
- 功能边界：做什么、明确不做什么？
- 与哪些现有系统有交互？
- 验收标准：什么情况下算完成？

**跨端功能追加**（涉及协议/双端改动时）：
- 需要哪些新的客户端→服务端消息？
- 数据需要持久化（MongoDB）还是临时存储（Redis/内存）？

**复杂系统追加**（新系统/新玩法时）：
- 关键数值/阈值/限制是什么？
- 异常情况如何处理？
- 需要新界面还是复用现有界面？
- 是否需要运行时视觉验证（MCP 截图确认）？

### 方案摘要确认

所有关键问题澄清后，输出**方案摘要**（不超过一屏）：

```
方案摘要：{功能名称}

核心思路：{一句话}

{以下按涉及端列出，仅涉及单端时省略另一端}

### 锁定决策
（用户确认的技术决策，下游执行引擎不得重新设计，必须原样采纳）

服务端：
  - 新增消息：{列表}
  - 数据存储：{方案}
  - 核心逻辑：{要点}

客户端：
  - 界面变更：{要点}
  - 关键交互：{要点}

主要技术决策：
  - {决策1}：选择 {方案}，原因 {理由}
  - {决策2}：...

技术细节（尽可能详细）：
  - 数据结构：{关键结构体/表字段定义}
  - 接口签名：{核心方法签名}
  - 协议消息：{新增/修改的 Req/Res/Ntf 字段}
  - 状态流转：{状态机转换规则}
  - 配置表：{需要新增/修改的配置表和字段}
  （按实际涉及的维度填写，未涉及的省略）

范围边界：
  - 做：{明确包含}
  - 不做：{明确排除}

### 待细化
（概念已批准但实现细节留给执行引擎补充的部分）
  - {待细化项1}：{方向描述，具体实现由 P2/Plan 确定}
  - {待细化项2}：...
  （无待细化项时写"无"）

### 验收标准
  - [mechanical] {条件}：判定 `{具体命令/断言/数值比较}`
  - [mechanical] {条件}：判定 `{具体命令/断言/数值比较}`
  - [visual] {条件}：截图对照 `{预期描述}`（尽量转化为 script-execute 断言）

> 每条必须标注 `[mechanical]`（附可执行的判定命令或断言）或 `[visual]`（附预期描述）。
> 优先 mechanical——GM 命令返回值、配置表行数、grep 符号存在性、编译通过等均为 mechanical。
> 仅无法脚本化的表现类验证（动画流畅度、UI 布局美观度）使用 visual。

确认方向正确，可以开始实现？(是/需要调整)
```

用户确认后，将方案摘要**追加写入** `{FEATURE_DIR}/idea.md` 的 `## 确认方案` 章节（持久化供 dev-workflow 读取）。

**必须写入 `### 执行引擎` 字段**（防止 Step 4 因缺少引擎指定而触发交互）：
- 如果用户在 Step 0 指定了 `USER_ENGINE_CHOICE`，写入该值
- 如果用户在 Step 3 方案确认过程中提到了引擎偏好，写入该值
- 否则，按 Step 4 的多维度判定矩阵自动推断引擎并写入（告知用户推断结果和理由，用户可在确认方案时一并调整）

然后标记进入自动阶段并进入 Step 4：

```bash
echo "autonomous" > /tmp/.claude_phase
```

用户提出调整时，修改摘要后再次确认，直到通过。

> **轮数上限**：
> - `[TEMPORARY]` **软上限（5 轮）**：提示用户"建议先锁定当前方向，细节可以在实现中迭代调整"
> - `[TEMPORARY]` **硬上限（8 轮）**：强制输出当前方案摘要，未收敛的决策点标注到 `### 待细化`，进入 Step 4。避免方案阶段无限循环

### 方案深度原则

**人工参与阶段（Step 1-3）尽可能深入细节**。用户在场时是最佳的细节确认窗口——能定到接口级就定到接口级，能定到字段级就定到字段级。方案摘要应包含：功能边界、核心思路、关键决策、验收标准，以及尽可能多的技术细节（数据结构、接口签名、协议消息字段、状态机转换、配置表字段等）。

**方案深度自检**（输出方案摘要前执行，未定义的项标注到 `### 待细化`）：

| 检查项 | 判定 |
|--------|------|
| 关键数据结构是否有字段定义（字段名+类型）？ | YES → 写入锁定决策 / NO → 标注待细化 |
| 核心接口是否有方法签名（参数+返回值）？ | YES → 写入锁定决策 / NO → 标注待细化 |
| 新增协议消息是否有字段列表？ | YES → 写入锁定决策 / NO → 标注待细化 |
| 配置表变更是否有字段名+类型+用途？ | YES → 写入锁定决策 / NO → 标注待细化 |
| 状态机/流程是否有转换条件？ | YES → 写入锁定决策 / NO → 标注待细化 |

下游引擎（dev-workflow P2 / auto-work Plan 迭代）在 `## 确认方案` 的基础上做**补充强化**，属于锦上添花：

| 层次 | 负责方 | 职责 |
|------|--------|------|
| 锁定决策 | new-feature + 用户（Step 1-3） | 用户确认的技术决策（`### 锁定决策`），执行引擎**不得重新设计**，必须原样采纳为硬约束 |
| 待细化补充 | dev-workflow P2 / auto-work Plan | 基于代码分析补充 `### 待细化` 中的实现细节、调用链、边界处理、遗漏的依赖关系 |

> **锁定决策合规验证**：`feature:plan-review` 必须在审查 plan.json 时，提取 idea.md `### 锁定决策` 中的关键词（函数名、消息名、存储方案、数据结构），逐条验证 plan.json 不与之矛盾。任何偏离必须标记为 CRITICAL 并阻止 plan 通过。这是机械验证，不依赖 LLM 自觉遵守。

---

## Step 3.5：技术可行性快检（自动，≤2 分钟）

方案确认后、引擎启动前，自动验证 `### 锁定决策` 中的**可检查技术假设**。目标：在引擎的 token 成本投入前，用轻量检查拦截无效方案。

### 触发条件

从锁定决策文本中扫描以下模式。**无命中则跳过本步骤，直接进入 Step 4**：

| 假设类型 | 识别模式（从锁定决策文本提取） | 检查方法 |
|---------|---------------------------|---------|
| 接口/函数存在 | 具体函数名或方法签名（如 `PlayerManager.GetPlayer()`） | `grep -rn "{函数名}" {工程目录}` |
| 依赖包/模块存在 | 第三方包名或内部模块路径 | 检查 `go.mod` / `.csproj` |
| 配置表字段存在 | 具体表名+字段名 | Excel MCP `excel_read_sheet` 或 grep 配置加载代码 |
| Proto 消息存在 | 具体 proto 消息名 | `grep -rn "{消息名}" old_proto/` |
| 文件/目录存在 | 具体路径 | `ls -d {路径}` |

### 执行

1. **提取假设列表**：从 `### 锁定决策` 中逐条扫描上述模式，生成 `assumptions[]`（每条含 type + target + source_line）
2. **并行验证**：对每条假设执行对应的检查方法（全部为只读操作，零副作用）
3. **结果判定**：

| 结果 | 动作 |
|------|------|
| 全部 PASS | 输出 `✓ 快检通过（{N} 项假设已验证）`，进入 Step 4 |
| 有 WARN（依赖缺失但可自动安装、字段不存在但可新增） | 输出警告列表，在 `### 锁定决策` 末尾追加 `> ⚠️ 快检发现：{列表}`，进入 Step 4 |
| 有 BLOCK（核心接口不存在且非本功能新增范围） | 进入下方 **BLOCK 分级处理**（部分可自动解决，仅无法自动解决的才暂停报告） |

**BLOCK 判定标准**（需同时满足）：
1. 假设在 `### 锁定决策` 中（非 `### 待细化`）
2. 假设的目标不存在且不属于本次功能新增范围（如假设使用一个并非本功能创建的接口）

### BLOCK 分级处理

发现 BLOCK 项时，按缺失物规模分级处理：

| 规模 | 判断标准 | 处理 |
|------|----------|------|
| 简单缺失 | 单函数/枚举/配置值，≤50 行 | 纳入 plan file_list 标注新建，不阻塞 |
| 独立系统 | >300 行 或 3+ 文件 或 有自身依赖链 | **只做发现和预注册**：写 `ddrp-req-*.md` + 在 `ddrp-registry.json` 注册 `status: pending`。**不在此处 spawn**，统一由 Step 4 DDRP 外循环执行 spawn，避免两处 spawn 逻辑不一致 |
| 仍有 BLOCK | 非上述两类，且无法自动解决 | **顶层 feature**：向用户报告，回 Step 3 调整；**子 feature**（`## 确认方案` 预填）：记录后继续，降级执行 |

> 上述三种 BLOCK 处理完成后（简单缺失已纳入 plan、独立系统已预注册、仍有 BLOCK 已报告/降级），均写入产出文件后进入 Step 4。Step 4 DDRP 循环首轮会检测到 `pending` 状态的预注册条目并执行 spawn。

### 产出

写入 `{FEATURE_DIR}/feasibility-check.md`。下游引擎启动时应检查此文件是否存在：若存在且全部 PASS/WARN，可跳过对 `### 锁定决策` 中已验证假设的重复检查（dev-workflow P2 和 auto-work Plan 迭代阶段）。

> **时间预算**：120s 上限。超时的检查项标记为 `UNKNOWN`，不阻塞流程。

---

## Step 3.7：方案红蓝对抗（自动，≤10 分钟）

开发前对方案进行对抗性验证，拦截设计缺陷（逻辑矛盾、边界遗漏、安全漏洞），避免开发完成后高成本返工。

> **设计依据**：Mario 自动化六步法第 4 步——"先不开发，基于方案做测试。红队每轮必须找出新 BUG，蓝队修复。结束目标：连续 N 轮 0 BUG"。案例实证：18 轮红蓝对抗发现 62 个设计缺陷，309 个断言。

### 触发条件

- `### 锁定决策` 中包含 **≥3 条**决策项 → 执行
- <3 条（简单功能）→ 跳过，直接进入 Step 4

### 执行

`[TEMPORARY]` **轮次结构**：红队攻击 → 蓝队修复 → 红队复审，动态轮次（最多 10 轮）。

**红队（Attacker subagent）**：

```
读取 {FEATURE_DIR}/idea.md 的 ## 确认方案。你是红队，逐条审查锁定决策，从以下维度攻击：
1. 逻辑矛盾（A 决策与 B 决策冲突、状态机死锁）
2. 边界遗漏（未定义的状态转换、溢出、空值、零值）
3. 并发/时序（双端消息乱序、重入、竞态）
4. 安全（输入未校验、权限绕过、注入）
5. 性能（热路径分配、N+1 查询、GC 压力）
6. 跨端一致性（客户端/服务端对同一字段的理解是否一致）

每条问题标注 severity: CRITICAL / HIGH / LOW。
输出格式：每条一行 `[severity] 维度: 问题描述`。
只报告真实问题，不凑数。0 个问题 = 方案质量高。
```

**蓝队（Defender，主进程执行）**：红队输出后，逐条处理：
- **CRITICAL/HIGH**：修改 `idea.md` 的 `### 锁定决策`（追加约束或修正矛盾），记录修改内容
- **LOW**：记录到 `### 待细化` 供引擎处理
- **误报**：标注驳回理由

**复审**：蓝队修复后，红队再审一轮（仅审查修改部分 + 修改可能引入的新问题）。

### 收敛

- `[TEMPORARY]` 连续 **3 轮** 0 个新 CRITICAL/HIGH → 通过，进入 Step 4（对齐 Mario 案例「连续 3 轮 0 fail」标准）
- `[TEMPORARY]` **10 轮**未收敛 → 将剩余 HIGH 移入 `### 待细化`，标注 `[adversarial-unresolved]`，进入 Step 4

### 产出

写入 `{FEATURE_DIR}/adversarial-review.md`：

```markdown
# 方案红蓝对抗报告

## 轮次记录
### Round 1
- 红队发现: {N} 条（{CRITICAL}C/{HIGH}H/{LOW}L）
- 蓝队修复: {列表}
### Round 2
- ...

## 最终状态
- 总发现: {N} 条
- 已修复: {M} 条（idea.md 已更新）
- 待细化: {K} 条（移入 ### 待细化）
- 驳回: {J} 条
```

> **时间预算**：10 分钟上限。超时按当前状态输出，未审查项标注 `TIMEOUT`，不阻塞流程。

---

## Step 4：全自动完成实现

方案确认后，确定执行引擎并启动实现。

### 引擎选择

**优先级**：idea.md `### 执行引擎` 字段 > 用户指定 > AI 推荐 + 用户确认。

1. **idea.md 已指定**：检查 `{FEATURE_DIR}/idea.md` 的 `## 确认方案` 章节中是否存在 `### 执行引擎` 字段。若存在且值非空（如 `auto-work`），直接使用该引擎，不询问用户。（子 feature 由父进程预填此字段，确保非交互执行）
2. **用户已指定**（Step 0 记录了 `USER_ENGINE_CHOICE`）：直接使用用户指定的引擎，不再询问。
3. **用户未指定且 idea.md 无 `### 执行引擎`**（理论上不应发生，Step 3 已强制写入）：按多维度判定矩阵自动决策，**直接使用推断结果，不询问用户**。输出推断理由供事后审查。

推荐依据：

| 引擎 | 推荐场景 | 核心优势 |
|------|----------|----------|
| `/dev-workflow`（默认推荐） | 涉及客户端视觉表现、需要 MCP 运行时验证、任务间有依赖 | MCP 全程可用、Unity 运行时验证、零冷启动、反馈环紧 |
| `/auto-work` | 纯服务端/纯逻辑、任务间无依赖、**客户端改动但不依赖多轮 MCP 调试**（基础 MCP 已自动覆盖） | 独立上下文零污染、Meta-Review 自学习 |

**多维度判定矩阵**（按优先级从高到低匹配，首条命中即决定）：

| 特征 | 推荐引擎 | 理由 |
|------|----------|------|
| 涉及动画/UI 交互/特效/相机——预期 MCP 截图→修复循环 >2 次 | dev-workflow | MCP 反馈环紧，迭代修复依赖运行时截图 |
| 纯服务端改动（仅 .go 文件） | auto-work | 无客户端依赖，CLI 并行效率高 |
| 协议变更 + 双端适配（逻辑为主，无视觉变化） | auto-work | 双端改动可并行，基础 MCP 验收覆盖编译 |
| 配置表改动 + 客户端读取（无视觉变化） | auto-work | 打表+编译验证即可，无需运行时调试 |
| 任务间有强依赖（后续 task 依赖前序 task 产出） | dev-workflow | 串行执行保证依赖顺序 |
| 以上均不明确 | dev-workflow | 默认选择，覆盖面更广 |

> **注意**：auto-work 对有 `.cs` 改动的功能会自动执行基础 MCP 验收（编译+登录+截图），即使 plan 中无 `[TC-XXX]`。但如果功能**强依赖多轮 MCP 调试迭代**（如动画、UI 交互），仍建议走 dev-workflow。
>
> **MCP 调试次数判定参考**：预期 MCP 截图→修复循环 ≤2 次（如配置驱动的 UI 文本变更、简单图标替换）→ auto-work 可覆盖；>2 次（如动画状态机调参、交互式 UI 布局、特效时序调整）→ dev-workflow。
>
> **规则生命周期标注**（每条问自己：模型强 10 倍，这条规则升值还是贬值？）：
> - `[PERMANENT]` 任务间有强依赖 → dev-workflow：串行保序是逻辑约束，不因模型变强而过时
> - `[PERMANENT]` 纯服务端 → auto-work：CLI 并行是工程优势，与模型能力无关
> - `[TEMPORARY]` MCP 截图→修复循环 >2 次 → dev-workflow：当前模型能力补偿。未来模型若能一次改对动画/UI，此规则应弱化
> - `[TEMPORARY]` MCP 调试次数阈值（≤2 次 vs >2 次）：基于当前经验，应随模型升级重新评估
> 标注为 `[TEMPORARY]` 的规则每季度审视，模型升级后优先验证是否仍需要。

推荐时的输出格式：
```
推荐使用 {引擎名}，原因：{一句话理由}
确认用这个引擎？或者你想用 {另一个引擎名}？
```

用户确认后启动。

### 创建 Feature 分支（引擎启动前）

为三个工程创建 feature 分支，保持良好的 git 历史：

```bash
# 记录原始分支名到文件（供 5.7 合并时使用，避免依赖不可靠的 reflog）
for repo in P1GoServer freelifeclient old_proto; do
  if [ ! -f "{FEATURE_DIR}/.original_branch_${repo}" ]; then
    git -C "$repo" rev-parse --abbrev-ref HEAD > "{FEATURE_DIR}/.original_branch_${repo}" 2>/dev/null || echo "main" > "{FEATURE_DIR}/.original_branch_${repo}"
  fi
  git -C "$repo" checkout -b "feature/${FEATURE_NAME}" 2>/dev/null || true
done
```

> 若分支已存在（断点恢复），`checkout -b` 会静默失败，不影响流程。原始分支名从文件读取而非 `HEAD@{1}`，防止 reflog 被 GC 或其他操作覆盖。

### 路径 A：dev-workflow

```bash
# [TEMPORARY] timeout 7200s 和 max-turns 200：基于当前模型速度，模型提速后应下调
timeout 7200 claude -p "/dev-workflow docs/version/${VERSION_ID}/${FEATURE_NAME}/idea.md" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 200
```

> **以子进程执行**（与 auto-work 一致），避免 P0-P7 输出累积到 new-feature 主进程。run_in_background 启动，DDRP 循环等待完成通知。

dev-workflow 会自动完成：
- P0 查询历史记忆 → P1 结构化需求（requirements.json）→ P2 技术设计+自审循环
- P3 任务拆分（wave 并行）→ P4 编码（subagent/CLI 并行）→ P5 编译+测试+MCP 验收
- P6 三维审查（代码+安全+测试）→ P7 经验沉淀+文档归档+自动推送

### 路径 B：auto-work

```bash
bash .claude/scripts/auto-work-loop.sh "{VERSION_ID}" "{FEATURE_NAME}"
```

auto-work 会自动完成：
- 阶段零 需求分类 → 阶段一 feature.json → 阶段二 Plan 迭代 → 阶段三 任务拆分
- 阶段四 波次并行开发（Keep/Discard + 质量棘轮 + Meta-Review）
- **阶段四-B MCP 验收**（有 `.cs` 改动时自动触发，见下方增强说明）
- 阶段五 模块文档 → 阶段六 三仓库推送

> 方案摘要已写入 `{FEATURE_DIR}/idea.md`，auto-work 阶段一会自动读取作为需求输入。

> **增强**：auto-work 阶段四-B 的触发条件从 `HAS_CLIENT_CHANGES && HAS_TEST_CASES` 放宽为 `HAS_CLIENT_CHANGES`。有 `.cs` 改动但 plan 中无 `[TC-XXX]` 时，自动生成并执行基础验收用例（编译检查 + 登录验证 + 主界面截图），确保客户端改动至少经过基本运行时验证。

### 告知用户

```
方案已锁定，使用 {dev-workflow/auto-work} 引擎。
进度可通过以下命令查看：
  dev-workflow: tail -f {FEATURE_DIR}/dashboard.txt
  auto-work:   tail -f docs/version/{VERSION_ID}/{FEATURE_NAME}/dashboard.txt
如果触发 DDRP 依赖解决，引擎可能多轮运行，最终完成后统一通知。
```

### 机械管道执行（Step 4 + Step 5 原子化）

选定引擎后，通过 `feature-pipeline.sh` 一次性执行 Step 4（引擎）+ Step 5（验收）+ 合并 + 清理。**这是一个不可打断的 bash 管道，LLM 无法在中间停下来询问用户。**

```bash
bash .claude/scripts/feature-pipeline.sh "{ENGINE}" "{VERSION_ID}" "{FEATURE_NAME}"
```

管道内部顺序执行：
1. `ddrp-outer-loop.sh`（引擎执行 + DDRP 依赖解决，5 轮上限）
2. `claude -p step5-acceptance-prompt.md`（独立验收进程，从文件重建上下文）
3. 条件 merge（三重守卫：报告存在 + 全 PASS + 无 BLOCKED）
4. worktree cleanup

> **硬性保证**：Step 4 引擎完成后，Step 5 验收**由 bash 机械触发**，不经过 LLM 决策。即使 LLM 用 `run_in_background` 调用 pipeline，内部四步仍然顺序执行。

日志输出到 `{FEATURE_DIR}/pipeline.log` 和 `{FEATURE_DIR}/ddrp-loop.log`。

**DDRP 分级规则**（developing 编码时遵循，详见 `.claude/rules/ddrp-protocol.md`）：

| 规模 | 判断标准 | 处理 |
|------|----------|------|
| 内联 | ≤50 行、单文件 | 当前 task 直接实现，记录 `[DDRP-INLINE]` |
| 子任务 | 50-300 行、1-3 文件 | 暂停→实现→编译→恢复，记录 `[DDRP-SUBTASK]` |
| 子系统 | >300 行 或 3+ 文件 | 写 `ddrp-req-{TASK_ID}.md`（status:open）后继续尝试 |

**关键机制**：
- **版本级注册表**：`docs/version/{VERSION}/ddrp-registry.json`，mkdir 原子锁防竞态
- **环路检测**：spawn 前遍历 `requested_by` 链，发现循环则标记 `circular-failed`
- **子 feature 跳过交互**：idea.md 预填 `## 确认方案`，直接进入 Step 4
- **Hook 强制**：Layer 2（Stop）和 Layer 3（push）拦截有 open ddrp-req 的交付/推送

### 非交互保障（hook 级硬拦截）

**机制**：`/tmp/.claude_phase` 或 `/tmp/.claude_phase_{FEATURE}` = `autonomous` 时，`block-obvious-asks.sh`（PreToolUse hook）以 exit 2 硬 block 一切 AskUserQuestion 调用。hook 扫描所有 `/tmp/.claude_phase*` 文件，任一为 autonomous 即拦截。

**阶段标记写入点**：
- feature-pipeline.sh 管道全程维护 per-feature marker（`/tmp/.claude_phase_{FEATURE}`）+ 全局兼容 marker
- ddrp-outer-loop.sh 读 `$PHASE_MARKER_PATH` 环境变量（pipeline 传入），fallback `/tmp/.claude_phase`
- feature-develop-loop.sh / feature-plan-loop.sh / feature/develop.md / dev-workflow / dev-debug / auto-work 写全局 marker

**被 hook 拦截后的降级行为**（各命令自行处理拦截反馈）：

| 交互点 | 降级行为 |
|--------|---------|
| Step 0 版本/目录确认 | 从 idea.md 路径推导 |
| Step 3 方案互动 | `## 确认方案` 已存在时跳过 |
| Step 4 引擎选择 | `### 执行引擎` 字段存在（Step 3 强制写入）→ 直接使用；缺失 → 按判定矩阵自动决策 |
| developing 参数解析 | 从最新版本目录搜索含 plan.json 的子目录 |
| developing 第二步 范围确认 | 从 plan file_list side 字段推断；无 side 时默认两端都做 |
| developing 第四步 优化建议 | `## 确认方案` 存在时不提建议 |
| develop-review 参数解析 | 从最新版本目录搜索含 develop-log.md 的子目录 |
| Step 5 BLOCKED-UNRESOLVABLE | 子 feature 记录后降级继续 |

### 引擎完成后

pipeline 自动进入 Step 5 验收（由 bash 机械触发，无需 LLM 记住继续）。

### 取消与中断

用户随时可以说"停止"或"取消"终止流程：
- **Step 0-3（方案阶段）**：直接停止，已创建的 `idea.md` 保留（下次可从断点继续）
- **Step 4（实现阶段）**：
  - **dev-workflow**：通过 `kill` 终止 `claude -p` 子进程；已完成的 Phase 保留在 `progress.json` 中，下次恢复时从断点继续
  - **auto-work**：通过 `kill` 命令终止 `auto-work-loop.sh` 进程（`kill $(cat {FEATURE_DIR}/auto-work.pid)`），已完成的 task 保留，未完成的回滚

### 失败处理

**失败恢复的上下文重建**（无论哪个引擎）：
- 重读 `{FEATURE_DIR}/idea.md`（含 `## 调研上下文` + `## 确认方案`）恢复需求、上下文和方案
- 不依赖会话记忆，完全从文件重建

**分级恢复策略**（先局部修复，避免整体回退）：

| 失败类型 | 恢复动作 | 是否回到 Step 3 |
|---------|---------|----------------|
| 编译错误、依赖缺失 | 直接修复后断点续跑 | 否 |
| 单个 task 失败 | 修改该 task 的 plan 后重试 | 否 |
| plan 不收敛 / 全部 task discard | 向用户报告**哪个技术决策导致失败**，局部调整方案 | 仅调整失败部分 |
| 根本性架构冲突 | 向用户报告根因，回到 Step 3 重新确认 | 是 |

**dev-workflow 失败时**：
1. 读取 `{FEATURE_DIR}/progress.json` 和 `dashboard.txt`，定位失败的 Phase/Task
2. 按上表分级恢复，优先断点续跑

**auto-work 失败时**：
1. 检查 `{FEATURE_DIR}/results.tsv` 和 `auto-work-log.md`，定位失败的阶段/任务
2. auto-work 有内置 Keep/Discard 机制，大多数任务级失败会自动回滚并继续
3. 按上表分级恢复，仅根本性架构问题才回到 Step 3

---

## Step 5：验收确认

引擎执行完成后，new-feature 自身对照方案阶段定义的验收标准逐条验证。**无论走哪个引擎，此步骤都执行。**

### 5.0-pre 引擎验收去重守卫

在执行任何验收逻辑前，先检查 `{FEATURE_DIR}/acceptance-report.md` 是否已存在（引擎内置验收可能已生成）：

| 状态 | 动作 |
|------|------|
| 文件存在且所有 AC 项均为 PASS | 输出报告摘要，**跳过 5.1-5.4**，直接进入 5.5（复用引擎报告） |
| 文件存在但有 FAIL/UNRESOLVED 项 | 仅对 FAIL/UNRESOLVED 项执行 5.1-5.4，PASS 项标记 `PASS(inherited)` |
| 文件不存在 | 正常执行完整 5.0-5.4 流程 |

> **背景**：auto-work 阶段四-B 已内置 `acceptance-loop.sh` 验收循环。不做去重会导致同一功能被验收两次，浪费 token 且可能重复登记已修复的 bug。

### 5.0 读取引擎执行概要

读取 `{FEATURE_DIR}/engine-result.md`（若存在），获取引擎类型、任务统计、编译/运行时验证状态等概要信息，作为后续验收的参考。

- 若文件不存在（旧引擎或手动执行），fallback 到直接读取引擎特定文件：dev-workflow 读 `progress.json`，auto-work 读 `results.tsv`
- engine-result.md 仅供快速概览，不替代 5.1-5.3 的逐条验收

### 5.1 提取验收清单

重新读取 `{FEATURE_DIR}/idea.md` 的 `## 确认方案` 章节，提取 `### 验收标准` 部分的每一条，编号为 `[AC-01]`、`[AC-02]`...

### 5.2 分类验证方法

对每条验收标准，按内容判定验证类型：

| 验证类型 | 判定条件 | 验证方式 |
|---------|---------|---------|
| 编译 | 所有功能默认包含 | Go: `make build`；Unity: `console-get-logs` 检查 CS 错误 |
| 代码存在性 | 涉及新增文件/接口/协议消息 | grep/glob 确认关键符号和文件存在 |
| 运行时 | 涉及客户端视觉/交互/UI/动画表现 | Unity MCP: Play → 登录 → 操作 → 截图 |
| 数据 | 涉及配置表/持久化 | 检查配置表行数、字段、bin/config 生成产物 |
| 协议一致性 | 涉及跨端通信 | 对比 Proto 定义与双端实现的消息字段 |

**验证执行优先级**（基于 Step 3 标注的验收类型）：
1. `[mechanical]` 类：直接执行判定命令/断言，比较输出与预期，PASS/FAIL 无歧义
2. `[visual]` 类：**必须先尝试 `script-execute` 读取 UI 组件属性/数值转化为机械断言**（如 `GameObject.Find("Panel").activeSelf == true`、`Text.text.Contains("xxx")`）。仅当 UI 组件确实无法程序化读取时（如动画流畅度、视觉美观度），才 fallback 到截图 + LLM 判定
   - `[TEMPORARY]` LLM 截图判定是补偿器，模型视觉能力提升后应逐步替换为精确断言

> **Step 3 方案阶段前置要求**：对每条 `[visual]` 验收标准，要求用户同时定义其**数值化等价物**（如"UI 正确显示"→"Panel_Shop.activeSelf==true 且 Text_Price.text 非空"）。无法数值化的标注 `[visual-only]`，仅此类才允许纯截图判定。

### 5.2.1 引擎感知的验证策略

读取 `engine-result.md` 中的引擎类型和验证状态，按以下矩阵决定每类验证的执行方式：

**dev-workflow 路径**：

| 验证类型 | P5 已覆盖？ | Step 5 动作 |
|---------|-----------|------------|
| 编译 | 是（`编译状态: PASS`） | **跳过**（仅当 engine-result.md 编译状态为 FAIL 时执行） |
| 代码存在性 | 否 | **执行** |
| 运行时 MCP | 是（`运行时验证: PASS`） | **仅验证 P5 遗留项**（读 `p5-residual-bugs.md`）；P5 已 PASS 的 TC 对应 AC 标记 `PASS(inherited)` |
| 数据 | 否 | **执行** |
| 协议一致性 | P6 审查覆盖（非机械验证） | **执行**（机械验证补充人工审查） |

> **快捷判断**：若 engine-result.md 显示 `编译状态: PASS` 且 `运行时验证: PASS`，Step 5 可跳过编译和大部分运行时验证，聚焦于代码存在性 + 数据 + 协议一致性 + P5 遗留项。

**auto-work 路径**：

| 验证类型 | auto-work 已覆盖？ | Step 5 动作 |
|---------|------------------|------------|
| 编译 | 是 | **跳过**（同 dev-workflow 逻辑） |
| 代码存在性 | 否 | **执行** |
| 运行时 MCP | 条件执行（可能 SKIPPED） | `SKIPPED` → **完整执行所有运行时类 AC 条目**；`PASS` → 同 dev-workflow 继承逻辑 |
| 数据 | 否 | **执行** |
| 协议一致性 | 部分 | **执行** |
| 单元测试 | **否**（auto-work 无测试阶段） | **新增**：Go 端 `make test`，涉及修改的包执行 `go test` |

> **关键差异**：auto-work 路径新增单元测试执行，这是 dev-workflow P5 已有但 auto-work 缺失的验证维度。

### 5.2.2 收敛控制

维护以下状态追踪验收-修复循环，**持久化到 `{FEATURE_DIR}/acceptance-state.json`**（防止 context 压缩或进程重启丢失）：
- `acceptance_round = 0`：当前验收轮次（初始 0，每完成一轮 5.3→5.4 循环 +1）
- `[TEMPORARY]` `max_acceptance_rounds = 5`：最大验收轮次
- `ac_fail_history`：每个 AC 项的连续 FAIL 次数记录
- `ac_total_fail_count`：每个 AC 项的**累计** FAIL 次数（PASS 后不归零）。用于检测振荡失败（PASS→FAIL→PASS→FAIL），累计 >= 3 时升级为 UNRESOLVED，即使连续计数未达阈值

**持久化格式**（每次 5.4.3 更新计数器后写入）：
```json
{
  "acceptance_round": 2,
  "max_acceptance_rounds": 5,
  "ac_fail_history": {"AC-01": 0, "AC-03": 2},
  "ac_total_fail_count": {"AC-01": 1, "AC-03": 3},
  "ac_fix_signatures": {
    "AC-03": [
      "round1: edit BigWorldNpcFsmComp.cs:L120-125, edit NpcMoveState.cs:L30-35",
      "round2: edit BigWorldNpcFsmComp.cs:L118-130"
    ]
  }
}
```
- `ac_fix_signatures`：每轮 dev-debug 修复后，提取被修改的文件名+行范围作为签名。用于 Context Rot 检测（见 5.4.3）
**恢复**：5.2.2 初始化时先检查 `acceptance-state.json` 是否存在，存在则从文件恢复状态而非从零开始。

### 5.3 执行验收（new-feature 主进程）

new-feature 自身逐条执行验证，每条记录 PASS / FAIL + 证据。**验收只做判定，不做修复。**

**编译验证**：
- Go 端 `make build`，Unity 端 `console-get-logs`
- 记录 PASS / FAIL

**代码存在性**：
- grep/glob 关键符号（函数名、消息类型、文件路径）
- 缺失 → 标记 FAIL，记录缺少什么

**运行时验证**（仅需要时执行）：
1. **前置健康检查**：
   - 服务器：检查游戏服务器进程是否运行（`powershell scripts/server.ps1 status`），未运行 → `powershell scripts/server.ps1 start` 启动并等待就绪
   - Unity Editor：`editor-application-get-state` 确认可用（不可用 → `scripts/unity-restart.ps1`）
   - 任一前置检查失败且自动恢复后仍失败 → 该 AC 条目标记 `BLOCKED`（非 FAIL），记录阻塞原因
2. 进入 Play 模式 → `/unity-login` 登录
3. 按验收条目描述执行操作（GM 命令 / UI 交互 / 触发条件）
4. `screenshot-game-view` 截图 + `console-get-logs` 抓日志
5. 对照预期判定 PASS / FAIL
6. 退出 Play 模式

验收完成后，若存在 FAIL 条目 → 进入 5.4；全部 PASS → 跳到 5.5。

### 5.4 失败修复：分级处理

**核心原则**：
- 轻量问题主进程内联修，复杂问题隔离修复，避免一刀切的进程开销
- COMPLEX 级失败仍进入 `docs/bugs/` 体系，与 bug-explore 共享同一套追踪结构

#### 5.4.0 FAIL 分级（主进程）

对每个 FAIL 条目，按以下规则判定修复级别：

| 级别 | 判定条件 | 示例 |
|------|---------|------|
| **TRIVIAL** | `[TEMPORARY]` 全部满足：① 验证类型为「代码存在性」或「数据」② 涉及 ≤3 个文件 ③ `ac_fail_history[AC-XX] == 0`（首次失败） | 缺少配置字段、函数名拼写、少注册消息处理 |
| **COMPLEX** | `[TEMPORARY]` 满足任一：① 验证类型为「编译」或「运行时」② 涉及 ≥4 个文件 ③ `ac_fail_history[AC-XX] >= 1`（已失败过） ④ 失败描述含「逻辑/状态/流程/时序」 | 编译错误、UI 异常、状态机流转、协议交互顺序 |

**TRIVIAL 内联修复**（主进程直接执行，不派生进程）：
1. 根据 5.3 记录的失败证据，直接 grep → Read → Edit 修复
2. 修复后立即重新验证该条目（执行 5.3 中对应的验证方法）
3. PASS → 移出 FAIL 列表，不登记 bug；仍 FAIL → 升级为 COMPLEX
4. **保护限制**：主进程最多读 200 行 + 改 3 个文件，超出阈值自动升级为 COMPLEX

> TRIVIAL 修复完成后，若仍有 COMPLEX 条目 → 进入 5.4.1；若 FAIL 列表已清空 → 跳到 5.5。

#### 5.4.1 登记 Bug（主进程，仅 COMPLEX 条目）

对每个 FAIL 条目，调用 `bug:report` 写入 `docs/bugs/{VERSION_ID}/{FEATURE_NAME}/`：

```
Skill: bug:report, args: "{VERSION_ID} {FEATURE_NAME} [AC-01] {验收标准描述}。现象：{失败现象}。预期：{预期行为}"
```

每条 FAIL 对应一个独立 bug 条目（编号由 bug:report 自动分配）。登记完成后记录映射关系：

| 验收条目 | Bug 编号 | Bug 路径 |
|---------|---------|---------|
| AC-01 | Bug #N | `docs/bugs/{VERSION_ID}/{FEATURE_NAME}/{FEATURE_NAME}.md` |
| AC-03 | Bug #M | 同上 |

同时将映射写入 `{FEATURE_DIR}/acceptance-bug-map.md` 供后续查询：

```markdown
# 验收失败 → Bug 映射

| AC 编号 | Bug # | 描述 | 状态 |
|---------|-------|------|------|
| AC-01 | {N} | {描述} | OPEN |
| AC-03 | {M} | {描述} | OPEN |

功能方案：{FEATURE_DIR}/idea.md
Bug 目录：docs/bugs/{VERSION_ID}/{FEATURE_NAME}/
```

**状态流转**：`OPEN` → `IN_PROGRESS`（dev-debug 启动时写入）→ `FIXED` / `UNFIXED`（dev-debug 完成时写入）。若 dev-debug 进程异常退出（非零退出码或超时 kill），主进程检测到 `IN_PROGRESS` 状态的条目视为 `UNFIXED`，避免状态停滞。

#### 5.4.2 启动 dev-debug 独立进程（每 Bug 一个进程，原子化修复）

**原子化原则**：每个 Bug 启动独立 `claude -p` 进程，单一变量（一个 Bug）+ 独立验证（修复后立即编译）= 可归因、可独立评估。避免一个进程修多个 Bug 导致交叉回归无法归因。

> **占位符替换**：以下模板中的 `{FEATURE_DIR}`、`{VERSION_ID}`、`{FEATURE_NAME}`、`{BUG_NUMBER}`、`{AC_ID}`、`{BUG_DESC}` 等占位符由 new-feature 主进程在构造 bash 命令时替换为实际值（LLM 文本替换），而非 bash 变量展开。使用 `<<'PROMPT'`（单引号 heredoc）确保内容不被 bash 二次解释。

**对 acceptance-bug-map.md 中每个 OPEN 条目，独立执行**：

```bash
claude -p "$(cat <<'PROMPT'
修复单个 Bug：{AC_ID} — {BUG_DESC}

上下文：
- 功能方案：{FEATURE_DIR}/idea.md（含 ## 确认方案）
- Bug 追踪：docs/bugs/{VERSION_ID}/{FEATURE_NAME}/{FEATURE_NAME}.md
- 开发日志：{FEATURE_DIR}/develop-log.md（如存在）

要求：
1. 将 {FEATURE_DIR}/acceptance-bug-map.md 中 {AC_ID} 条目状态更新为 IN_PROGRESS
2. 按 /dev-debug --mode acceptance --caller new-feature 流程自主诊断和修复（spec-vs-code 对比）
3. 修复后验证编译通过（Go: make build，Unity: console-get-logs）
4. 修复结果写入：
   - docs/bugs/{VERSION_ID}/{FEATURE_NAME}/{BUG_NUMBER}/fix-log.md
   - docs/bugs/{VERSION_ID}/{FEATURE_NAME}/{BUG_NUMBER}/images/
5. 修复成功：在 {FEATURE_NAME}.md 标记 [x]，更新 acceptance-bug-map.md 为 FIXED
6. 修复失败：保留 [ ]，在 fix-log.md 记录原因，更新 acceptance-bug-map.md 为 UNFIXED
PROMPT
)" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 30
```

`[TEMPORARY]` **并发策略**：COMPLEX Bug 串行执行（每个修完、编译验证后再启动下一个），避免并发修改导致冲突。未来模型若能可靠处理并发修复，可改为并行。

> **隔离保证**：
> - 每个 Bug 独立 `claude -p` 进程，单一修复目标，上下文窗口互不污染
> - 输入通过 `acceptance-bug-map.md` 的单条传递，输出写入 `docs/bugs/` 标准结构
> - 主进程在每个进程退出后**立即读取该条状态**并验证，而非等全部完成
> - 单 Bug 修复失败不影响其他 Bug 的修复流程（故障隔离）
> - dev-debug 的产出（fix-log、images、fixed.md）与 bug-explore 触发的修复格式完全一致

#### 5.4.3 重新验证与循环判定（主进程）

所有 COMPLEX Bug 的独立 dev-debug 进程依次执行完毕后：

1. 读取 `{FEATURE_DIR}/acceptance-bug-map.md`，获取每条的最终状态。**若有条目仍为 `IN_PROGRESS`**（进程异常退出未来得及写终态），将其标记为 `UNFIXED`
2. 对标记为 `FIXED` 的条目，**重新执行 5.3 中对应的验证方法**
3. 更新计数器：
   - `ac_fail_history`：PASS 归零，FAIL +1（连续计数）
   - `ac_total_fail_count`：FAIL +1（累计计数，PASS 不归零）
   - `ac_fix_signatures`：从 dev-debug 产出的 fix-log.md 中提取被修改的文件名+行范围，追加到对应 AC 条目的签名列表
4. `acceptance_round += 1`

**循环判定**：
- 全部 PASS → 跳到 5.5 输出报告
- 仍有 FAIL 且 `acceptance_round < max_acceptance_rounds`：
  - 若某 AC 项 `ac_fail_history[AC-XX] >= 3`（连续失败）**或** `ac_total_fail_count[AC-XX] >= 3`（累计失败，检测振荡） → 标记为 `[UNRESOLVED]`，追加标注 `⚠️ 验收标准疑似歧义或振荡（累计 FAIL {N} 次）`
  - **Context Rot 检测**：对比 `ac_fix_signatures[AC-XX]` 最近两轮的修复签名。若被修改的文件集合 ≥70% 重叠（同文件同区域反复修改）→ 标记为 `[UNRESOLVED-ROT]`，追加标注 `⚠️ 修复振荡：连续两轮修改相同位置，疑似 context rot 或根因未定位`，不再重试
  - 对仍为 FAIL 且未被标记 UNRESOLVED / UNRESOLVED-ROT 的条目，回到 5.4.1 重新登记 + spawn dev-debug
- 仍有 FAIL 且 `acceptance_round >= max_acceptance_rounds` → 将这些 FAIL 标记为 `[UNRESOLVED]`，跳到 5.5

### 5.5 验收报告

写入 `{FEATURE_DIR}/acceptance-report.md` 并在终端输出摘要：

```
---
generated: {ISO8601 timestamp}
engine: {dev-workflow / auto-work}
git_commits:
  P1GoServer: {short hash}
  freelifeclient: {short hash}
  old_proto: {short hash}
---

═══════════════════════════════════════════════
  验收报告：{功能名称}
  版本：{VERSION_ID}
  引擎：{dev-workflow / auto-work}
═══════════════════════════════════════════════

## 验收标准

[PASS] AC-01: {标准描述}
[PASS] AC-02: {标准描述} — 截图: {相对路径}
[FAIL] AC-03: {标准描述} → Bug #{N} (docs/bugs/{VERSION_ID}/{FEATURE_NAME}/{FEATURE_NAME}.md)
[UNRESOLVED] AC-05: {标准描述} → 5 轮修复未通过，Bug #{X}

## 实现概要

- 完成 task: {列表}
- Keep/Discard: {概要}（仅 auto-work 路径输出此行）
- 推送仓库: {列表}

## Bug 追踪（如有）

Bug 目录: docs/bugs/{VERSION_ID}/{FEATURE_NAME}/
- Bug #{N} [AC-03]: FIXED — 见 {N}/fix-log.md
- Bug #{M} [AC-05]: UNFIXED — 见 {M}/fix-log.md
- Bug #{X} [AC-05]: UNRESOLVED — 5 轮修复未收敛，见 {X}/fix-log.md

## 结论

通过率: X/Y
结论: [全部通过 / 部分通过，遗留 N 项 / 有 M 项 UNRESOLVED（阻塞推送）/ 有 K 项 BLOCKED（需排障）]
```

### 5.5.1 度量指标归档

验收报告生成后，追加结构化指标到 `docs/version/{VERSION_ID}/feature-metrics.jsonl`（每行一个 JSON，append 模式）：

```json
{"feature":"{FEATURE_NAME}","engine":"auto-work|dev-workflow","timestamp":"{ISO8601}","ac_total":5,"ac_pass":4,"ac_fail":0,"ac_unresolved":1,"ac_blocked":0,"acceptance_rounds":3,"ddrp_rounds":1,"adversarial_rounds":2,"adversarial_issues_found":8}
```

> **用途**：Step 1 上下文调研时，若 `feature-metrics.jsonl` 存在，读取最近 5 条作为引擎推荐和轮次预期参考。例如：历史数据显示 auto-work 路径在客户端功能上平均验收轮次 3.2，dev-workflow 为 1.8 → 优先推荐 dev-workflow。

### 5.6 BLOCKED 项处理（验收后、推送前）

> **BLOCKED ≠ 可跳过**。BLOCKED 意味着功能未经运行时验证，不允许直接 commit/push。

1. **有 BLOCKED 项** → 必须先尝试排障（与 dev-workflow P5 BLOCKED 处理一致）：
   - GM 命令生成测试实体
   - `script-execute` 直接初始化依赖对象
   - 修复依赖系统初始化逻辑
2. **排障成功** → 回到 5.3 重新执行被 BLOCKED 的 AC 条目
3. **排障失败**（≥3 种方案均不可行）→ 标记为 `[BLOCKED-UNRESOLVABLE]`，在验收报告中记录已尝试方案，**仍然阻止自动推送**，向用户报告阻塞原因
4. **全部 PASS + 无 BLOCKED** → 自动进入 commit/push

### 5.7 合并 Feature 分支

验收通过后，合并 feature 分支回原分支并删除：

```bash
# 从 Step 4 保存的文件中读取原始分支名（比 HEAD@{1} 可靠，不依赖 reflog）
for repo in P1GoServer freelifeclient old_proto; do
  ORIGINAL_BRANCH=$(cat "{FEATURE_DIR}/.original_branch_${repo}" 2>/dev/null || echo "main")
  git -C "$repo" checkout "$ORIGINAL_BRANCH" 2>/dev/null && \
  git -C "$repo" merge --no-ff "feature/${FEATURE_NAME}" -m "merge: ${FEATURE_NAME}" 2>/dev/null && \
  git -C "$repo" branch -d "feature/${FEATURE_NAME}" 2>/dev/null || true
done
```

> 若 feature 分支不存在（未创建或已合并），命令静默跳过。

```bash
rm -f /tmp/.claude_phase 2>/dev/null
```
