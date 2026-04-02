# NPC 配置表源文件（Excel）

> 路径相对于 `freelifeclient/RawTables/`
>
> 打表工具：`_tool/` 目录下，输出路径配置在 `_tool/dir_file`

## 1. NPC 核心配表（npc/）

| 文件 | 说明 |
|------|------|
| `npc/npc_permanent.xlsx` | NPC 常驻配置（基础属性定义） |
| `npc/NpcAction.xlsx` | NPC 动作配置 |
| `npc/NpcBehaviorArgs.xlsx` | NPC 行为参数 |
| `npc/NpcSkillConfig.xlsx` | NPC 技能配置（GTA 新增） |
| `npc/NpcCreator.xlsx` | NPC 创建器/生成规则 |
| `npc/NpcTag.xlsx` | NPC 标签分类 |
| `npc/NpcTimeline.xlsx` | NPC 时间轴事件 |
| `npc/NpcArchive.xlsx` | NPC 档案信息 |
| `npc/NpcRelation.xlsx` | NPC 关系网络 |
| `npc/Plot.xlsx` | NPC 剧情配置 |

## 2. 怪物配表（npc/）

| 文件 | 说明 |
|------|------|
| `npc/MonsterConfig.xlsx` | 怪物基础配置 |
| `npc/MonsterLevel.xlsx` | 怪物等级数值 |
| `npc/MonsterPrefab.xlsx` | 怪物预设体映射 |

## 3. 小镇 NPC 配表（TownNpc/）

| 文件 | 说明 |
|------|------|
| `TownNpc/npc.xlsx` | 小镇 NPC 定义 |
| `TownNpc/DealerConfig.xlsx` | 商人 NPC 配置 |
| `TownNpc/NpcContact.xlsx` | NPC 接触点 |
| `TownNpc/NpcMeetingPoint.xlsx` | NPC 聚集点 |
| `TownNpc/NpcMeetingTime.xlsx` | NPC 聚集时间 |
| `TownNpc/NpcTownDialogue.xlsx` | 城镇 NPC 对话 |

## 4. 关联配表（其他目录）

| 文件 | 说明 |
|------|------|
| `play/npc_group.xlsx` | NPC 分组配置 |
| `animation/NpcAnimation.xlsx` | NPC 动画映射表 |
| `audio/AudioNPCdialogue.xlsx` | NPC 对话音频 |
| `audio/AudioNPCDlg.xlsx` | NPC 对话语音 |
| `audio/NPCVoice.xlsx` | NPC 语音配置 |

## 打表工具

| 文件 | 说明 |
|------|------|
| `_tool/dir_file` | 客户端打表输出路径配置 |
| `_tool/dir_file_server` | 服务器打表输出路径配置 |
| `npc/generate_npc_plot.exe` | NPC 剧情数据生成工具 |

**输出目标**（配置在 `_tool/dir_file`）：

| 变量 | 路径 | 说明 |
|------|------|------|
| `TARGET_CLIENT_CODE` | `Assets/Scripts/Gameplay/Config/Gen` | 客户端 C# 配置代码 |
| `TARGET_CLIENT_BYTES` | `Assets/PackResources/Config/Data` | 客户端配置二进制 |
| `TARGET_SERVER_BYTES` | `P1GoServer/bin/config` | 服务器配置二进制 |
