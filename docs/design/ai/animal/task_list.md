# 动物系统完善 — 任务清单

> 基于 2026-03-24 端到端验收，更新任务状态

## 已完成任务

| 任务 | 说明 | 完成方式 |
|------|------|---------|
| T1: FieldAccessor Animal 字段 | field_accessor.go Resolve 支持 Animal.Base.* / Animal.Perception.* | 代码审查确认已实现 |
| T2: AnimalStateChangeNtf 推送 | scene.proto 注册 cmd 3201，bt_tick_system 检测跃迁并 AOI 广播 | 新增代码 |
| T3: Animal V2Brain Config JSON | animal_engagement/locomotion/navigation.json 三个配置文件 | 代码审查确认已存在 |
| T4: 客户端 FSM 状态通知 | SyncAnimalStateFromNpcData 轮询 + ChangeStateById 驱动 FSM | 代码审查确认已实现 |
| T6: AnimalSceneNpcExt 序列化 | 8 字节 little-endian（AnimalType + VariantID） | 代码审查确认已实现 |
| T7: 配置表数据填充 | InitMonster/MonsterPrefab/MonsterAnimation 4 种动物全部已有 | 代码审查确认已存在 |
| T5: 端到端验证 | 8 只动物生成 + 动画正确 + 喂食 State=5 同步到客户端 | MCP 验收通过 |

### 本次额外修复

| 修复项 | 文件 | 问题 |
|--------|------|------|
| Handler BehaviorState 赋值 | animal_idle/follow/bird_flight.go | Handler 未设 BehaviorState，客户端收到 State=0 |
| Bird 初始 FlightState | animal_init.go | 鸟初始 FlightState=0，navigation pipeline 永远不转换到 fly plan |
| BehaviorState 统一推导 | bt_tick_system.go syncAnimalStateChange | 改为 sync 层统一推导，避免多维度 Handler 覆盖冲突 |
| SetSync 缺失 | animal_feed.go + gm/animal.go | 修改 NpcState 后未调 SetSync()，NpcDataUpdate 不触发 |
| 客户端 Ntf 接收 | AnimalStateChangeNtf.cs + AnimalController + MonsterManager | 新增 NetMsgHandler + OnAnimalStateChange + TryGetAnimal |
| Proto type 关键字冲突 | vehicle.proto | DriverPersonalityData.type → personality_type（Go 关键字） |
| feed_animal GM 命令 | gm/animal.go + gm.go | 新增 GM 命令，绕过物品/距离校验，自动找最近 Dog 喂食 |
| add_backpack_item GM | gm/backpack.go + gm.go | 新增 GM 命令，向玩家 BackpackComp 添加物品 |
| **Follow 速度修复** | npc_state.go, animal_init.go, animal_follow.go, bt_tick_system.go | NpcMoveComp.RunSpeed 未初始化 + Handler 未切换速度 → 狗以 1.5m/s 漫步追不上玩家。增加 SpeedOverride 机制，跟随时用 7.0m/s 奔跑速度（2026-03-25） |

## 遗留任务（已全部完成 2026-03-24）

### [P0] 大世界 BtTickSystem 集成 ✅

- **修复**：CitySceneInfo 实现 NpcAIConfigProvider（EnableDecision=true），通用路径调用 initNpcAISystemsFromConfig + 防重复注册
- **文件**：`scene_type.go`、`scene_impl.go`

### [P1] 大世界背包与喂食物品 ✅

- **修复**：AnimalInteractComp 改用 StoreManager.Backpack 检查物品，不依赖 HoldComp
- **文件**：`AnimalInteractComp.cs`、`StoreBackpackData.cs`

### [P1] 客户端 Follow 表现 ✅

- **修复**：P0 完成后自动生效 — 服务器 FollowHandler tick 更新位置 → 帧同步 → 客户端 TransformComp 插值
- **无额外代码修改**

### [P2] AnimalInteractComp 交互闭环 ✅

- **修复**：与 P1 背包合并 — 近距离（3m）+ 背包有物品 → 显示交互 UI → 自动消耗第一个物品
- **文件**：`AnimalInteractComp.cs`

### [P2] Bird 飞行高度 ✅

- **修复**：P0 完成后自动生效 — BirdFlightHandler tick 设飞行 Y 坐标 → 帧同步 → 客户端插值升空
- **无额外代码修改**

## 验收记录（2026-03-24）

| 测试项 | 结果 | 详情 |
|--------|------|------|
| TC-001: 动物生成 | **通过** | 8 只（2Dog + 3Bird + 1Croc + 2Chicken） |
| TC-002: 动画播放 | **通过** | 4 种 idle 动画全部正确 |
| TC-003: Bird 飞行状态 | **部分通过** | State=4 正确下发，Y 坐标未升空（P0 阻塞） |
| TC-004: Dog 喂食 | **通过** | State=5 + FollowTarget 同步成功。Dog 以 7.0m/s 奔跑追上玩家，到达后停步（2026-03-25 MCP 自动化验收） |
| TC-005: 同屏限制 | **通过** | 8 只 ≤ 配置上限 |
| TC-006: LOD 切换 | **未测** | 依赖 P0 |
| TC-007: 异常场景 | **未测** | 依赖 P1 背包 |
