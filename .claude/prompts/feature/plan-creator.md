---
description: 通过需求和AI共创实现方案
argument-hint: [version_id feature_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `docs/Version/*/` 下的子目录，将参数中的空格分隔词与目录结构匹配。典型用法是 `v0.0.2-mvp deep-research`，对应 `docs/Version/v0.0.2-mvp/deep-research/`
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分为 version_id 和 feature_name
3. **验证路径**：确认 `docs/Version/{version_id}/{feature_name}/feature.json`（或兼容旧版 `feature.md`）存在
4. **无法自动匹配时**：使用 AskUserQuestion 向用户确认，列出已有的版本目录和功能目录供选择

获得完整参数后再继续。

## 任务

在本项目框架下，基于需求文档 `docs/Version/{version_id}/{feature_name}/feature.json`（或兼容旧版 `feature.md`）进行业务需求共创，输出 JSON 格式的技术规格 `plan.json`。

## 你的角色

1. 精通大场景、多人联网游戏开发的技术专家
2. 经验丰富的游戏策划
3. 熟悉当前项目架构（请先阅读相关 CLAUDE.md 和 constitution.md）

## 工作流程

### 第一步：建立上下文

**使用并行 Agent 加速上下文建立。** 启动以下 Agent 并行执行：

- **Agent 1（文档阅读）**：阅读需求文档 `docs/Version/{version_id}/{feature_name}/feature.json`（若不存在则读 `feature.md`）+ 项目宪法 `P1GoServer/.claude/constitution.md` 和 `freelifeclient/.claude/constitution.md`
- **Agent 2（现有设计调研）**：阅读 `docs/Engine/` 下与本功能相关的现有设计文档
- **Agent 3（现有代码调研）**：调研 `P1GoServer/` 与 `freelifeclient/` 中与本功能相关的现有代码，找到最相似的已有实现作为参考模板，总结命名风格、文件组织、API 调用方式、错误处理模式

等所有 Agent 返回后，综合它们的结果建立完整上下文，再进入下一步。

### 第二步：结构化需求澄清

通过向我提问来澄清需求。提问必须覆盖以下维度（按需选择相关维度）：

**通用维度：**
- **功能边界**：这个功能做什么、不做什么？与哪些现有功能有交互？
- **数据模型**：需要哪些新的数据结构？需要持久化吗？
- **协议设计**：客户端-服务端需要哪些新消息？消息流转顺序？
- **错误与异常**：每个操作可能失败的场景？失败后如何恢复？
- **并发与时序**：是否存在竞态条件？多人同时操作同一资源怎么办？断线重连怎么处理？
- **边界条件**：数值上限/下限？空列表？重复操作？频率限制？

**服务端维度：**
- **Actor 职责**：涉及哪些 Actor（Avatar/Map/Manager）？各自负责什么？Actor 间如何通信？
- **持久化方案**：MongoDB/Redis 如何选型？数据结构怎么设计？
- **错误码设计**：需要哪些 errorx 错误码？触发条件是什么？

**客户端维度：**
- **UI/UX 交互**：需要哪些新界面或 UI 组件？交互流程是怎样的？有无动画/特效需求？
- **客户端状态管理**：本地需要缓存哪些数据？状态如何同步？离线/弱网时怎么表现？
- **表现与反馈**：操作后的即时反馈是什么（音效、动画、提示）？加载和等待状态如何表现？
- **客户端容错**：网络延迟/丢包时的客户端预测和回滚策略？服务端推送异常数据时如何防御？

每次问不超过8个问题，等我回答后再继续下一轮，直到所有关键问题都澄清。

### 第三步：方案摘要确认

在写完整 plan 之前，先输出一份简短的**方案摘要**（不超过一屏），包含：
- 核心设计思路（一句话）
- 服务端：涉及的 Actor 和职责划分
- 客户端：涉及的界面/模块和职责划分
- 关键消息流（简要）
- 主要技术决策点

等我确认方向正确后，再进入下一步。

### 第四步：评估复杂度并输出 plan.json

在输出 plan 之前，先评估方案的复杂度。判断标准：

**简单方案**（满足以下全部条件）：
- 涉及的模块 ≤ 3 个
- 新增 API ≤ 5 个
- 无多阶段（Phase）实施计划

**复杂方案**（满足以下任一条件）：
- 涉及的模块 > 3 个
- 新增 API > 5 个
- 有多阶段（Phase）实施计划
- 涉及前后端同时大规模改造

---

#### 4A. 简单方案：单文件输出

将完整的技术规格写入 `docs/Version/{version_id}/{feature_name}/plan.json`。

#### 4B. 复杂方案：主文件 + 分文件输出

**使用并行 Agent 加速输出。** 先写 plan.json 主文件（含摘要和索引），然后启动多个 Agent 并行写子文件：
- Agent A：写 `plan/protocol.json`（协议定义详情）
- Agent B：写 `plan/flow.json`（流程设计详情）
- Agent C：写 `plan/server.json`（服务端设计详情）
- Agent D：写 `plan/client.json`（客户端设计详情）
- Agent E：写 `plan/testing.json`（测试要点详情）

每个 Agent 需要携带完整的方案上下文（从前面步骤积累的需求理解、架构决策等），确保子文件内容与主文件摘要一致。

**目录结构：**
```
docs/Version/{version_id}/{feature_name}/
├── feature.json        # 需求文档（已有）
├── plan.json           # 主文件：概述 + 索引 + 关键决策
└── plan/               # 详情子目录（仅复杂方案）
    ├── protocol.json   # 协议定义详情
    ├── flow.json       # 流程设计详情
    ├── server.json     # 服务端设计详情
    ├── client.json     # 客户端设计详情
    └── testing.json    # 测试要点详情
```

**原则：**
- 只读 plan.json 就能理解整体方案和关键决策
- 需要实现细节时再查看对应 plan/*.json 子文件
- 每个子文件独立可读，包含完整上下文

---

**无论简单还是复杂方案，plan.json 都必须遵循以下 JSON Schema：**

```json
{
  "name": "{feature_name} 技术规格",
  "overview": "功能目标和范围的简要描述",
  "complexity": "simple 或 complex",
  "sub_files": ["plan/protocol.json", "..."],

  "protocols": [
    {
      "name": "消息名称（如 ReqXxx、ResXxx、XxxNtf）",
      "type": "req|res|ntf",
      "description": "消息用途描述",
      "fields": [
        {"name": "字段名", "type": "类型", "description": "说明"}
      ]
    }
  ],

  "flows": {
    "main": [
      {
        "name": "主流程名称",
        "description": "流程概述",
        "steps": [
          "步骤1: 客户端发起XXX",
          "步骤2: 服务端处理XXX → 返回结果",
          "步骤3: 客户端收到响应 → 更新UI"
        ]
      }
    ],
    "exception": [
      {
        "name": "异常场景名称",
        "trigger": "触发条件",
        "handling": "处理方式"
      }
    ]
  },

  "server_design": {
    "data_models": [
      {
        "name": "数据模型名",
        "storage": "mongodb|redis|memory",
        "description": "模型用途",
        "fields": [
          {"name": "字段名", "type": "类型", "description": "说明"}
        ]
      }
    ],
    "actors": [
      {
        "name": "Actor 名称",
        "responsibilities": ["职责1", "职责2"],
        "handlers": ["处理的消息类型"]
      }
    ],
    "error_codes": [
      {
        "code": "ERROR_CODE_NAME",
        "description": "错误描述",
        "trigger": "触发条件"
      }
    ]
  },

  "client_design": {
    "managers": [
      {
        "name": "Manager 名称",
        "base_type": "BaseManager|MonoManager",
        "responsibilities": ["职责1"]
      }
    ],
    "ui_panels": [
      {
        "name": "面板名称",
        "description": "面板功能描述"
      }
    ],
    "state_management": "客户端本地数据结构、缓存策略、状态同步方式",
    "error_handling": "网络异常时的客户端行为和降级策略"
  },

  "testing": {
    "server": ["服务端测试要点1", "服务端测试要点2"],
    "client": ["客户端测试要点1", "客户端测试要点2"]
  },

  "file_list": [
    {
      "path": "文件路径",
      "action": "create|modify",
      "side": "client|server|proto|config",
      "description": "文件职责描述"
    }
  ],

  "constitution_check": {
    "server": ["宪法检查结果1"],
    "client": ["宪法检查结果1"]
  }
}
```

**复杂方案子文件 Schema（每个 plan/*.json 对应 plan.json 中的一个章节）：**
- `plan/protocol.json`：`{"protocols": [...]}` — 同 plan.json 中 protocols 字段的完整版
- `plan/flow.json`：`{"flows": {"main": [...], "exception": [...]}}` — 完整流程详情
- `plan/server.json`：`{"server_design": {...}}` — 完整服务端设计
- `plan/client.json`：`{"client_design": {...}}` — 完整客户端设计
- `plan/testing.json`：`{"testing": {...}}` — 完整测试要点

复杂方案中，plan.json 的各章节字段包含摘要，plan/*.json 包含完整详情。

### 第五步：合宪性自检

输出 plan 后，对照两端的 `constitution.md` 进行自检并报告：

**服务端自检（对照 `P1GoServer/.claude/constitution.md`）：**
- Actor 通信是否都通过消息传递？（第五条）
- 错误是否都有显式处理和日志？（第三条 3.1/3.2）
- 是否使用了 safego 启动协程？（第五条 5.6）
- 是否引入了不必要的复杂性？（第一条）
- 是否有全局变量？（第三条 3.3）

**客户端自检（对照 `freelifeclient/.claude/constitution.md`）：**
- 对照客户端宪法中的各项规则逐条检查

---

请先完成参数解析，然后执行第一步建立上下文，再开始第二步的提问。