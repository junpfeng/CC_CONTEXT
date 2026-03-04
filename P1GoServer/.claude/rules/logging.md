---
paths:
  - "servers/**/*.go"
  - "common/**/*.go"
---

# 日志规范

## 格式与必需字段

统一格式：`log.Debugf("[模块名] 描述, key=%v, key=%v", val1, val2)`

**格式符**：统一用 `%v`，浮点数可用 `%.3f`。禁止 `%d`/`%s`/`%.2f`/`%+v`。

**必需字段**（缺一不可）：

| 场景 | 必需字段 | 排列顺序 |
|------|----------|----------|
| 涉及 NPC | `npc_entity_id` + `npc_cfg_id`（必须成对） | npc_entity_id → npc_cfg_id → 业务字段 |
| 涉及玩家 | `player_entity_id` | |
| NPC 与玩家交互 | 上述全部 + `role_id` | npc_entity_id → npc_cfg_id → role_id → 业务字段 |

**关键字段命名**：

| 字段 | 命名 | 说明 |
|------|------|------|
| NPC 实体/配置 ID | `npc_entity_id` / `npc_cfg_id` | 必须成对出现 |
| 玩家实体/角色 ID | `player_entity_id` / `role_id` | role_id 用于交互场景 |
| 通用/目标实体 ID | `entity_id` / `target_entity_id` / `target_npc_entity_id` | |
| 其他 | `scene_id` / `plan` / `tree_name` / `feature` / `duration_ms` | |

## 模块标签

| 模块类型 | 格式 | 示例 |
|---------|------|------|
| 组件 / 系统 | `[CompName]` / `[SystemName]` | `[VisionComp]`, `[DecisionSystem]` |
| 执行器 / 感知器 | `[Executor]` / `[SensorName]` | `[Executor][handleMoveEntry]` |
| AI 决策 | `[Decision][SubModule]` | `[Decision][GSS]` |
| BT 节点 / 工具函数 | `[NodeName]` / `[functionName]` | `[IdleBehavior]`, `[setTransformFromFeature]` |
| BT 运行器/Tick/上下文 | `[BtRunner]` / `[BtTickSystem]` / `[BtContext]` | |

## NPC cfg_id 获取方式

| 模块 | 获取方式 |
|------|----------|
| BT 节点 | `ctx.GetNpcCfgId()` |
| BtRunner | `instance.Context.GetNpcCfgId()` |
| BtTickSystem | `s.getNpcCfgId(entityID)` |
| Decision Agent / gssBrain | `a.npcCfgId` / `b.npcCfgId` |
| FSM State | `ctx.NpcCfgId` |
| Executor | `e.getNpcCfgId(entityID)` |
| Police System | `getNpcCfgId(scene, entityID)` |
| PoliceComp / BeingWantedComp | 组件内 helper（需 nil-Scene guard） |
| 其他 System | `common.GetComponentAs[*cnpc.NpcComp](...).NpcCfgId` |

## Helper 性能规则

1. **方法入口缓存**：`getNpcCfgId`/`getPlayerRoleId` 每次调用做 ECS 查询，应在方法开头调用一次存局部变量
2. **循环外提升**：NPC 自身 cfgId 在循环中不变，必须提到循环外
3. **nil-Scene guard**：组件级 helper 必须检查 `scene == nil`（测试可能用 nil Scene）

## 日志级别

`Debugf`(调试) → `Infof`(重要/生产) → `Warnf`(警告) → `Errorf`(错误)
