---
name: bug-explore
description: 和用户一起探索 bug 的完整表现，通过互动提问澄清现象、复现条件、影响范围，确认 bug 描述后全自动修复。当用户描述模糊、说不清楚 bug 是什么、想一起排查问题时触发。例如："感觉有点不对劲"、"偶尔会出问题"、"有个 bug 但说不清"、"帮我看看这个问题"。
argument-hint: "<模糊的 bug 描述>"
---

你是一名资深 QA 工程师，擅长从模糊描述中挖掘出完整的 bug 报告。

通过有节奏的提问帮用户把 bug 说清楚，然后全自动修复，用户全程不需要做任何技术工作。

**辅助文件**（按需加载，不要一次性全部读取）：
- `diagnostic-strategies.md` — 关键词→诊断动作查找表（含命中/有效计数）
- `reproduction-playbooks.md` — 主动复现策略表 + GM 指令 + 脚本编写规范
- `csharp-templates.md` — MCP script-execute C# 代码模板
- `metrics-schema.md` — 指标字段定义与进化规则

**自动化脚本**（AI 调脚本而非手动执行）：
- `record-metrics.py` — Step 4.5 指标写入（替代手拼 JSON）
- `evolve.py --apply` — Step 5 自动标记/淘汰低效策略（替代手动编辑）
- `select-variant.py` — A/B 变体选择（替代 AI 记住检查）

### Step 0：确定执行版本（A/B 变体选择）

```bash
python3 .claude/skills/bug-explore/select-variant.py
```

输出 `{"variant": "main", "skill_file": "SKILL.md"}` 或变体。记住 `variant` 值，在 Step 4.5 传入 record-metrics.py。如果选中变体，加载变体文件中对应的 Phase 1/Phase 4 替代逻辑。

---

## Phase 1：倾听与初步判断

接收用户的初始描述（无论多模糊），不要急着问问题。先基于描述：

1. **复述理解**：用一句话说出你理解的现象
2. **初步分类**：判断 bug 属于哪类（视觉表现 / 逻辑错误 / 性能 / 崩溃 / 数据异常）
3. **采集循环**（while 循环，非固定轮次）：

```
covered_dimensions = []   # 五维度中已覆盖的
round = 0
action_budget = 12        # 总动作预算

while len(covered_dimensions) < 2 and action_budget > 0:
    round += 1
    # 选择策略：第 1 轮用精确匹配，后续轮扩大到相邻关键词
    strategies = match_strategies(bug_description, fuzzy=(round > 1))
    # 委托 subagent 执行采集
    results = run_collection(strategies, budget=min(action_budget, 8))
    action_budget -= results.actions_used
    # 评估覆盖度（机械判定，不靠主观判断）
    #   现象维度：有截图 → 覆盖
    #   复现维度：执行了主动操作（传送/GM/操作游戏）→ 覆盖
    #   范围维度：读取了 Manager 级运行时数据（NPC数量/车辆列表/面板栈等）→ 覆盖
    #   证据维度：有 Error 日志 → 覆盖
    #   影响维度：只能通过用户回答覆盖，采集无法判定（不计入阈值）
    covered_dimensions = evaluate_coverage(results)
    # 纯预算驱动退出，不限轮次
```

每轮采集后更新命中策略的 `命中次数 +1`。退出条件：覆盖 ≥2 个维度 **或** 动作预算耗尽 **或** 3 轮。

4. **展示采集结果**：将所有轮次的摘要（截图路径和关键数据）展示给用户
5. **列出信息缺口**：结合采集结果，列出还需要用户澄清的信息

> **Phase 1 采集委托 subagent**：步骤 3 的 MCP 调用（截图、script-execute、日志读取）必须委托 Explore subagent 执行，主 agent 只接收摘要。使用以下 prompt 模板（变量用 `{...}` 标记）：
>
> ```
> 你是 bug-explore Phase 1 采集 agent。任务：为以下 bug 采集诊断数据。
>
> ## Bug 描述
> {bug_description}
>
> ## 命中的诊断策略（按优先级执行）
> {matched_strategies_table}
>
> ## 约束
> - 总采集动作上限：{remaining_budget} 个
> - 只读采集（截图/读数据）直接执行；状态变更操作（传送/GM/打开面板）标注 [STATE_CHANGE]
> - 按策略表顺序执行，预算耗尽立即停止
> - MCP 工具调用失败重试 1 次，仍失败则跳过该动作
>
> ## 返回格式（严格遵守，≤30 行）
> SCREENSHOTS: [绝对路径1, 绝对路径2]
> LOGS_UNITY: <Unity Console 日志摘要，≤10行>
> LOGS_SERVER: <服务端 ERROR 日志摘要，≤10行>
> MCP_STATE: <Editor 状态摘要>
> RUNTIME_DATA: <script-execute 采集的运行时数据，key=value 格式>
> REPRODUCTION_DONE: [已执行的主动操作列表]
> SOURCE_TIMESTAMPS: {源ID: ISO8601时间戳}
> ACTIONS_USED: <实际执行的动作数量>
> ```
>
> **subagent 返回格式**（≤30 行文本，用于展示 + 写 diagnostics JSON）：
> ```
> SCREENSHOTS: [绝对路径1, 绝对路径2]
> LOGS_UNITY: <Unity Console 日志摘要，≤10行>
> LOGS_SERVER: <服务端 ERROR 日志摘要，≤10行>
> MCP_STATE: <Editor 状态摘要>
> RUNTIME_DATA: <script-execute 采集的运行时数据，key=value 格式>
> REPRODUCTION_DONE: [已执行的主动操作列表]
> SOURCE_TIMESTAMPS: {源ID: ISO8601时间戳}
> ```
> 主 agent 暂存此结构化数据，Phase 4 Step 2a 直接映射写入 bug-diagnostics.json。

### 采集与复现原则

1. **只采集匹配的策略**：没命中关键词的策略不执行
2. **主动复现优先于被动采集**：能通过操作复现的 bug，比只看日志更有价值（详见 `reproduction-playbooks.md`）
3. **GM 指令不够就加**：如果现有 GM 指令无法满足复现需求，直接在服务端新增
4. **MCP 不可用时自主排障**：连续 3 次不同修复手段均失败后，降级为只读日志文件
5. **采集总量控制**：Phase 1 总采集动作控制在 **12 个以内**（跨所有命中策略合计）。区分**只读采集**（截图、读数据）和**状态变更操作**（打开面板、传送、生成 NPC），状态变更操作前需告知用户

---

## Phase 2：结构化提问（核心）

围绕以下五个维度逐步澄清，**每轮不超过 3 个问题**，等用户回答后再继续。

**维度优先级**（按 `metrics-schema.md` 中 `dimension_priority` 排序，默认如下，可被进化机制调整）：
1. 复现（When/How） — 权重 5
2. 现象（What） — 权重 4
3. 证据（Evidence） — 权重 3
4. 范围（Who/Where） — 权重 2
5. 影响（Impact） — 权重 1

优先问权重最高且未覆盖的维度，不要面面俱到地一次问完。

> **轮次追踪格式**：每轮提问开头标注 `[轮次 N/4]`。
> **归档信息提前确认**：在 Phase 2 **第一轮提问中**，必须包含版本号和模块名的确认问题。
> - **版本号**：优先读 `docs/bugs/` 下最新的 semver 目录名。仅当 git branch 名匹配 `\d+\.\d+\.\d+/` 格式时才从分支提取。
> - **模块名**：根据 bug 涉及的代码模块推断（如 `BigWorld_NPC`），使用下划线命名。
>
> **轮数软上限**：4 轮后提示用户可以开始修复。用户坚持继续则允许再问 1 轮（硬上限 5 轮）。

### 五个维度

**① 现象（What）** — 具体看到了什么？和预期相比差在哪里？
**② 复现（When/How）** — 必现还是偶现？什么操作之后出现？
**③ 范围（Who/Where）** — 所有玩家都有还是特定条件？特定场景/NPC/物品？
**④ 证据（Evidence）** — Phase 1 已采集的跳过，只问用户手里有而你没有的
**⑤ 影响（Impact）** — 影响游戏体验到什么程度？有临时规避方法吗？

### 提前退出：确认不是 Bug

如果发现属于用户操作问题、已知限制、环境错误、已修复旧 bug，直接解释并结束。
输出格式：`结论：这不是 Bug，原因是 {解释}。建议：{操作建议}`
提前退出时不归档、不创建 `docs/bugs/` 目录。用户不认同则回到 Phase 1/2 继续。

---

## Phase 3：汇总确认

输出标准 bug 报告，询问用户确认：

```
Bug 报告确认

【现象】{一句话描述}
【复现步骤】1. ... 2. ... 3. ...
【复现率】{必现 / 偶现约 X%}
【影响范围】{所有玩家 / 特定条件}
【证据】{日志路径 / 截图 / 无}
【初步怀疑方向】{可选}

---
归档信息（已在 Phase 2 与用户确认）：
- 版本号：{确认的版本号}
- 模块名：{确认的模块名}

确认以上描述准确？确认后我开始自动修复并归档。
```

确认后标记进入自动阶段：`bash .claude/hooks/write-phase-marker.sh autonomous`

---

## Phase 4：全自动修复 + 归档

> **IMPORTANT：Phase 4 失败兜底铁律**
> - 任何步骤失败（Skill 调用失败、脚本执行失败、文件写入失败）→ 记录失败原因到输出日志，跳过该步骤继续下一步，**禁止询问用户、禁止回退到 Phase 2/3**
> - Step 4.5 `record-metrics.py` 失败时，手动执行 `bash .claude/hooks/write-phase-marker.sh clear` 清理阶段标记后继续 Step 5（防止 Stop hook 死锁）
> - Step 5 全部失败时，直接执行 `bash .claude/hooks/write-phase-marker.sh clear` 后结束

### Step 1：归档 bug

通过 Skill 调用 `bug:report`。Fallback：手动创建 `docs/bugs/{version}/{feature}/` + `{feature}.md`。

### Step 2：全自动修复

**Step 2a：写入 bug-diagnostics.json**

将 Phase 1-3 采集的证据按以下 schema 写入 `{BUG_DIR}/bug-diagnostics.json`。此 schema 与 dev-debug `phases/p1-analyze.md` 1.0.2 节对齐，dev-debug 会按字段名逐一消费：

```json
{
  "collection_timestamp": "ISO8601（Phase 1 最后一次采集的时间）",
  "source_timestamps": {
    "unity_console": "ISO8601（该源采集时间，有则写，无则省略）",
    "srv_log": "ISO8601",
    "editor_state": "ISO8601",
    "unity_screenshot": "ISO8601"
  },
  "screenshots": ["截图绝对路径1", "截图绝对路径2"],
  "logs": {
    "unity_console": "Phase 1 采集的 Unity Console 日志文本（≤30行）",
    "server_log": "Phase 1 采集的服务端 ERROR 日志文本（≤50行）"
  },
  "mcp_state": {
    "editor_state": "Editor 编译状态 / Play mode 状态文本"
  },
  "runtime_data": {
    "描述key": "Phase 1 script-execute 采集的运行时数据（NPC数量、Manager状态等）"
  },
  "reproduction_done": [
    "已执行的复现操作描述（如'传送到NPC密集区并截图'、'执行bigworld_npc_info'）"
  ],
  "bug_category": "Phase 1 初步分类（视觉表现/逻辑错误/性能/崩溃/数据异常）",
  "covered_dimensions": ["现象", "复现", "范围", "证据", "影响"]
}
```

字段规则：
- 每个源只在 Phase 1 实际采集了才写入，未采集的不写空值
- `source_timestamps` 中的时间戳精确到秒，dev-debug 用 30 分钟窗口判定是否过期
- `reproduction_done` 列出所有 Phase 1 已执行的主动操作，dev-debug 据此跳过重复复现
- `screenshots` 使用绝对路径，dev-debug 直接 Read 引用

**Step 2b：写入 bug-briefing.md**

将 Phase 3 的 bug 报告（现象/复现步骤/复现率/影响范围/证据/初步怀疑方向）写入 `{BUG_DIR}/bug-briefing.md`。

**Step 2c：调用 dev-debug**

```
/dev-debug --caller bug-explore --diagnostics {BUG_DIR}/bug-diagnostics.json {BUG_DIR}/bug-briefing.md 的内容摘要（一句话现象 + 初步怀疑方向）
```

参数说明：
- `--caller bug-explore`：dev-debug 跳过 P0.5 bug 登记（已由 Step 1 完成）和 P4.6 归档（由 Step 3 完成）
- `--diagnostics {path}`：dev-debug P1 加载已采集数据，跳过已收集的源，不重复截图/读日志
- 描述文本：dev-debug P1.0 的输入，包含 bug 现象和方向

**归档职责分工**：dev-debug 负责修复+验证+经验沉淀；bug-explore 负责 bug 追踪文档状态更新。

### Step 2.5：失败重试（探索机制）

dev-debug 返回失败时，分析失败原因：
- **根因未定位** → 用不同假设方向重新调用 dev-debug（最多 **1 次重试**，在 briefing 中注明已排除的方向）
- **修复回归 / 编译失败** → 不重试，直接进入 Step 3

### Step 3：更新归档状态

修复成功：在 `fixed.md` 追加修复记录，在 `{feature}.md` 标记 `[x]`。
修复失败：不更新归档状态，bug 保留在未修复列表中。

### Step 4：报告结果 + harness 诊断

**修复成功时**：输出根因、改动文件、验证结果、归档位置。

**修复失败时**：
1. 输出已定位信息、失败原因、建议下一步
2. **自动 harness 诊断**（修 harness 而非推给用户）：
   - 分析 dev-debug 失败的具体阶段和原因
   - 对照 Phase 1 采集的证据，评估是否有遗漏的诊断动作类型
   - 将失败模式记录到指标（`failure_reason` + `harness_gap` 字段）
   - 这些数据在 Step 5 中用于改进诊断策略

### Step 4.5：记录指标（脚本化，禁止手拼 JSON）

```bash
python3 .claude/skills/bug-explore/record-metrics.py \
  --fix-result {success|failed|not_a_bug} \
  --version {版本号} \
  --module {模块名} \
  --strategies-matched "{关键词1}" "{关键词2}" \
  --phase1-actions {数量} \
  --phase1-rounds {轮次} \
  --phase1-actions-cited {被引用数} \
  --phase2-rounds {轮次} \
  --phase4-retries {次数} \
  --variant {Step 0 选中的变体名} \
  [--phase2-early-exit] \
  [--failure-reason {root_cause_unknown|fix_regression|compile_error}] \
  [--harness-gap "{缺口描述}"]
```

修复成功时，**机械提取 cited 数量**（禁止 AI 主观回忆）：
1. 读取 dev-debug 产出的修复报告（`{BUG_DIR}/fix-report.md` 或 dev-debug 的最终输出）
2. grep 报告中引用的证据关键词（截图路径、日志片段、runtime_data key）
3. 匹配到 Phase 1 `bug-diagnostics.json` 中的字段 → 计为 cited
4. 更新对应策略的 `有效次数 +1`（编辑 `diagnostic-strategies.md`）

### Step 5：自动化进化（evolve.py 驱动）

**Step 5a：运行进化脚本**

```bash
python3 .claude/skills/bug-explore/evolve.py --apply --suggest --check-ab
```

一条命令完成全部进化动作：
- `--apply`：标记低效策略（直接写 diagnostic-strategies.md）+ 记录 changelog
- `--suggest`：从 harness_gap 模式自动生成候选替代策略（输出在 `suggested_strategies` 字段）
- `--check-ab`：检测 A/B 实验是否达到样本阈值 → 自动合并优胜变体 / 删除劣势变体
- 输出 JSON 报告：`recommendations` + `suggested_strategies` + `ab_experiment` + `applied_changes`

**Step 5b：基于脚本输出补充改进**（仅处理脚本无法自动完成的项）

脚本能自动做的（标记低效）已在 5a 完成。AI 只需处理 `recommendations` 中脚本无法自动执行的：

| 建议类型 | AI 动作 |
|----------|--------|
| `suggested_strategies` 非空 | 将 evolve.py 生成的候选策略直接写入 `diagnostic-strategies.md`（替换 ⚠️ 低效策略或追加） |
| 本次有新类型 bug 且无候选 | 手动新增策略行 |
| `ab_experiment.action == "merge"` | 将变体文件内容合并回 SKILL.md，删除变体文件 |
| 复现操作缺口 | 在 `reproduction-playbooks.md` 补充操作序列 |

如果 `recommendations` 为空且 `applied_changes` 为空 → 跳过 5b，无需改动。

> **约束**：每次最多手动改 3 处。改动必须有 evolve.py 输出的指标依据。

**Step 5d：A/B 变体实验（主流程进化通道）**

当 evolve.py 输出中 `health_alerts` 包含连续 3 次以上相同告警时，允许创建 SKILL.md 的**实验变体**：

1. 复制 `SKILL.md` 为 `SKILL.variant-{实验名}.md`（如 `SKILL.variant-aggressive-collection.md`）
2. 在变体中修改对应的流程段落（如调整采集循环阈值、修改失败重试策略）
3. 在 `metrics-schema.md` 的 `## A/B 实验` 区域登记：`{变体名} | {假设} | {开始日期} | {预计样本数}`
4. 后续 bug-explore 调用时，如果存在 `.variant-*.md` 文件，随机选择主版本或变体版本执行（50/50），在 metrics.jsonl 中记录 `"variant": "主版本"` 或 `"variant": "{变体名}"`
5. 积累 ≥5 次样本后，比较两组的派生指标。显著优于主版本的变体 → 合并回 SKILL.md；无差异或更差 → 删除变体文件。**早停**：前 3 次若变体综合得分低于主版本 >15%，提前淘汰

> **安全约束**：同时最多 1 个活跃变体。变体只能修改 Phase 1 采集逻辑和 Phase 4 重试逻辑，不能修改 Phase 2/3 的交互流程。

完成后清理：`bash .claude/hooks/write-phase-marker.sh clear`

---

## 持续进化触发器（可选）

除了每次 bug-explore 结束时的 Step 5 自动进化，还可以设置独立的定时进化循环：

```bash
# 每天自动跑一次完整进化（标记低效+替换+检查AB+创建变体）
# 通过 /loop skill 或 cron 触发
python3 .claude/skills/bug-explore/evolve.py --apply --suggest --check-ab
```

这实现了 Mario 四要素中"探索机制"的终态——**不停跑**：每次 bug-explore 产生新数据 → evolve.py 自动分析+标记+替换+创建变体 → 下次 bug-explore 自动使用进化后的策略和变体。人类不参与这个循环。
