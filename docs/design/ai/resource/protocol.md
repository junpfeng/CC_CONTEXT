# NPC 协议定义文件

## 编辑入口

**唯一编辑入口**: `old_proto/`（独立 git 仓库）

> `P1GoServer/resources/proto/` 是 git submodule，**未参与构建，禁止修改**。

## NPC 相关 Proto 文件

| 文件（相对 `old_proto/`） | 说明 |
|---------------------------|------|
| `scene/npc.proto` | **NPC 核心协议**（~407 行） |
| `scene/player.proto` | 玩家协议（含 `MoveStateProto`，驱动客户端 NPC FSM） |
| `scene/scene.proto` | 场景 NPC 集合同步 |
| `base/base.proto` | 基础类型（向量、坐标等） |
| `social/social_internal_server.proto` | 社交/对话协议 |

## npc.proto 主要定义

### 枚举

| 枚举 | 说明 |
|------|------|
| `NpcState` | NPC 状态（见下表） |
| `MonsterDangerState` | 怪物危险等级 |
| `NpcSyncState` | NPC 同步状态 |
| `WeakStateCommand` | 虚弱状态命令 |

**NpcState 枚举值（0~16，共 17 个）**：

| 值 | 名称 | 说明 |
|----|------|------|
| 0 | None | 无状态 |
| 1 | Stand | 站立 |
| 2 | Ground | 地面 |
| 3 | Drive | 驾驶 |
| 4 | Interact | 交互 |
| 5 | Death | 死亡 |
| 6 | Shelter | 掩蔽 |
| 7 | Shiver | 颤抖 |
| 8 | Combat | 战斗（GTA） |
| 9 | Flee | 逃跑（GTA） |
| 10 | Watch | 围观（GTA） |
| 11 | Investigate | 调查（GTA） |
| 12 | Scared | 恐惧（情绪） |
| 13 | Panicked | 恐慌（情绪） |
| 14 | Curious | 好奇（情绪） |
| 15 | Nervous | 紧张（情绪） |
| 16 | Angry | 愤怒（情绪） |

### 核心消息

| 消息 | 说明 |
|------|------|
| `TownNpcData` | 小镇 NPC 数据同步（含 GTA 扩展 6 字段） |
| `NavigateProto` | 导航目标信息 |
| `MonsterData` | 怪物数据 |
| `NpcWeakStateCommand` | 虚弱状态指令 |

### 通知消息（GTA/情绪扩展）

| 消息 | 说明 |
|------|------|
| `NpcSkillCastNtf` | NPC 技能释放通知 |
| `NpcHitNtf` | NPC 受击通知 |
| `NpcEmotionChangeNtf` | NPC 情绪变化通知 |

## 代码生成工具

**工具**: `old_proto/_tool_new/1.generate.py`

**工作流**: 编辑 `old_proto/` 中的 `.proto` 文件 → 运行 `1.generate.py` → 代码自动生成到各工程目录。
