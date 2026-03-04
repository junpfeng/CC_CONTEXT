# 行为树系统验证清单

## 概述

本清单用于验证行为树系统是否完整实现并正确工作。

---

## 1. 基础设施检查

### 1.1 核心文件存在性

| 文件 | 路径 | 状态 |
|------|------|------|
| BtContext | `common/ai/bt/context/context.go` | ✅ |
| IBtNode 接口 | `common/ai/bt/node/interface.go` | ✅ |
| BtRunner | `common/ai/bt/runner/runner.go` | ✅ |
| NodeFactory | `common/ai/bt/nodes/factory.go` | ✅ |
| BTreeLoader | `common/ai/bt/config/loader.go` | ✅ |
| ExecutorResource | `ecs/system/decision/executor_resource.go` | ✅ |
| BtTickSystem | `ecs/system/decision/bt_tick_system.go` | ✅ |

### 1.2 类型注册

| 类型 | 位置 | 状态 |
|------|------|------|
| SystemType_AiBt | `common/system_type.go` | ✅ |
| ResourceType_Executor | `common/resource_type.go` | ✅ |

---

## 2. 初始化流程检查

### 2.1 场景初始化 (scene_impl.go)

- [x] 创建 ExecutorResource
- [x] 调用 AddResource 注册
- [x] **调用 RegisterExampleTrees** ← 之前遗漏
- [x] **调用 RegisterTreesFromConfig** ← 之前遗漏
- [x] 创建 DecisionSystem
- [x] 创建 BtTickSystem 并传入 BtRunner

### 2.2 NPC 初始化 (npc/common.go)

- [x] 从 Scene 获取共享的 ExecutorResource
- [x] 使用共享 Executor 创建 DecisionComp
- [x] 降级处理：资源不存在时创建临时 Executor

---

## 3. 运行时流程检查

### 3.1 行为树执行流程

```
GSS Brain 产生 Plan
    ↓
Executor.OnPlanCreated()
    ↓
BtRunner.HasTree(planName)?  ← 之前因为 trees 为空永远返回 false
    ↓ Yes
BtRunner.Run(planName, entityID)
    ↓
BtTickSystem.Update() 每帧 Tick
    ↓
行为树完成 → 触发重评估
```

### 3.2 验证点

- [ ] `BtRunner.trees` 不为空（场景初始化后检查）
- [ ] `BtRunner.HasTree("bt_wait")` 返回 true
- [ ] Plan 名称与行为树名称匹配时，走行为树逻辑
- [ ] 行为树完成后，触发 `DecisionComp.TriggerCommand()`

---

## 4. 配置文件检查

### 4.1 JSON 配置文件

| 文件 | 路径 | 状态 |
|------|------|------|
| patrol.json | `bt/trees/patrol.json` | ✅ |
| conditional.json | `bt/trees/conditional.json` | ✅ |

### 4.2 嵌入检查

```go
//go:embed *.json
var treeConfigs embed.FS
```

- [x] 使用 `//go:embed` 嵌入 JSON 文件
- [x] `RegisterTreesFromConfig` 正确读取嵌入文件

---

## 5. 编译验证

```bash
make build APPS='scene_server'
```

- [x] 编译无错误
- [x] 无 import 循环依赖

---

## 6. 端到端测试建议

### 6.1 最小验证场景

1. 创建一个 NPC
2. 确保 NPC 有 DecisionComp
3. 配置一个简单的 Plan（如 "bt_wait"）
4. 观察日志确认行为树被启动

### 6.2 关键日志

```
[Scene] registered X behavior trees from config  ← 场景初始化
[Executor] BT started, plan=bt_wait, entity=123  ← 行为树启动
[BtTickSystem] tree completed, entity_id=123     ← 行为树完成
```

---

## 7. 问题排查指南

### 问题：行为树从未执行

**检查点**：
1. `BtRunner.trees` 是否为空？
   - 是 → 检查场景初始化是否调用了 `RegisterExampleTrees` / `RegisterTreesFromConfig`
2. Plan 名称是否与行为树名称匹配？
   - `HasTree(planName)` 区分大小写
3. `EnableDecision` 配置是否为 true？

### 问题：行为树执行后 NPC 停止响应

**检查点**：
1. 行为树是否正常完成（Success/Failed）？
2. `onTreeCompleted` 是否调用了 `TriggerCommand()`？
3. DecisionComp 是否正确重新评估？

---

## 8. 设计-实现一致性检查

| 设计文档描述 | 实现状态 |
|-------------|---------|
| 场景初始化创建 ExecutorResource | ✅ 已实现 |
| 场景初始化注册行为树模板 | ✅ 已实现 (2026-02-02 补充) |
| NPC 使用共享 ExecutorResource | ✅ 已实现 |
| BtTickSystem 每帧 Tick | ✅ 已实现 |
| 完成后触发重评估 | ✅ 已实现 |

---

## 更新记录

| 日期 | 更新内容 |
|------|----------|
| 2026-02-02 | 创建清单，补充行为树注册调用 |
