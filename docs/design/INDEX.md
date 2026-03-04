# design/ 索引

> 快速定位设计文档。按主题分组，关键词辅助搜索。

## 行为树（BT）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-bt-single-tree.md` | 单 JSON 对应单行为，on_exit 子图架构 | 单树、on_exit、生命周期 |
| `design-bt-ue5-refactor.md` | UE5 Phase1：节点实例隔离（深拷贝）、装饰节点族（Inverter/Repeater/Timeout/Cooldown）、行为节点拆分 | UE5、深拷贝、装饰节点、Phase1 |
| `design-bt-ue5-refactor-phase2.md` | UE5 Phase2：Service + Decorator + Abort 事件驱动、Blackboard 观察者、JSON 格式扩展 | Service、Decorator、Abort、事件驱动、Phase2 |
| `design-bt-behavior-nodes-refactor.md` | 行为节点重构：handler→BT 节点转换，13 个新行为节点 | 行为节点、handler 迁移、OnEnter/OnTick/OnExit |
| `design-bt-long-running-nodes.md` | 长运行节点：每节点独立生命周期，移除 on_exit | 长运行、per-node 生命周期、on_exit 移除 |
| `design-bt-brain-integration.md` | Plan 粒度、Brain/BT 决策边界、6 个架构坏味道、复合树模式 | Brain 集成、Plan、复合树、决策边界 |
| `design-bt-town-sakura-compatibility.md` | 行为树兼容小镇+樱花 NPC，硬编码组件/资源/配置抽象 | Town、Sakura、兼容性、组件抽象 |
| `bt-town-sakura-compatibility.md` | 需求文档：BT 支持小镇和樱花校园 NPC | Town、Sakura、NPC 兼容、需求 |

### BT 任务拆解

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `tasks-bt-single-tree.md` | 8 任务：BTreeConfig OnExit、Runner on_exit、JSON 合并 | 单树任务 |
| `tasks-bt-ue5-refactor.md` | 节点隔离、Decorator 实现、JSON 树重写、36 文件整合 | UE5 重构任务 |
| `tasks-bt-ue5-refactor-phase2.md` | 5 个 PR（基础设施/Abort/Service/并行子树/全面重写）、100+ 任务 | Phase2 任务 |
| `tasks-bt-behavior-nodes-refactor.md` | 15 任务：重命名、helpers、13 节点实现、注册、JSON 更新 | 行为节点任务 |
| `tasks-bt-long-running-nodes.md` | 8 任务：移除 OnExit、简化 Runner、19→10 节点重写 | 长运行任务 |
| `tasks-bt-brain-integration.md` | 8 任务：PursuitBehavior.OnExit、JSON 树、Brain 配置 | Brain 集成任务 |
| `tasks-bt-town-sakura-compatibility.md` | 13 任务：能力接口、BtContext 注册、节点重构（3 阶段） | 兼容性任务 |

## NPC 战斗

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-npc-skill.md` | NPC 技能系统：感知→决策→执行，SimpleParallel 追击+攻击，自定义伤害 | NPC 技能、SimpleParallel、伤害、仇恨 |
| `design-npc-attack-p0.md` | NPC 攻击 P0：HitData、can_take_damage、GAS 集成、死亡广播 | 攻击、HitData、GAS、死亡 |
| `design-police-enforcement.md` | 警察执法：pursuit↔investigate↔return 状态机、异步节点模式 | 警察、pursuit、investigate、异步节点、ChaseTarget |
| `tasks-npc-skill.md` | 15 任务：NpcSkill.xlsx、NpcSkillComp、NpcAttack/SelectCombatSkill 节点 | NPC 技能任务 |

## 射击系统

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-shooting-system-migration.md` | Rust→Go 迁移：Shot/Hit/Explosion、CheckManager 反作弊、GAS 伤害管线 | 射击、Rust 迁移、CheckManager、伤害管线 |
| `tasks-shooting-system-migration.md` | 10 任务：ResourceType_CheckManager、damage 模块骨架、各 handler | 射击任务 |

## 反作弊

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-anti-cheat-detection.md` | 移动验证（速度/瞬移/飞行）、射速检查、异常上报 Redis→MongoDB、GM 审查 | 反作弊、移动验证、射速、GM 审查 |
| `tasks-anti-cheat-detection.md` | 10 任务：MoveValidateComp、cheat_reporter、GM handler、配置阈值 | 反作弊任务 |

## 武器轮盘 & 背包

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-weapon-wheel-impl.md` | AddItem/RemoveItem/SelectSlot 逻辑、EquipComp、子弹回收 | 武器轮盘、EquipComp、装备 |
| `design-weapon-wheel-init-fix.md` | Bug 修复：缺失初始化、bulletId、cell index 0 | 武器轮盘初始化、Bug 修复 |
| `design-backpack-sync.md` | Rust→Go 背包数据同步、LoadFromData/ToSaveProto、物品反序列化 | 背包同步、持久化、Rust 迁移 |
| `tasks-weapon-wheel-impl.md` | 10 任务：EquipComp 增强、onChooseCommonWheelSlot 分支 | 武器轮盘任务 |
| `tasks-backpack-sync.md` | 9 任务：NewItemFromProto、LoadFromData/ToSaveProto | 背包任务 |

## 载具 & 传送

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-vehicle-door.md` | Open/CloseVehicleDoorReq、VehicleStatusComp.DoorList、车门状态管理 | 车门、VehicleStatusComp、协议 |
| `design-sakura-vehicle-wheel-teleport.md` | 樱花场景系统边界：载具/武器轮盘/传送作为场景无关模块 | Sakura、系统边界、模块化 |
| `design-traffic-vehicle-sakura.md` | 交通载具：NPC 驾驶环境车、生成+自动消失、Sakura 校园支持 | 交通载具、NPC 驾驶、自动消失 |
| `design-gm-teleport.md` | 传送系统 Rust→Go 迁移：核心实现、入口、NPC 传送逻辑 | 传送、Rust 迁移、GM、NPC 传送 |
| `requirements-traffic-vehicle-sakura.md` | 交通载具扩展到 Sakura：OnTrafficVehicleReq、自动消失、场景隔离 | 交通载具需求、Sakura |
| `tasks-traffic-vehicle-sakura.md` | 9 任务：ComponentType、TrafficVehicleComp、SpawnTrafficVehicle | 交通载具任务 |
| `tasks-sakura-vehicle-wheel-teleport.md` | 13 任务（3 层）：组件、载具核心、武器轮盘核心 | Sakura 载具任务 |

## Sensor 系统

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `design-merge-sensor-systems.md` | 整合 EventSensorSystem 与 SensorFeatureSystem，确保帧内时序确定性 | Sensor 合并、时序、pull-model、push-model |

## 时间系统

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `sakura-time-system.md` | Sakura 时间系统扩展：复用 TimeMgr、场景特有时间行为、无睡眠机制 | Sakura、时间系统、TimeMgr |

## 其他

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `ai-decision-review-fixes.md` | 修复报告：ExitTask 命名 bug、rand.Intn(0) panic、feature 评估顺序 | AI 决策修复、Bug、panic |
| `disaster-recovery-test-plan.md` | 灾难恢复测试计划：崩溃场景、压力测试、内存泄漏、进程恢复、监控 | 灾难恢复、压测、监控 |
