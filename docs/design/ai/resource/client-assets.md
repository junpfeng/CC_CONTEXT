# 客户端 NPC 美术资源

> 路径相对于 `freelifeclient/`

## 1. NPC 模型 Prefab

### 基础模型

| 文件 | 说明 |
|------|------|
| `Assets/ArtResources/Character/Human/TO_Zhouhan/BaseCharacter_Male_NPC_Prefab.prefab` | 男性 NPC 基础模型 |
| `Assets/ArtResources/Character/Human/TO_Zhouhan/BaseCharacter_Male_NPC_Prefab002.prefab` | 男性 NPC 基础模型变体 2 |
| `Assets/ArtResources/Character/Human/TO_Zhouhan/BaseCharacter_Male_NPC_Prefab003.prefab` | 男性 NPC 基础模型变体 3 |
| `Assets/ArtResources/Character/Human/TO_Zhouhan/BaseCharacter_Male_NPC_Prefab004.prefab` | 男性 NPC 基础模型变体 4 |
| `Assets/ArtResources/Character/Human/TO_Zhouhan/FeMale_NPC_001.prefab` ~ `FeMale_NPC_007.prefab` | 女性 NPC 模型（7 个） |
| `Assets/ArtResources/Character/Human/TO_Zhouhan/Male_NPC_001.prefab` ~ `Male_NPC_007.prefab` | 男性 NPC 模型（7 个） |

### 合并模型（Merged）

| 文件 | 说明 |
|------|------|
| `Assets/ArtResources/Character/NPC/Merged/Prefab/FeMale_NPC_002(Clone)_merged.prefab` ~ `FeMale_NPC_007(Clone)_merged.prefab` | 女性合并模型（6 个，002~007） |
| `Assets/ArtResources/Character/NPC/Merged/Prefab/Male_NPC_001(Clone)_merged.prefab` | 男性合并模型 001 |
| `Assets/ArtResources/Character/NPC/Merged/Prefab/Male_NPC_003(Clone)_merged.prefab` ~ `Male_NPC_007(Clone)_merged.prefab` | 男性合并模型（5 个，003~007，无 002） |

### 行人 Prefab（Gameflow）

| 文件 | 说明 |
|------|------|
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Level/Factories/NpcEntityPhysicsShapeFactory.prefab` | NPC 物理碰撞工厂 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Base/NpcBase.prefab` | NPC 基础实体 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Base/NpcBase InCar.prefab` | NPC 车内实体 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Outside/NpcBase outside.prefab` | NPC 室外基础 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Outside/NpcMonoBase outside.prefab` | NPC Mono 室外基础 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Outside/NpcPhysicsShape.prefab` | NPC 物理碰撞体 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Outside/PlayerMobNpcEntity.prefab` | 玩家随从 NPC |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Outside/PlayerNpcEntity.prefab` | 玩家 NPC 实体 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Mates/Outside/PoliceNpcEntity.prefab` | 警察 NPC 实体 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Pedestrians/Base/NpcHybridShape.prefab` | 行人混合碰撞体 |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Pedestrians/Mono/Character1.prefab` ~ `Character8.prefab` | 行人 Mono 模型（8 个） |
| `Assets/ArtResources/Temp/Prefabs/Gameflow/Pedestrians/New/Character1.prefab` ~ `Character8.prefab` | 行人新模型（8 个） |

### 打包 Prefab

| 文件 | 说明 |
|------|------|
| `Assets/PackResources/Prefab/Character/Base/BaseCharacter.prefab` | 角色基础 Prefab |
| `Assets/PackResources/Prefab/Character/Base/BaseMale.prefab` | 男性基础 Prefab |
| `Assets/PackResources/Prefab/Character/Base/DressUpRole.prefab` | 换装角色 |
| `Assets/PackResources/Prefab/Character/Clothing/ShopNPC_male.prefab` | 商店男性 NPC |
| `Assets/PackResources/Prefab/Character/Npc/BaseCharacter_Male.prefab` | NPC 男性基础 |
| `Assets/PackResources/Prefab/Character/Npc/MiPedestrian.prefab` | 行人基础 |
| `Assets/PackResources/Prefab/Character/Npc/MiPedestrian_001.prefab` ~ `MiPedestrian_009.prefab` | 行人变体（9 个） |
| `Assets/PackResources/Prefab/Character/Npc/NpcPrefab.prefab` | NPC Prefab（男性） |
| `Assets/PackResources/Prefab/Character/Npc/NpcPrefab_Female.prefab` | NPC Prefab（女性） |
| `Assets/PackResources/Prefab/Character/Npc/NewNpcPrefab.prefab` | 新版 NPC Prefab（男性） |
| `Assets/PackResources/Prefab/Character/Npc/NewNpcPrefab_Female.prefab` | 新版 NPC Prefab（女性） |
| `Assets/PackResources/Prefab/Character/Npc/SUSANOO.prefab` | SUSANOO 特殊 NPC |

### 特殊 Prefab

| 文件 | 说明 |
|------|------|
| `Assets/ArtResources/Timeline/GameTimeline/Transition/NPCRawPrefab.prefab` | NPC 原始 Prefab（Timeline 用） |
| `Assets/ArtResources/Timeline/GameTimeline/Transition/RandomNPCRawPrefab.prefab` | 随机 NPC Prefab（Timeline 用） |

## 2. 动画资源

### 动画控制器

| 文件 | 说明 |
|------|------|
| `Assets/ArtResources/Character/NPC/Merged/NPCTest.controller` | NPC 测试动画控制器 |

### 动画片段

**目录**: `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/`

共 270 个 `.anim` 文件，按子目录分布：

| 子目录 | 完整路径前缀 | 文件数 | 说明 |
|--------|------------|--------|------|
| `Amb_Female/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Amb_Female/` | 58 | 女性环境动画（坐姿、站姿、看手机、聊天等） |
| `Amb_male/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Amb_male/` | 45 | 男性环境动画 |
| `Cover/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Cover/` | 38 | 掩体动画 |
| `Interact/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Interact/` | 61 | 互动动画（开火、风铃等） |
| `Move/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Move/` | 29 | 移动动画（行走、跑步） |
| `Reaction/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Reaction/` | 35 | 反应动画（逃跑、推搡、躲避） |
| `Idle/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Idle/` | 3 | 待机动画 |
| `Grenade/` | `Assets/ArtResources/Animation/Human/Clip/StandardCharacter/NPCs/Grenade/` | 1 | 手雷动画 |

## 3. 音频资源

NPC 语音由配置表引用（见 [excel-tables.md](excel-tables.md) 第 4 节音频配表）：
- `RawTables/audio/AudioNPCdialogue.xlsx` — NPC 对话音频映射
- `RawTables/audio/AudioNPCDlg.xlsx` — NPC 对话语音映射
- `RawTables/audio/NPCVoice.xlsx` — NPC 语音配置
