# V2 NPC 系统文件清单

本文档梳理 V2 版本 NPC 系统重构涉及的所有文件，覆盖从协议定义到服务器 AI 框架到客户端表现的完整链路。

## 一、协议定义

| 文件 | 说明 |
|------|------|
| `old_proto/scene/npc.proto` | NPC 协议定义（唯一编辑入口） |
| `P1GoServer/common/proto/npc_pb.go` | Go 协议生成代码（工具生成，勿手编） |
| `old_proto/_tool_new/go/` | Go 协议生成工具输出目录 |

> 注：C# 协议生成代码由 `old_proto/_tool_new/` 工具生成，分布在客户端多处，非集中目录。

## 二、服务器 — AI 决策框架

### V2Brain（配置驱动决策）

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/decision/v2brain/brain.go` | V2Brain 核心：JSON 配置加载 + 决策评估 |
| `servers/scene_server/internal/common/ai/decision/v2brain/brain_test.go` | Brain 单元测试 |
| `servers/scene_server/internal/common/ai/decision/v2brain/config.go` | Brain 配置结构定义 |
| `servers/scene_server/internal/common/ai/decision/systems/v2brain_decision.go` | V2Brain 决策系统（ECS System 层） |
| `servers/scene_server/internal/common/ai/decision/systems/v2brain_decision_test.go` | 决策系统测试 |
| `servers/scene_server/internal/common/ai/decision/systems/v2brain_integration_test.go` | 集成测试 |

### 表达式解析器

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/decision/v2brain/expr/expr.go` | 表达式求值入口 |
| `servers/scene_server/internal/common/ai/decision/v2brain/expr/expr_test.go` | 表达式测试 |
| `servers/scene_server/internal/common/ai/decision/v2brain/expr/parser.go` | 表达式解析器 |
| `servers/scene_server/internal/common/ai/decision/v2brain/expr/tokenizer.go` | 词法分析器 |
| `servers/scene_server/internal/common/ai/decision/v2brain/expr/field_accessor.go` | 字段访问器（NpcState → 表达式变量） |
| `servers/scene_server/internal/common/ai/decision/v2brain/expr/field_accessor_test.go` | 字段访问器测试 |

### 正交管线（OrthogonalPipeline）

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/pipeline/orthogonal_pipeline.go` | 4 维度正交管线核心 |
| `servers/scene_server/internal/common/ai/pipeline/orthogonal_pipeline_test.go` | 管线测试 |

### V2 行为树引擎（独立于 V1）

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/execution/btree/node.go` | Node 接口 + Status 类型别名 |
| `servers/scene_server/internal/common/ai/execution/btree/leaf.go` | Action + Wait 叶子节点 |
| `servers/scene_server/internal/common/ai/execution/btree/composite.go` | Sequence + Selector + Parallel |
| `servers/scene_server/internal/common/ai/execution/btree/decorator.go` | Condition + Repeater + Inverter + UntilSuccess + UntilFailure + AlwaysSucceed |
| `servers/scene_server/internal/common/ai/execution/btree/tree.go` | BehaviorTree 根容器 |
| `servers/scene_server/internal/common/ai/execution/btree/btree_test.go` | 引擎单元测试（37 用例） |
| `servers/scene_server/internal/common/ai/execution/btree_status.go` | BtStatus 枚举（解决循环依赖） |
| `servers/scene_server/internal/common/ai/execution/bt_handler.go` | BtPlanHandler 适配器 + TickableTree 接口 |

### PlanHandler 执行层

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/execution/plan_handler.go` | PlanHandler 接口 + PlanContext + SceneAccessor |
| `servers/scene_server/internal/common/ai/execution/plan_executor.go` | PlanExecutor：管理 Handler 切换生命周期 |
| `servers/scene_server/internal/common/ai/execution/plan_executor_test.go` | Executor 测试 |
| `servers/scene_server/internal/common/ai/execution/handlers/engagement_handlers.go` | Engagement 维度：CombatBt(行为树) / Pursuit(直写) |
| `servers/scene_server/internal/common/ai/execution/handlers/expression_handlers.go` | Expression 维度：ThreatReact / SocialReact |
| `servers/scene_server/internal/common/ai/execution/handlers/locomotion_handlers.go` | Locomotion 维度：OnFoot |
| `servers/scene_server/internal/common/ai/execution/handlers/navigation_handlers.go` | Navigation 维度：NavigateBt(行为树) / Idle / Interact / Investigate |
| `servers/scene_server/internal/common/ai/execution/handlers/handlers_test.go` | Handler 单元测试（36 用例） |
| `servers/scene_server/internal/common/ai/execution/handlers/util.go` | 工具函数（distanceSqToTarget 等） |

### 全局守卫与交互锁

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/guard/global_guard.go` | 死亡/眩晕时强制退出所有 Handler |
| `servers/scene_server/internal/common/ai/guard/global_guard_test.go` | 守卫测试 |
| `servers/scene_server/internal/common/ai/decision/interaction_lock.go` | 近战交互锁（抑制导航） |
| `servers/scene_server/internal/common/ai/decision/interaction_lock_test.go` | 交互锁测试 |
| `servers/scene_server/internal/common/ai/decision/interaction_manager.go` | 交互管理器 |

### NPC 状态

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/ai/state/npc_state.go` | NpcState：AI 可写状态 + ReactType 常量 |
| `servers/scene_server/internal/common/ai/state/npc_state_test.go` | 状态测试 |
| `servers/scene_server/internal/common/ai/state/npc_state_integration_test.go` | 状态集成测试 |
| `servers/scene_server/internal/common/ai/state/npc_state_snapshot.go` | NpcStateSnapshot：只读快照（含 Expression） |
| `servers/scene_server/internal/common/ai/state/snapshot_test.go` | 快照测试 |

## 三、服务器 — ECS 集成层

### BT Tick 系统 & SceneAccessor

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/system/decision/decision.go` | 决策系统入口（V1 行为树调度） |
| `servers/scene_server/internal/ecs/system/decision/executor.go` | V1 行为树执行器 |
| `servers/scene_server/internal/ecs/system/decision/executor_helper.go` | 执行器辅助函数 |
| `servers/scene_server/internal/ecs/system/decision/executor_resource.go` | 执行器资源管理 |
| `servers/scene_server/internal/ecs/system/decision/bt_tick_system.go` | BT 帧驱动：管线优先 → fallback 旧 MultiTree |
| `servers/scene_server/internal/ecs/system/decision/bt_tick_system_test.go` | mapNpcStateToProto 优先级测试（7 个用例） |
| `servers/scene_server/internal/ecs/system/decision/scene_accessor_adapter.go` | SceneAccessor 适配器（包装 common.Scene） |

### Pipeline 配置 & 工厂

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_defaults.go` | 管线默认配置 + buildDimensionConfigs 工厂 |
| `servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_factory.go` | 管线工厂 |
| `servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_test.go` | 管线配置测试 |

### NPC 管理器 & 扩展

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go` | 场景 NPC 管理器 |
| `servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr_test.go` | 管理器测试 |
| `servers/scene_server/internal/ecs/res/npc_mgr/ext_handler.go` | 扩展接口定义 |
| `servers/scene_server/internal/ecs/res/npc_mgr/town_ext_handler.go` | 小镇 NPC 扩展（含 GTA 切换） |
| `servers/scene_server/internal/ecs/res/npc_mgr/sakura_ext_handler.go` | 樱花模式扩展 |
| `servers/scene_server/internal/ecs/res/npc_mgr/default_ext_handler.go` | 默认扩展 |

### ECS 组件

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/com/cnpc/npc_comp.go` | NPC 基础组件 |
| `servers/scene_server/internal/ecs/com/cnpc/scene_npc.go` | 场景 NPC 组件 |
| `servers/scene_server/internal/ecs/com/cnpc/town_npc.go` | 小镇 NPC 组件（GTA 字段扩展） |
| `servers/scene_server/internal/ecs/com/cnpc/scene_ext.go` | 场景扩展类型（SceneNpcExtType_TownGta=3） |
| `servers/scene_server/internal/ecs/com/cnpc/sakura_npc.go` | 樱花 NPC 组件 |
| `servers/scene_server/internal/ecs/com/cnpc/monster_comp.go` | 怪物组件 |
| `servers/scene_server/internal/ecs/com/cnpc/schedule_comp.go` | 日程组件 |
| `servers/scene_server/internal/ecs/com/cnpc/trade_proxy_comp.go` | 交易代理组件 |
| `servers/scene_server/internal/ecs/com/cnpc/npc_move.go` | NPC 移动组件 |

### 场景实现

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/scene/scene_impl.go` | 场景初始化（GTA 标志位切换逻辑） |

### 配置加载

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/common/config/scene_config.go` | 场景配置（UseGtaNpcBehavior 字段） |
| `common/config/cfg_npcskillconfig.go` | NPC 技能配置加载器（打表生成） |

## 四、服务器 — AI 决策 JSON 配置

| 文件 | 说明 |
|------|------|
| `bin/config/ai_decision_v2/engagement.json` | 默认 Engagement 决策树 |
| `bin/config/ai_decision_v2/expression.json` | 默认 Expression 决策树 |
| `bin/config/ai_decision_v2/locomotion.json` | 默认 Locomotion 决策树 |
| `bin/config/ai_decision_v2/navigation.json` | 默认 Navigation 决策树 |
| `bin/config/ai_decision_v2/gta_engagement.json` | GTA Engagement 决策树 |
| `bin/config/ai_decision_v2/gta_expression.json` | GTA Expression 决策树 |
| `bin/config/ai_decision_v2/gta_locomotion.json` | GTA Locomotion 决策树 |
| `bin/config/ai_decision_v2/gta_navigation.json` | GTA Navigation 决策树 |
| `bin/config/ai_decision_v2/combat.json` | 战斗配置 |
| `bin/config/ai_decision_v2/movement_mode.json` | 移动模式配置 |
| `bin/config/ai_decision_v2/main_behavior.json` | 主行为配置 |

## 五、客户端 — NPC 表现层

### 控制器与管理器

| 文件 | 说明 |
|------|------|
| `Assets/Scripts/Gameplay/Modules/S1Town/Entity/NPC/TownNpcController.cs` | NPC 控制器（Comp 注册 + Update 调度） |
| `Assets/Scripts/Gameplay/Modules/S1Town/Managers/Npc/TownNpcManager.cs` | NPC 管理器 |

### 组件（Comp）

| 文件 | 说明 |
|------|------|
| `Entity/NPC/Comp/TownNpcCombatComp.cs` | 战斗组件 |
| `Entity/NPC/Comp/TownNpcReactComp.cs` | 反应组件（威胁逃跑 / 社交围观 + 平滑旋转） |
| `Entity/NPC/Comp/TownFsmComp.cs` | 状态机组件 |
| `Entity/NPC/Comp/TownNpcAnimationComp.cs` | 动画组件 |
| `Entity/NPC/Comp/TownNpcTransformComp.cs` | 变换组件 |
| `Entity/NPC/Comp/TownNpcWeaponComp.cs` | 武器组件 |
| `Entity/NPC/Comp/TownNpcHoldComp.cs` | 持有物组件 |
| `Entity/NPC/Comp/TownNpcInteractableComp.cs` | 交互组件 |
| `Entity/NPC/Comp/TownNpcPoliceComp.cs` | 警察组件 |
| `Entity/NPC/Comp/TownNpcTradeEffectComp.cs` | 交易特效组件 |

（以上路径省略前缀 `Assets/Scripts/Gameplay/Modules/S1Town/`）

### 状态机（State）

| 文件 | 说明 |
|------|------|
| `Entity/NPC/State/TownNpcStateBase.cs` | 状态基类 |
| `Entity/NPC/State/TownNpcIdleState.cs` | 待机 |
| `Entity/NPC/State/TownNpcMoveState.cs` | 行走 |
| `Entity/NPC/State/TownNpcRunState.cs` | 跑步 |
| `Entity/NPC/State/TownNpcTurnState.cs` | 转向 |
| `Entity/NPC/State/TownNpcCombatState.cs` | 战斗状态（GTA 新增） |
| `Entity/NPC/State/TownNpcFleeState.cs` | 逃跑状态（GTA 新增） |
| `Entity/NPC/State/TownNpcWatchState.cs` | 围观状态（GTA 新增） |
| `Entity/NPC/State/TownNpcInvestigateState.cs` | 调查状态（GTA 新增） |
| `Entity/NPC/State/TownNpcInDoorState.cs` | 室内状态 |
| `Entity/NPC/State/TownNpcTradeEffectState.cs` | 交易特效状态 |

### 数据模型

| 文件 | 说明 |
|------|------|
| `Entity/NPC/Data/TownNpcClientData.cs` | 客户端数据 |
| `Entity/NPC/Data/TownNpcNetData.cs` | 网络同步数据 |
| `Entity/NPC/Data/TownNpcStateData.cs` | 状态数据 |
| `Entity/NPC/Data/TownNpcDialogInfoData.cs` | 对话信息数据 |
| `Entity/NPC/Data/TownNpcSuspicionInfoData.cs` | 怀疑度信息数据 |

### 日程调度

| 文件 | 说明 |
|------|------|
| `Entity/NPC/Schedule/TownNpcScheduleSetConfig.cs` | NPC 日程配置集 |
| `Entity/NPC/Schedule/TownNpcScheduleStateSetConfig.cs` | NPC 日程状态配置集 |

### 配置（打表生成）

| 文件 | 说明 |
|------|------|
| `Assets/Scripts/Gameplay/Config/Gen/CfgNpcSkillConfig.cs` | NPC 技能配置（GTA 新增） |
| `Assets/Scripts/Gameplay/Config/Gen/CfgTownNpc.cs` | 小镇 NPC 配置 |
| `Assets/Scripts/Gameplay/Config/Gen/CfgNpc.cs` | NPC 通用配置 |
| `Assets/Scripts/Gameplay/Config/Gen/CfgNpcAction.cs` | NPC 动作配置 |
| `Assets/Scripts/Gameplay/Config/Gen/CfgNpcBehaviorArgs.cs` | NPC 行为参数配置 |

## 六、配置表（Excel 源文件）

| 文件 | 说明 |
|------|------|
| `freelifeclient/RawTables/npc/NpcSkillConfig.xlsx` | NPC 技能配置（GTA 新增） |
| `freelifeclient/RawTables/npc/NpcAction.xlsx` | NPC 动作 |
| `freelifeclient/RawTables/npc/NpcBehaviorArgs.xlsx` | NPC 行为参数 |
| `freelifeclient/RawTables/npc/NpcArchive.xlsx` | NPC 档案 |
| `freelifeclient/RawTables/npc/NpcTag.xlsx` | NPC 标签 |
| `freelifeclient/RawTables/npc/NpcRelation.xlsx` | NPC 关系 |
| `freelifeclient/RawTables/npc/NpcTimeline.xlsx` | NPC 时间线 |
| `freelifeclient/RawTables/npc/NpcCreator.xlsx` | NPC 创建器 |
| `freelifeclient/RawTables/npc/npc_permanent.xlsx` | NPC 常驻配置 |
| `freelifeclient/RawTables/npc/Plot.xlsx` | 剧情 |
| `freelifeclient/RawTables/npc/MonsterConfig.xlsx` | 怪物配置 |
| `freelifeclient/RawTables/npc/MonsterLevel.xlsx` | 怪物等级 |
| `freelifeclient/RawTables/npc/MonsterPrefab.xlsx` | 怪物预设体 |
| `freelifeclient/RawTables/_tool/dir_file` | 打表输出路径（含 TARGET_GO_CODE） |
| `freelifeclient/RawTables/_tool/dir_file_server` | 服务器打表路径 |

## 七、设计文档

| 文件 | 说明 |
|------|------|
| `docs/design/ai/npc-v2-decision-execution-redesign.md` | 正交管线需求文档 |
| `docs/design/ai/npc-v2-decision-execution-redesign-tech-design.md` | 正交管线技术设计 + 任务清单 |
| `docs/design/ai/npc-gta5-behavior-implementation.md` | GTA 行为实现方案 + GTA5 参考 + 审查报告 |
| `docs/design/ai/npc-combat-expansion.md` | 战斗扩展完整方案（需求+配置表+任务清单） |
| `docs/design/ai/npc-v2-btree-framework.md` | V2 行为树框架设计 |
| `docs/design/ai/npc-v2-file-inventory.md` | 本文件（V2 系统文件清单） |

## 八、数据流总览

```
Excel (RawTables/npc/*.xlsx)
  ↓ generate.exe
Config Code (Gen/CfgNpcSkillConfig.cs + cfg_npcskillconfig.go)
  ↓
Proto (old_proto/scene/npc.proto → npc_pb.go + C#)
  ↓
Server AI: NpcState → V2Brain(JSON) → OrthogonalPipeline → PlanHandler → ECS Comp
  ↓ Proto 同步
Client: TownNpcNetData → TownNpcController → Comp/State → 表现
```

---

**文档版本**: v1.2（新增 V2 btree 引擎章节）
**最后更新**: 2026-03-12
