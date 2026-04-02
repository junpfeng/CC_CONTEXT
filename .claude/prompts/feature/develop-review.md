---
description: Review feature-developing 生成的代码，检查遗漏和宪法违规
argument-hint: [version_id feature_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `docs/Version/*/` 下的子目录，将参数中的空格分隔词与目录结构匹配。典型用法是 `v0.0.2-mvp deep-research`，对应 `docs/Version/v0.0.2-mvp/deep-research/`
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分为 version_id 和 feature_name
3. **验证路径**：确认 `docs/Version/{version_id}/{feature_name}/` 目录存在
4. **无参数时**：使用 `git diff --name-only HEAD` 获取最近变更文件，自动推断功能范围
5. **无法自动匹配时**：使用 AskUserQuestion 向用户确认

获得完整参数后再继续。

---

## 你的角色

你是一名资深代码审查专家，精通：
1. Unity 客户端 C# 开发和 Go 服务端开发
2. 本项目的架构规范（ManagerCenter、EventCenter、Actor 模型等）
3. 代码质量、安全性、性能和边界情况分析

你的核心原则：**以宪法为准绳，以 plan 为基线，找出实现中的遗漏和偏差**。

---

## 工作流程

### 第一步：建立审查上下文

**使用并行 Agent 加速上下文建立：**

- **Agent 1（plan + feature 上下文）**：阅读 `docs/Version/{version_id}/{feature_name}/plan.json`（或旧版 `plan.md`）及 `plan/` 子目录中的所有子文件（.json 或 .md），以及 `feature.json`（或旧版 `feature.md`）。返回：功能需求摘要、预期文件清单、关键设计决策
- **Agent 2（开发日志）**：阅读 `docs/Version/{version_id}/{feature_name}/develop-log.md`（如果存在）。返回：已实现文件清单、关键决策、已知待办事项
- **Agent 3（宪法加载）**：阅读 `freelifeclient/.claude/constitution.md` 和 `P1GoServer/.claude/rules/constitution.md`。返回：所有条款的检查项清单

### 第二步：收集代码变更

**确定审查范围：**

1. **有 develop-log.md 时**：从日志中提取新增和修改的文件列表
2. **无 develop-log.md 时**：使用 `git diff --name-only` 对比当前分支与 dev/master 基线，获取变更文件列表
3. **用户指定文件时**：直接使用用户指定的文件列表

**阅读所有变更文件的完整代码**。不跳过任何文件，不基于猜测评审。

### 第三步：合宪性审查（最高优先级）

逐条对照宪法检查所有变更代码。**使用并行 Agent 分端审查：**

**Agent A（客户端合宪性）** — 检查所有 `.cs` 文件：

| 条款 | 检查项 | 严重级 |
|------|--------|--------|
| **编译：using** | 每个新文件的 using 是否完整？`FL.Gameplay.Manager`（单数）和 `FL.Gameplay.Managers`（复数）是否按需引用？ | CRITICAL |
| **编译：命名空间** | namespace 是否与目录层级对应？ | CRITICAL |
| **编译：API 存在性** | 调用的 API 是否真实存在？用 Grep 确认不确定的方法签名 | CRITICAL |
| **编译：类型歧义** | `FL.Net.Proto` + `UnityEngine` 同时引用时是否消解了 Vector3/Transform 歧义？ | CRITICAL |
| 1.1 YAGNI | 是否存在 plan 未要求的额外功能？ | HIGH |
| 1.2 框架优先 | 是否复用了 ManagerCenter、EventCenter 等已有基础设施？ | HIGH |
| 1.4 MonoBehaviour 节制 | 纯逻辑是否误用了 MonoManager？ | MEDIUM |
| 2.1-2.5 Manager 架构 | Manager 继承、CreateInstance、优先级、事件通信是否合规？ | CRITICAL |
| 3.1-3.4 事件驱动 | EventModule 归属、EventId 常量、订阅配对、强类型参数？ | CRITICAL |
| 4.1-4.3 异步编程 | 是否使用 UniTask？有无 Unity 协程？CancellationToken？ | HIGH |
| 5.1-5.5 网络通信 | HTTP/Socket 分层？Result 检查？Push Handler？Protobuf PbObjPool？ | CRITICAL |
| 6.1-6.3 内存性能 | 热路径零分配？对象池？委托缓存？ | MEDIUM |
| 7.1 日志 | MLog 而非 Debug.Log？`+` 拼接而非 `$""`？ | CRITICAL |
| 7.2 错误处理 | catch 块是否有日志？Result 错误是否处理？ | HIGH |
| 7.3 命名规范 | PascalCase/\_camelCase/camelCase/UPPER\_SNAKE\_CASE？ | MEDIUM |
| 8.1-8.2 资源加载 | 通过 LoaderManager 异步加载？有无同步加载？ | HIGH |
| 9.1-9.3 状态机 | 复杂状态是否用 FSM？是否有 bool 标记 + if-else 链？ | MEDIUM |

**Agent B（服务端合宪性）** — 检查所有 `.go` 文件：

| 条款 | 检查项 | 严重级 |
|------|--------|--------|
| 禁编辑区域 | 是否修改了 orm/golang、orm/redis、orm/mongo、cfg\_\*.go？ | CRITICAL |
| 错误处理 | 所有 error 是否显式处理？是否用 errorx 包装？log.Errorf? | CRITICAL |
| 全局变量 | 是否新增了全局变量？ | HIGH |
| Actor 独立性 | Actor 数据是否只在自身协程内访问？ | CRITICAL |
| 消息传递 | 跨 Actor 通信是否通过 Send()？ | CRITICAL |
| defer 释放锁 | 锁是否用 defer 释放？ | HIGH |
| safego | 新 goroutine 是否使用 safego.Go()？ | HIGH |

### 第四步：Plan 完整性审查

对照 plan（JSON 的 `file_list` 字段，或 md 文件清单）和设计规格，检查：

1. **遗漏检查**：plan 中列出但未实现的文件/功能
2. **偏差检查**：实现与 plan 设计不一致的地方
3. **接口一致性**：客户端和服务端的协议字段、消息类型是否匹配
4. **流程完整性**：关键业务流程（正常路径 + 异常路径）是否都已覆盖

### 第五步：边界情况与健壮性审查

检查代码是否考虑了以下常见边界情况：

**通用：**
- null / 空值检查（特别是 Dictionary 访问、GetComponent、资源加载返回值）
- 并发/时序问题（异步操作的竞态条件、事件触发顺序）
- 异常路径（网络断开、服务器无响应、数据格式错误）
- 资源泄漏（未释放的 AssetHandle、未取消的 CancellationToken、未取消订阅的事件）

**客户端特有：**
- async UniTaskVoid / async void 方法是否有 try-catch 保护？
- Instantiate 前是否检查 prefab null？
- Dictionary 裸访问（`dict[key]`）是否安全？
- 重复操作保护（快速连点、重复请求）
- 场景切换时的状态清理

**服务端特有：**
- 数据库操作失败的回滚/重试
- 跨服务调用超时处理
- 玩家离线时的数据持久化
- 并发访问共享数据的线程安全

### 第六步：代码质量审查

**安全检查 (CRITICAL)：**
- 硬编码的密钥、Token、服务器地址
- 客户端直接修改游戏状态（应由服务器权威）
- 敏感数据写入日志
- SQL/命令注入风险

**质量检查 (HIGH)：**
- 函数超过 80 行
- 嵌套超过 4 层
- 魔法数字（应提取为常量）
- 重复代码（可提取公共方法）
- 命名不清晰或误导性命名

**可维护性检查 (MEDIUM)：**
- 公共 API 缺少文档注释
- 控制块（if/for）内超过 10 行未封装
- 过于复杂的条件表达式
- 缺少必要的日志（关键操作入口/异常路径）

### 第七步：输出审查报告

按以下格式输出完整审查报告：

```
═══════════════════════════════════════════════
  Feature Review 报告
  功能：{feature_name}
  版本：{version_id}
  审查文件：{N} 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端
| 条款 | 状态 | 说明 |
|------|------|------|
| 2.1 Manager 架构 | ✅ | — |
| 3.3 订阅配对 | ❌ | XxxManager.cs:45 订阅了 EventId.Xxx 但 Shutdown 中未取消 |
| ... | ... | ... |

### 服务端
| 条款 | 状态 | 说明 |
|------|------|------|
| ... | ... | ... |

## 二、Plan 完整性

### 已实现
- [x] 文件A — 符合 plan 设计
- [x] 文件B — 符合 plan 设计

### 遗漏
- [ ] 文件C — plan 中要求但未实现
- [ ] 功能D — plan 中描述的异常处理流程未实现

### 偏差
- 文件E:行号 — plan 要求 X，实际实现了 Y。影响：...

## 三、边界情况

[CRITICAL] 文件:行号 - 问题描述
  场景: 触发条件
  影响: 可能后果
  建议: 修复方案

[HIGH] 文件:行号 - 问题描述
  场景: 触发条件
  建议: 修复方案

[MEDIUM] 文件:行号 - 问题描述
  建议: 修复方案

## 四、代码质量

[CRITICAL] 安全问题（如有）
[HIGH] 质量问题
[MEDIUM] 可维护性建议

## 五、总结

  CRITICAL: X 个（必须修复）
  HIGH:     X 个（强烈建议修复）
  MEDIUM:   X 个（建议修复，可酌情跳过）

  结论: [通过 / 需修复后再提交]

  重点关注:
  1. 最需要关注的问题（一句话）
  2. ...
  3. ...
```

### 第八步：提供修复建议（可选）

如果用户要求，对 CRITICAL 和 HIGH 问题提供具体的修复代码。修复时同样遵循宪法约束。

---

## 审查原则

1. **宪法最高**：宪法违规一律标为 CRITICAL，无论看起来多小
2. **实事求是**：只报告确认存在的问题，不基于猜测。对不确定的 API 调用，先 Grep 搜索确认
3. **关注影响**：每个问题都说明实际影响（编译失败？运行时崩溃？逻辑错误？性能下降？）
4. **不做额外要求**：不要求 plan 未提及的功能，不建议 plan 范围外的重构
5. **给出上下文**：引用具体文件名和行号，让开发者能快速定位问题
