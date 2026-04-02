# 服务端 NPC 配置文件

> 路径相对于 `P1GoServer/`

## 1. TOML 全局配置

**文件**: `bin/config.toml`（`[scene]` 段）

| 配置项 | 类型 | 说明 |
|--------|------|------|
| `use_bt` | int | 0=使用 `ai_decision/` 目录，1=使用 `ai_decision_bt/` 目录 |
| `use_scene_npc_arch` | int | 0=TownNpcMgr（V1），1=SceneNpcMgr（V2） |
| `use_gta_npc_behavior` | int | 0=禁用，1=启用 GTA5 行为模式 |
| `navmesh_path` | string | 导航网格文件目录（默认 `config/navmesh/`） |

## 2. V2 AI 决策配置（JSON）

**目录**: `bin/config/ai_decision_v2/`

正交管线 4 维度配置，每个维度有默认版和 GTA 版：

| 文件 | 维度 | 说明 |
|------|------|------|
| `bin/config/ai_decision_v2/engagement.json` | Engagement | 默认参与/交互决策 |
| `bin/config/ai_decision_v2/expression.json` | Expression | 默认表情/反应决策 |
| `bin/config/ai_decision_v2/locomotion.json` | Locomotion | 默认移动方式决策 |
| `bin/config/ai_decision_v2/navigation.json` | Navigation | 默认导航决策 |
| `bin/config/ai_decision_v2/gta_engagement.json` | Engagement | GTA 参与决策（含战斗/追击） |
| `bin/config/ai_decision_v2/gta_expression.json` | Expression | GTA 表情决策（含威胁/社交反应） |
| `bin/config/ai_decision_v2/gta_locomotion.json` | Locomotion | GTA 移动决策 |
| `bin/config/ai_decision_v2/gta_navigation.json` | Navigation | GTA 导航决策（含调查） |
| `bin/config/ai_decision_v2/combat.json` | 全局 | 战斗配置（技能/攻击参数，供 Engagement 维度引用） |
| `bin/config/ai_decision_v2/movement_mode.json` | 全局 | 移动模式配置（供 Locomotion 维度引用） |
| `bin/config/ai_decision_v2/main_behavior.json` | 全局 | 主行为状态机（idle/move/dialog/pursuit/meeting/trade，跨维度调度） |

**配置格式**: JSON，字符串表达式条件（如 `"health < 30"`），由 V2Brain 解析。

## 3. V1 行为树配置（JSON）

**目录**: `bin/config/ai_decision_bt/`

| 文件 | 说明 |
|------|------|
| `bin/config/ai_decision_bt/Blackman_State.json` | Blackman NPC（日程/聚会/对话/执法） |
| `bin/config/ai_decision_bt/CustomeNpc_State.json` | 自定义 NPC |
| `bin/config/ai_decision_bt/Dan_State.json` | Dan NPC |
| `bin/config/ai_decision_bt/DealerNpc_State.json` | 商人 NPC |
| `bin/config/ai_decision_bt/Sakura_Common_State.json` | 樱花通用配置 |

**说明**: V1 架构使用状态机 + 任务节点驱动，通过 `use_bt=1` 启用。

## 4. 导航网格

**目录**: `bin/config/navmesh/`

场景服务器启动时加载，用于 NPC 寻路。TOML 中 `navmesh_path` 指定加载目录。

| 文件 | 格式 | 说明 |
|------|------|------|
| `bin/config/navmesh/WorldNavBake_20241218.bin` | bin | 主世界导航网格 |
| `bin/config/navmesh/WorldNavBake_DiamondCasino.bin` | bin | 钻石赌场导航网格 |
| `bin/config/navmesh/Apartment01.bin` | bin | 公寓室内导航网格 |
| `bin/config/navmesh/Sakura.obj` | obj | 樱花场景导航网格 |
| `bin/config/navmesh/ScheduleI.obj` | obj | ScheduleI 场景导航网格 |
