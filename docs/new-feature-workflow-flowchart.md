# /new-feature 工作流详细流程图

> 更新日期：2026-03-31

## 一、总览

```
用户一句话需求
    │
    ▼
Step 0  收集基础信息 + 断点恢复
    │
    ▼
Step 1  建立项目上下文（并行调研）
    │
    ▼
Step 2  创建 idea.md 需求文档
    │
    ▼
Step 3  互动确认方案 ⭐ 唯一人工深度参与
    │
    ▼
Step 3.5 技术可行性快检（自动，PASS/WARN/BLOCK）
    │
    ▼
Step 4  全自动实现 → 选择引擎
    ├── Path A: /dev-workflow（P0→P7，MCP 可用）
    └── Path B: /auto-work（6 阶段，CLI 隔离并行）
    │
    ▼
  结果报告
```

---

## 二、Step 0：收集基础信息 & 断点恢复

```mermaid
flowchart TD
    START(["用户：/new-feature '一句话需求'"]) --> PARSE["解析 $ARGUMENTS"]
    PARSE --> CHECK_ENGINE{"用户是否指定引擎?<br/>（如 '用 auto-work'）"}
    CHECK_ENGINE -->|"是"| RECORD["记录 USER_ENGINE_CHOICE"]
    CHECK_ENGINE -->|"否"| SKIP_ENGINE["留空，Step 4 再推荐"]

    RECORD & SKIP_ENGINE --> RESUME{"断点恢复检测<br/>检查 FEATURE_DIR + idea.md"}

    RESUME -->|"idea.md 有 ## 确认方案"| GO_S4["✅ 告知用户，跳到 Step 4"]
    RESUME -->|"idea.md 存在但无确认方案"| GO_S3["⚠️ 告知用户，跳到 Step 3"]
    RESUME -->|"目录存在但无 idea.md"| GO_S1["⚠️ 告知用户，跳到 Step 1"]
    RESUME -->|"全新需求"| INFER

    INFER["自动推导默认值：<br/>① 版本号 ← docs/version/ 最新目录<br/>② 功能名 ← 需求关键词 → snake_case"]
    INFER --> CONFIRM_INFO["请用户确认/调整"]
    CONFIRM_INFO --> SET["设定：<br/>VERSION_ID / FEATURE_NAME<br/>FEATURE_DIR = docs/version/{VER}/{NAME}/"]
    SET --> GO_S1_NORMAL["进入 Step 1"]
```

---

## 三、Step 1：建立项目上下文

```mermaid
flowchart TD
    S1_START["Step 1 开始"] --> PARALLEL

    subgraph PARALLEL["三路并行调研"]
        direction LR
        A["查阅 MEMORY.md<br/>历史经验 + 已知坑"]
        B["读 docs/README.md 索引<br/>定位相关设计文档并阅读"]
        C{"功能复杂度"}
        C -->|"简单"| C1["grep/glob 定位<br/>已有 Manager/Handler/Comp"]
        C -->|"跨端/复杂"| C2["委托 Explore subagent<br/>多轮搜索、跨工程调用链"]
    end

    PARALLEL --> COLLECT["汇总调研信息<br/>（不单独写文件，直接带入 Step 2）"]
    COLLECT --> S2["进入 Step 2"]

    style C2 fill:#fff3cd
```

> 注意：这是**初步调研**。下游引擎（dev-workflow P2 / auto-work Plan 迭代）会在此基础上做二次强化设计。

---

## 四、Step 2：创建需求文档

```mermaid
flowchart TD
    S2_START["Step 2 开始"] --> WRITE["写入 FEATURE_DIR/idea.md"]

    WRITE --> SCHEMA

    subgraph SCHEMA["idea.md 必需章节"]
        direction TB
        H1["## 核心需求<br/>用户原始描述"]
        H2["## 调研上下文<br/>Step 1 收集的全部信息<br/>（下游 dev-workflow P0 复用）"]
        H3["## 范围边界<br/>做什么 / 不做什么"]
        H4["## 初步理解<br/>AI 的理解和拆解"]
        H5["## 待确认事项<br/>需要澄清的关键点"]
        H6["## 确认方案<br/>（Step 3 完成后追加）"]
        H1 --> H2 --> H3 --> H4 --> H5 --> H6
    end

    SCHEMA --> S3["告知用户文档已创建，进入 Step 3"]
```

> 下游复用契约：
> - dev-workflow P0：检测到 `## 调研上下文` → 跳过重复搜索
> - dev-workflow P1：检测到 `## 确认方案` → 分类为 `direct`，跳过调研
> - auto-work：检测到 `## 确认方案` → 分类为 `direct`，跳过分类和初步调研

---

## 五、Step 3：互动确认方案（核心步骤）

```mermaid
flowchart TD
    S3_START["Step 3 开始"] --> DIM{"功能复杂度分级"}

    DIM -->|"所有功能"| Q_MIN["最小必问：<br/>• 功能边界（做/不做）<br/>• 与哪些现有系统交互<br/>• 验收标准"]
    DIM -->|"+ 跨端"| Q_NET["追加：<br/>• 需要哪些新协议消息<br/>• 持久化方案（Mongo/Redis/内存）"]
    DIM -->|"+ 复杂系统"| Q_COMPLEX["追加：<br/>• 关键数值/阈值/限制<br/>• 异常处理方案<br/>• 新界面 or 复用<br/>• 是否需 MCP 运行时验证"]

    Q_MIN & Q_NET & Q_COMPLEX --> ASK["输出 ≤6 个问题<br/>每个附 1-2 推荐选项"]
    ASK --> WAIT["等待用户回答"]
    WAIT --> CHECK{"关键问题已澄清?"}
    CHECK -->|"否，<5轮"| ASK
    CHECK -->|"≥5轮未收敛"| HINT["提示：建议先锁定方向<br/>细节可实现中迭代"]
    CHECK -->|"是"| SUMMARY
    HINT --> SUMMARY

    SUMMARY["输出方案摘要（不超过一屏）"]

    subgraph 摘要内容
        direction LR
        SA["核心思路"]
        SB["服务端：消息/存储/逻辑"]
        SC["客户端：界面/交互"]
        SD["技术决策 + 理由"]
        SE["技术细节：数据结构/接口签名<br/>协议字段/状态流转/配置表"]
        SF["范围边界"]
        SG["验收标准"]
    end

    SUMMARY --> CONFIRM{"用户确认?"}
    CONFIRM -->|"需要调整"| ADJUST["修改摘要"] --> CONFIRM
    CONFIRM -->|"确认 ✅"| PERSIST["追加写入 idea.md ## 确认方案<br/>方案锁定 🔒"]
    PERSIST --> S4["进入 Step 4"]

    style SUMMARY fill:#d4edda
```

### 方案深度原则

| 层次 | 负责方 | 职责 |
|------|--------|------|
| **主体设计** | new-feature + 用户（Step 1-3） | 尽可能深入的技术方案，含接口级细节 |
| **补充强化** | dev-workflow P2 / auto-work Plan | 基于代码分析补充调用链、边界处理、遗漏依赖 |

---

## 五点五、Step 3.5：技术可行性快检

```mermaid
flowchart TD
    S35_START["Step 3.5 开始"] --> SCAN{"扫描锁定方案<br/>是否含可验证假设?<br/>（函数存在/依赖/配置字段/<br/>proto消息/文件路径）"}

    SCAN -->|"无可验证假设"| SKIP["跳过本步骤<br/>直接进入 Step 4"]

    SCAN -->|"有假设"| CHECK["逐条验证：<br/>• grep/glob 确认函数/类存在<br/>• 检查依赖版本兼容<br/>• 确认配置字段/proto消息存在<br/>• 验证文件路径有效"]

    CHECK --> RESULT{"整体结果"}
    RESULT -->|"全部通过"| PASS["PASS ✅<br/>输出 feasibility-check.md<br/>→ 进入 Step 4"]
    RESULT -->|"部分假设存疑<br/>但不阻塞"| WARN["WARN ⚠️<br/>在 feasibility-check.md<br/>标注风险点<br/>→ 进入 Step 4（附注释）"]
    RESULT -->|"发现阻塞性冲突<br/>（API不存在/架构不兼容）"| BLOCK["BLOCK 🚫<br/>暂停，向用户说明冲突<br/>等待方案调整后重新确认"]

    BLOCK --> S3["返回 Step 3 修订方案"]

    style PASS fill:#d4edda
    style WARN fill:#fff3cd
    style BLOCK fill:#f8d7da
```

**输出文件**：`feasibility-check.md`（仅在有假设需验证时生成）

---

## 六、Step 4：引擎选择与启动

```mermaid
flowchart TD
    S4_START["Step 4 开始"] --> CHOICE{"USER_ENGINE_CHOICE 已设?"}

    CHOICE -->|"是"| USE_SPECIFIED["直接使用指定引擎"]
    CHOICE -->|"否"| RECOMMEND{"AI 评估方案特征"}

    RECOMMEND -->|"客户端视觉需反复 MCP 迭代<br/>任务间有依赖"| REC_DW["推荐 /dev-workflow"]
    RECOMMEND -->|"纯服务端/纯逻辑<br/>或客户端改动不需反复 MCP 调试<br/>任务间无依赖可真并行"| REC_AW["推荐 /auto-work"]

    REC_DW & REC_AW --> ASK_CONFIRM["输出推荐理由<br/>请用户确认"]
    ASK_CONFIRM --> USER_OK{"用户确认"}
    USER_OK --> USE_SPECIFIED

    USE_SPECIFIED --> ENGINE{"选择哪个?"}
    ENGINE -->|"/dev-workflow"| PATH_A["Path A<br/>调用 /dev-workflow FEATURE_DIR/idea.md"]
    ENGINE -->|"/auto-work"| PATH_B["Path B<br/>调用 auto-work-loop.sh"]

    PATH_A --> REPORT
    PATH_B --> REPORT
    REPORT(["输出结果报告：<br/>• 完成了哪些 task<br/>• Keep/Discard 情况<br/>• 已推送的仓库"])

    style PATH_A fill:#cce5ff
    style PATH_B fill:#fff3cd
```

---

## 七、Path A：/dev-workflow 全流程（P0→P7）

```
/dev-workflow {FEATURE_DIR}/idea.md
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  P0: 记忆查询                                               │
│  ─────────────                                               │
│  • idea.md 有 ## 调研上下文 → 直接复用，跳过搜索             │
│  • 否则：提取关键词 → 查 MEMORY.md + docs/ → 输出摘要       │
│  • 容错：搜索失败不阻塞                                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P1: 需求解析与验证                                          │
│  ──────────────────                                          │
│  1.1 读取 idea.md，Schema 检查（核心需求/确认方案）          │
│  1.2 需求分类：                                              │
│      • 有 ## 确认方案 → direct（跳过调研）                   │
│      • 全新系统/需选型 → research                             │
│  1.3 多轮调研（仅 research）：                                │
│      调研(subagent) ⇄ 审查，≤6轮，连续2轮无问题 → 早退       │
│  1.4 工程定位 + 依赖检查                                     │
│  1.5 输出 requirements.json（REQ-XXX + acceptance_criteria） │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P2: 技术设计（subagent 执行 + 自审循环）                    │
│  ─────────────────────────────────────────                    │
│  2.0 读取 requirements.json                                  │
│  2.1 架构设计：系统边界 / 接口 / 状态机 / 错误码             │
│  2.2 详细设计：按工程分（业务/协议/配置/DB）                  │
│  2.3 事务性设计：事务范围 / 回滚 / 幂等 / 并发控制            │
│  2.4 接口契约：跨工程消息格式 / 版本兼容 / 错误码映射         │
│  2.5 验收测试方案（涉客户端时）：                             │
│      [TC-XXX] 用例 = 真人操作序列 + MCP 验证手段              │
│  → 自审循环（有问题返回修改）→ 通过后冻结设计文档             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P3: 任务拆解                                                │
│  ────────────                                                │
│  • 单一职责 + 工程隔离 + 依赖明确 + 可验证                   │
│  • 拓扑排序 → Wave 分组：                                    │
│    wave 0: 无依赖（Proto/配置）                               │
│    wave 1: 依赖 wave 0（Server + Client 可并行）              │
│    wave 2: 依赖 wave 1（集成/测试）                           │
│  • 同 Wave 内检查无文件交集                                   │
│  • 输出：Wave 汇总表 + 依赖图(Mermaid) + 任务清单             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P4: 并行实现                                                │
│  ════════════                                                │
│                                                               │
│  for each Wave:                                               │
│    ① 保存 Git 检查点（wave 级 + task 级）                    │
│    ② 执行模式选择：                                          │
│       • 1 个 task → 主 agent 直接执行                         │
│       • 2-3 个 → subagent 并行（dev-workflow-implementer）   │
│       • 4+ 个 → CLI 进程并行（claude -p，独立上下文）        │
│         可选：worktree 隔离（≥2 不重叠任务跨不同工程时）     │
│    ③ 收集结果（文件列表 + 编译结果，不读代码）                │
│    ④ 超时（600s）→ Discard                                   │
│    ⑤ 记录 results.tsv                                        │
│    ⑥ Meta-Review（条件触发：≥2 task 完成且有 discard）       │
│    ⑦ Post-wave 编译验证（fail-fast）                         │
│                                                               │
│  Keep/Discard 机制：                                          │
│    编译失败3次 → Discard（回滚到 task 检查点）                │
│    同 wave 文件重叠 → 退化为 wave 级回滚                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P5: 构建与测试                                              │
│  ──────────────                                              │
│  • P4 已编译通过 → 跳过编译，直接测试                         │
│  • 测试链：单元测试 → 集成测试 → 回归测试                     │
│  • Unity MCP 验收测试（涉客户端 + 设计文档含 [TC-XXX]）：    │
│    1. 确认 Unity Editor 状态（MCP 不通 → 自动重启）          │
│    2. 进入 Play 模式 + 登录游戏                               │
│    3. 逐用例执行操作 + 截图/日志验证                          │
│    4. 失败 → 分析根因 → 退出 Play → 回 P4 修复 → 重测       │
│       （最多 3 轮，仍有失败 → 标注遗留，继续 P6）            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P6: 产出审查（3+1 Agent）                                   │
│  ═════════════════════════                                    │
│                                                               │
│  第一步：3 Agent 并行审查                                     │
│    ┌────────────────┐ ┌──────────────┐ ┌────────────────┐   │
│    │ Code Reviewer   │ │ Security     │ │ Test Designer  │   │
│    │ 质量+规范+事务  │ │ 注入/凭证/   │ │ 测试覆盖充分性 │   │
│    │                │ │ 越权         │ │                │   │
│    └───────┬────────┘ └──────┬───────┘ └───────┬────────┘   │
│            └─────────────────┼─────────────────┘             │
│                              ▼                                │
│  第二步：综合审查                                             │
│    功能完整性 + 协议/配置/DB 一致性 + 跨工程集成              │
│                              │                                │
│  审查循环（质量棘轮，最多 10 轮）：                            │
│    有问题 → 保存 fix checkpoint → 逐项修复 → 重审            │
│    new_total < prev_total → 继续修复                          │
│    new_total >= prev_total → 回滚到 fix checkpoint            │
│    Critical=0 且 High≤2 → 通过 ✅                             │
│    达 10 轮仍有问题 → 标注遗留，继续 P7                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  P7: 经验沉淀                                                │
│  ────────────                                                │
│  7.1 Meta-Review（读 results.tsv + progress.json）：         │
│      • 统计：Keep/Discard 率、修复轮次、耗时分布              │
│      • 模式检测（≥2 次同类错误/issue/高 Discard 率）          │
│      • 自动生成 ≤3 条 lesson 规则（去重检查）                 │
│  7.2 经验分类沉淀：                                          │
│      编码规范 → 子工程规范 | 领域知识 → docs/                │
│      架构约定 → 子工程说明 | Agent 优化 → Memory             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
                   完成报告
```

---

## 八、Path B：/auto-work 全流程（6 阶段）

```
bash .claude/scripts/auto-work-loop.sh "{VER}" "{NAME}"
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段零：需求分类                                            │
│  ─────────────────                                           │
│  • idea.md 含 ## 确认方案 → direct（跳过调研）               │
│  • 全新系统/需选型 → research                                 │
│  • 扩展/修复 → direct                                        │
└──────────────────────┬──────────────────────────────────────┘
                       │ (research)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段零-B：技术调研（仅 research 类）                         │
│  ───────────────────────────────────                          │
│  复用 research-loop.sh：                                      │
│    research:do（搜索业界方案）⇄ research:review（检查质量）   │
│    收敛 or 10 轮 → 结束                                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段一：生成 feature.json                                    │
│  ──────────────────────────                                   │
│  独立 Claude 进程 → 结构化 JSON 需求文档                      │
│  含：requirements / interaction_design / technical_constraints│
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段二：Plan 迭代循环                                        │
│  ═════════════════════                                        │
│  feature-plan-loop.sh：                                       │
│    奇数轮：feature:plan-creator（5步设计）                    │
│      ① 解析需求 → ② 架构 → ③ 详设 → ④ 接口契约 → ⑤ 输出   │
│      plan.json + plan/{protocol,flow,server,client,testing}  │
│    偶数轮：feature:plan-review（7维审查）                     │
│      → plan-review-report.md                                  │
│    收敛：Critical=0 AND Important≤2                           │
│    早退：连续两轮问题数不变                                    │
│    硬上限：20 轮                                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段三：任务拆分                                             │
│  ─────────────────                                            │
│  plan.json → tasks/task-01.md ... task-NN.md                 │
│  最小可独立验证单元，按依赖拓扑排序                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段四：波次并行开发（核心引擎）                              │
│  ═══════════════════════════════                               │
│                                                               │
│  按拓扑排序分 Wave，同 Wave 无依赖的 task 用 git worktree 并行│
│                                                               │
│  每个 Task 原子循环：                                         │
│    ① 保存 git 检查点（HEAD hash）                             │
│    ② feature:develop 循环（feature-develop-loop.sh）：        │
│       奇数轮：feature:developing（9步实现）                   │
│         上下文→范围→计划→编码→测试→编译→宪法自查→文档→摘要  │
│       偶数轮：feature:develop-review（7维审查）               │
│         宪法/方案/事务/边界/质量/安全/测试                     │
│       收敛：C=0 AND H≤2 / 连续两轮不变 / 20轮                │
│    ③ 编译验证                                                 │
│       PASS → ④ | FAIL 3次 → Discard（回滚检查点）            │
│    ④ Review 质量判定                                          │
│       PASS → Keep | FAIL + 质量棘轮恶化 → Discard 本次修复   │
│    ⑤ Keep → 提交 + 记录 results.tsv                          │
│                                                               │
│  波次间 Meta-Review：                                         │
│    ≥2 task 完成 + 有 discard → 分析模式 → 自动生成规则       │
│                                                               │
│  Stage 4-B 验证策略（引擎感知）：                             │
│    编译：PASS则跳过重复编译                                   │
│    MCP 验收：有任何客户端 .cs 改动即触发（不限于[TC-XXX]）    │
│      Basic MCP = 编译检查 + 登录 + 截图确认                   │
│      含 [TC-XXX] → 完整用例操作序列验证                       │
│    单元测试：执行 make test（auto-work 新增）                  │
│    FAIL → 修复 + 重测（≤2轮）                                 │
│                                                               │
│  5.4.0 FAIL 分类（Review 质量判定失败时）：                   │
│    TRIVIAL → 主 agent 内联修复（≤3文件/首次失败/             │
│              代码存在性/数据类型问题）                         │
│    COMPLEX → 独立 claude -p 进程处理（原有流程）              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段五：生成模块文档                                         │
│  ─────────────────────                                        │
│  归档到 docs/Engine/Business/，追加模式                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段六：推送远程仓库                                         │
│  ─────────────────────                                        │
│  P1GoServer / freelifeclient / old_proto 三仓库推送           │
│  禁止 force push                                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
                   完成报告
```

---

## 九、失败恢复策略

```
┌────────────────────┬──────────────────────────────┬──────────┐
│ 失败类型           │ 恢复动作                      │ 回Step3? │
├────────────────────┼──────────────────────────────┼──────────┤
│ 编译错误/缺依赖    │ 直接修复 → 断点续跑           │   否     │
│ 单个 task 失败     │ 修改该 task plan → 重试       │   否     │
│ Plan 不收敛/全丢弃 │ 报告失败的技术决策 → 局部调整 │  仅失败部分│
│ 根本性架构冲突     │ 报告根因 → 重新确认方案       │   是     │
└────────────────────┴──────────────────────────────┴──────────┘

恢复始终从文件重建（idea.md 含完整上下文），不依赖会话记忆。

dev-workflow 失败：读 progress.json + dashboard.txt → 定位断点 → 分级恢复
auto-work 失败：  读 results.tsv + auto-work-log.md → 内置 Keep/Discard 自动回滚
```

---

## 十、取消与中断

```
用户说"停止/取消"
      │
      ├── Step 0-3（方案阶段）→ 直接停止，idea.md 保留供下次断点恢复
      │
      ├── Step 4 dev-workflow → 当前会话中断
      │   progress.json 保留已完成 Phase，下次从断点继续
      │
      └── Step 4 auto-work → kill $(cat FEATURE_DIR/auto-work.pid)
          已完成 task 保留，未完成 task 回滚
```

---

## 十一、关键产出文件

```
{FEATURE_DIR}/
├── idea.md                    ← 需求 + 确认方案（核心交接文件）
│
├── feasibility-check.md       ← Step 3.5 可行性快检结果（有假设时生成）
│
├── requirements.json          ← P1/阶段一 结构化需求
├── feature.json               ← 阶段一 结构化需求（auto-work）
│
├── plan.json                  ← 技术方案
├── plan/                      ← 分模块方案
│   ├── protocol.json
│   ├── flow.json
│   ├── server.json
│   ├── client.json
│   └── testing.json
├── plan-review-report.md      ← 方案审查报告
│
├── tasks/                     ← 原子任务
│   ├── task-01.md
│   ├── task-02.md
│   └── ...
│
├── develop-log.md             ← 实现日志
├── develop-review-report.md   ← 代码审查报告
├── meta-review.md             ← 波次间自学习分析
├── mcp-verify-report.md       ← MCP 验收报告
│
├── results.tsv                ← 全量实验追踪
├── dashboard.txt              ← 实时进度（tail -f）
├── progress.json              ← 阶段状态 + 检查点（断点恢复）
├── heartbeat.json             ← 看门狗心跳
└── auto-work-log.md           ← auto-work 全程日志
```

---

## 十二、两条路径对比

| 维度 | dev-workflow (Path A) | auto-work (Path B) |
|------|----------------------|-------------------|
| **执行环境** | 当前会话（subagent 隔离） | 独立 CLI 进程（零上下文污染） |
| **并行方式** | subagent / CLI 进程 | git worktree 真文件隔离 |
| **MCP 能力** | 全程可用 ✅ | 主进程内可用（阶段四验证）✅ |
| **视觉验收** | P5 Unity MCP 真人模拟 | 有 .cs 改动即触发 Basic MCP（编译+登录+截图）；含[TC-XXX]则完整用例 |
| **设计迭代** | P2 subagent 自审 | feature-plan-loop 多轮收敛 |
| **质量门控** | P6 三Agent + 质量棘轮（10轮） | Keep/Discard + 编译3次上限 |
| **自学习** | P7 经验沉淀 | 波次间 Meta-Review |
| **推荐场景** | 客户端视觉需反复 MCP 迭代调试、任务有依赖 | 纯服务端/逻辑、无依赖可真并行、客户端改动不需反复 MCP 调试 |
| **超时保护** | 单任务 600s | 同 |
| **断点恢复** | progress.json + heartbeat | 阶段完成标记 |
