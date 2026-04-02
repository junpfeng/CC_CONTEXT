# V2_NPC 未修复 bug

- [ ] 大世界 NPC 密集聚堆（服务端最小间距保护）
  - **现象**：服务端 spawn 系统选点时相邻路网节点间距 0.5-1m，可能在同一路网密集区生成多个 NPC
  - **归因**：需求遗漏 — spawn 系统仅检查与玩家的距离，无 NPC 间最小间距保护；路网 footwalk 节点间距 0.5-1m 导致候选点过密
  - **注意**：客户端密集聚堆（8K+ 幽灵 controller）已通过 despawn 修复解决，此条目指服务端 spawn 选点逻辑

- [x] 大世界NPC持续累积不回收（10125个），导致FPS=2.6、内存6.5GB，且MonsterStandState.OnEnter NullRef导致模型不完整
  - **现象**：进入大世界后NPC随时间持续累积至10000+，地面密密麻麻排列NPC，模型显示不全，场景几乎不可操作
  - **数据**：Monsters=10125, FPS=2.6, MemMB=6588
  - **报错**：MonsterStandState.OnEnter():27 NullReferenceException — _subStateMachine为null（ConfigLoader.NpcMap找不到NpcCreatorId）
  - **怀疑方向**：①服务端持续推送NPC数据客户端只Spawn不Remove ②MonsterStandState.OnInit配置缺失导致初始化失败模型不完整

