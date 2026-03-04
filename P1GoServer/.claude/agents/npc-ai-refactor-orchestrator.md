# NPC AI 重构执行指南

## 概述

本文档描述如何使用 Agent 执行 NPC AI 决策系统重构计划。

**计划文件**：`.claude/plans/npc-ai-refactor-plan.md`

---

## Agent 列表

| Agent | 文件 | 职责 | 阶段 |
|-------|------|------|------|
| npc-system-refactor | `npc-system-refactor.md` | 重构感知、视野、警察系统 | 第一阶段 |
| npc-init-refactor | `npc-init-refactor.md` | 统一场景 AI 系统初始化 | 第一、二阶段 |
| npc-creation-refactor | `npc-creation-refactor.md` | 统一 NPC 创建流程 | 第三阶段 |
| npc-ai-test | `npc-ai-test.md` | 测试重构结果 | 各阶段完成后 |

---

## 执行顺序

### 第一阶段：解决 Sakura 场景无法使用 AI 系统的问题

```bash
# 1. 重构系统遍历逻辑（必须首先完成）
claude "执行 @.claude/agents/npc-system-refactor.md 任务 1.1-1.4"

# 2. Sakura 场景初始化 AI 系统（临时方案）
claude "执行 @.claude/agents/npc-init-refactor.md 任务 1.5"

# 3. 测试
claude "执行 @.claude/agents/npc-ai-test.md 阶段一测试"
```

**预期产出**：
- sensor_feature.go 使用 EntityListByType 遍历 NPC
- vision_system.go 使用 EntityListByType 遍历 NPC
- police_system.go 使用 IsNpcPolice() 判断警察
- Sakura 场景调用 initNpcAISystems()
- Sakura NPC 能正常使用 AI 决策功能

### 第二阶段：统一初始化流程

```bash
# 1. 实现接口化配置
claude "执行 @.claude/agents/npc-init-refactor.md 任务 2.1-2.3"

# 2. 测试
claude "执行 @.claude/agents/npc-ai-test.md 阶段二测试"
```

**预期产出**：
- common/scene_info.go 定义 NpcAIConfigProvider 接口
- TownSceneInfo、SakuraSceneInfo 实现接口
- scene_impl.go 统一调用 initNpcAISystemsFromConfig()

### 第三阶段：统一 NPC 创建流程

```bash
# 1. 实现统一创建函数
claude "执行 @.claude/agents/npc-creation-refactor.md 任务 3.1-3.4"

# 2. 测试
claude "执行 @.claude/agents/npc-ai-test.md 阶段三测试"
```

**预期产出**：
- common.go 定义 CreateSceneNpc() 和 CreateSceneNpcParam
- town_npc.go 使用 CreateSceneNpc()
- sakura_npc.go 使用 CreateSceneNpc()
- InitNpcAIComponents() 支持可选警察组件

---

## 回滚策略

每个阶段完成后，如果测试失败：

```bash
# 查看改动
git diff

# 回滚到上一个阶段
git checkout -- <changed_files>
```

---

## 验收标准

### 阶段一验收
- [ ] 小镇 NPC AI 功能正常（回归）
- [ ] Sakura NPC AI 功能正常（新增）
- [ ] 编译通过，无警告

### 阶段二验收
- [ ] 新场景只需实现 GetNpcAIConfig() 接口
- [ ] 删除 initNpcAISystems() 的重复调用
- [ ] 编译通过，无警告

### 阶段三验收
- [ ] CreateTownNpc 使用 CreateSceneNpc
- [ ] CreateSakuraNpc 使用 CreateSceneNpc
- [ ] 新场景 NPC 创建只需 ~20 行代码
- [ ] 编译通过，无警告

---

## 注意事项

1. **每个任务完成后必须编译验证**：`make build APPS='scene_server'`
2. **分步提交**：每个小任务完成后可以单独提交
3. **保持向后兼容**：InitNpcAIComponents() 保留原有签名
4. **日志规范**：新增日志遵循 `.claude/rules/logging.md`
