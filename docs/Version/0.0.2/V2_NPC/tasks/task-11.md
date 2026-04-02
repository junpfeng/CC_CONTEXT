---
name: 集成联调与端到端验证
status: pending
---

## 范围
- 服务端集成: 确保 scene_impl → Spawner → ExtHandler → PatrolRouteManager → Map 全链路初始化正常
- 客户端集成: 确保 BigWorldNpcManager → BigWorldNpcController → 各 Comp 生命周期完整
- 端到端测试: 启动服务器 → 客户端进入大世界 → NPC 自动生成 → 动画表现 → GM 命令 → 小地图图例 → AOI 回收
- 回归测试: 小镇 NPC 不受影响、车辆路网向后兼容、Pipeline 注册隔离

## 验证标准
- 服务端 make build 编译通过
- 客户端 Unity 编译无错误
- 服务器启动日志确认：行人路网加载成功、巡逻路线加载成功、Spawner 就绪
- 玩家进入大世界后 NPC 自动生成在人行道上（非车道）
- NPC Idle/Walk/Run 动画正确切换，移动平滑无瞬移
- GM 命令 `/ke* gm bw_npc spawn/clear/info` 功能正常
- 小地图 NPC 图例 Toggle 功能正常（大世界可见，小镇不可见）
- NPC AOI 回收时资源正确释放（巡逻路线、对象池）
- 小镇场景 NPC 系统不受影响（回归安全）
- NPC 总数不超过 50，分区密度符合 densityWeight 配置

## 依赖
- 依赖 task-01 ~ task-10（全部完成后进行集成）
