---
name: 端到端集成联调
status: completed
---

## 范围
- 修改: 服务端大世界场景启动流程 — 确保 BigWorldNpcSpawner 在场景加载完成后正确初始化（加载路网 → 校验 → TickSpawn 注册）
- 修改: 服务端 SceneImplI 接口 — 新增 GetTrafficManager()/GetTrafficLightState() 方法，BigWorldSceneImpl 完整实现，其他场景（Town/Sakura）返回 nil/Unknown
- 修改: 客户端 BigWorldNpcManager — 在 ManagerCenter 中注册，确保大世界场景加载时自动初始化
- 修改: 客户端网络层 — 确保 NpcDataUpdate 消息正确路由到 BigWorldNpcManager（大世界场景下）
- 新增: 大世界 NPC 情绪组件（P1 预留）：
  - freelifeclient/.../Comp/BigWorldNpcEmotionComp.cs — 情绪表现组件骨架（接收 EmotionData 驱动表情，P0 可为空实现）
- 验证: 完整流程——玩家进入大世界 → NPC 自动生成 → 沿路网移动 → 状态同步到客户端 → 动画播放正确 → 离开 AOI 后回收

## 验证标准
- 服务端 `make build` 编译通过
- 客户端 Unity 编译无 CS 错误
- GM 命令 `/ke* gm bigworld_npc_spawn 5` 能在大世界生成 5 个 NPC
- NPC 沿路网移动，Y 坐标无浮空/穿地（Raycast 修正生效）
- 客户端 NPC 动画状态（Idle/Walk/Run/Turn）与服务端同步一致
- NPC 离开 AOI 后正确回收，无内存泄漏
- 场景切换后 BigWorldNpcManager.OnClear() 无残留实体

## 依赖
- 依赖 task-03（服务端 Spawner + Update System）
- 依赖 task-04（GM 命令）
- 依赖 task-07（客户端 Manager）
