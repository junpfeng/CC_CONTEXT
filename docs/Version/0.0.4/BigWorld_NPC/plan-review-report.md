# Plan Review 报告

## 📊 总评

| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ✅ 完善 | 0 |
| 边界条件 | ⚠️ 有遗漏 | 2 |
| 协议设计 | ⚠️ 有遗漏 | 2 |
| 服务端设计 | ⚠️ 有遗漏 | 3 |
| 客户端设计 | ⚠️ 有遗漏 | 1 |
| 安全防滥用 | ✅ 完善 | 0 |
| 可测试性 | ⚠️ 有遗漏 | 1 |

**总体评价**：经过3轮迭代修复，plan整体质量较高，核心架构决策合理；主要风险集中在3个实现级缺失（GameEvent规范、TypeNtf推送时机、LOD迟滞），不修复会在P1阶段产生功能不可用或明显视觉缺陷。

---

## 🔴 必须修复（Critical）

> 不修复会导致功能不可用或体验严重劣化

### C1: BigWorldNpcTypeNtf AOI进入推送机制未定义

- **位置**：protocol.json BigWorldNpcTypeNtf设计、server.json AOI快照逻辑
- **问题**：P1新增了BigWorldNpcTypeNtf消息（entity_id + npc_type），但protocol.json和server.json均未说明该消息何时发送：Spawn时？AOI enter时？还是仅在NPC类型变化时？迭代3修复的AOI快照（C3）只覆盖NpcSyncState字段，没有涵盖TypeNtf。断线重连时是否重推也未定义。
- **影响**：P1多NPC类型功能对新进入AOI区域的玩家完全失效——玩家进入大世界看到的所有NPC类型为默认值（0=Pedestrian），警察/商贩/动物外观错误
- **建议**：在server.json补充：① BigWorldNpcSpawner.Spawn时在NpcSyncState快照之后立即推送TypeNtf；② AOI enter handler中，现有"推送完整NpcSyncState快照"逻辑之后追加推送TypeNtf；③ 断线重连走相同AOI enter路径，自动覆盖

---

### C2: LOD分档边界无迟滞（Hysteresis）阈值

- **位置**：server.json LOD分档决策、client.json BigWorldNpcLodComp距离分档
- **问题**：服务端和客户端均使用硬边界（30m²=900 / 60m²=3600）进行LOD分档，无滞回区间。玩家与NPC距离在边界值附近时：服务端每帧来回切换500ms/1500ms tick频率；客户端来回触发`ForceIdle()`清除残留动画状态。两端均在边界处持续振荡。
- **影响**：生产环境中30m/60m附近所有NPC动画持续闪烁重置（ForceIdle每帧被调用），体验严重劣化；服务端tick调度也随之振荡，增加无效CPU开销
- **建议**：设计滞回区间，在server.json和client.json中同时指定进入/退出双阈值：
  - Near：进入 < 28m（784m²），退出 > 32m（1024m²）
  - Mid：进入 < 58m（3364m²），退出 > 62m（3844m²）
  - Far：默认（Mid退出后）
  服务端LOD决策和客户端LodComp均使用相同双阈值，保持一致

---

### C3: EmotionSystem所依赖的GameEvent类型/参数格式未定义

- **位置**：server.json BigWorldNpcEmotionSystem
- **问题**：server.json只写"监听GameEvent_*"，完全未指定：① 具体事件类型名称（GameEvent_Gunshot? GameEvent_Explosion? GameEvent_Fight?）；② 事件payload结构（触发位置Vector3、影响半径float、强度float）；③ 这些事件是系统已有还是需新建。testing.json中出现"触发枪声事件"但没有对应实现规范。
- **影响**：BigWorldNpcEmotionSystem无法实现——不知道注册哪个事件、事件参数如何解析、AOI影响范围如何从事件中获取。P1情绪系统整体阻塞。
- **建议**：在server.json补充GameEvent清单（至少P1阶段所需）：
  ```
  GameEvent_Gunshot: { position: Vector3, radius: float(50m) } → Scared
  GameEvent_Explosion: { position: Vector3, radius: float(80m) } → Scared（高强度）
  ```
  明确是复用现有事件系统还是新建，明确payload字段名称，以及EmotionSystem如何从payload中提取影响半径

---

## 🟡 建议修复（Important）

> 不修复可能导致边界场景bug或实现偏差

### I1: BtTickSystem在大世界场景的注册代码位置未指定

- **位置**：server.json BtTickSystem设计
- **问题**：plan只说"大世界场景初始化时必须注册，grep搜索Town side注册模式参考"，但未指定具体注册点（哪个文件/哪个方法/哪个System的Init）。大世界和小镇场景初始化结构可能不同。
- **建议**：在server.json指定具体注册点，如：`BigWorldSceneInitSystem.OnStart()` → 调用 `BtTickSystem.Register(sceneId, BigWorldNpcUpdateSystem)`；或在 `BigWorldNpcManager.Init()` 中注册。给出参考小镇注册的文件路径。

---

### I2: V2Brain Plan切换条件表达式未定义

- **位置**：server.json bigworld_npc_brain.json配置设计
- **问题**：plan只说WanderPlan/SchedulePlan/FleePlan三个Plan及"参考Town side格式"，但未给出具体条件表达式。开发者不知道FleePlan的激活条件是判断`emotion_state==Scared`、`mood_level>0`还是`flee_attr_flags&1==1`，三者语义不同且都合理，极易写成不同版本。
- **建议**：在server.json补充bigworld_npc_brain.json示例片段，至少给出FleePlan的activate_condition和deactivate_condition字段示例值，明确使用哪个字段作为判断依据（建议：`emotion_state != 0` 作为情绪类Plan通用激活条件）。

---

### I3: 协议"零新增"约束与P1 BigWorldNpcTypeNtf矛盾

- **位置**：plan.json 关键决策
- **问题**：plan.json关键决策写"协议零新增，复用NpcSyncState"，但P1阶段新增了BigWorldNpcTypeNtf推送消息，形成自相矛盾。未说明"零新增"仅适用于P0。
- **建议**：将关键决策该条修改为："P0协议零新增，仅激活NpcSyncState中已定义的emotion_state/flee_attr_flags等字段；P1新增BigWorldNpcTypeNtf一条推送消息用于多类型支持"。

---

### I4: Far档NPC情绪FleePlan触发最大延迟3000ms未记录为已接受Trade-off

- **位置**：server.json LOD tick频率与EmotionSystem设计
- **问题**：EmotionSystem在GameEvent触发时可以即时写入emotionState，但V2Brain在Far档（>60m）每3000ms才tick一次评估Plan切换。60m外NPC听到枪声最多3秒后才开始逃跑。这个trade-off完全未被文档化。
- **建议**：在server.json中添加设计说明："Far档NPC情绪激活至FleePlan切换延迟最大3000ms，属已接受trade-off（远处NPC表现精度低于近处NPC）"。否则QA会以bug形式报告，浪费排查时间。

---

### I5: 多玩家AOI重叠时NPC档位突变场景未设计

- **位置**：server.json BigWorldNpcUpdateSystem"取最近玩家距离"策略
- **问题**：当玩家A距NPC 25m（Near档）、玩家B距同一NPC 70m（Far档）时，NPC保持Near高频tick。若玩家A突然离开，NPC下一帧立即降至Far档，玩家B可能瞬间看到NPC动画帧率骤降（从500ms更新变为3000ms更新）。
- **建议**：最低要求是记录此场景为已知trade-off；若要优化，可对档位降级增加"连续N次tick都在低档才真正降档"的确认窗口（如连续3次tick在Far才降档），防止玩家频繁进出边界引发NPC频繁升降档。

---

## 🟢 可选优化（Nice to have）

### N1: 缺少GM命令支持情绪调试

- **建议**：在testing.json或server.json中设计专用GM命令，如：`/ke* gm bwnpc_emotion <entity_id> <scared|nervous|curious|angry|none> [duration_sec]`，方便QA不依赖GameEvent_*自然触发就能直接测试各情绪表现。P1-S1目前依赖"GM命令触发枪声事件"，若枪声事件系统本身有bug，情绪测试也会受阻。

### N2: 性能基准指标不够具体

- **建议**：testing.json P1-S5"单帧CPU<2ms"缺少上下文：① 测试机规格；② 是否包含EmotionSystem衰减开销；③ 客户端侧帧率目标。建议补充：服务端 `50 NPC同帧BtTick + LOD计算 < 2ms`（排除网络IO）；客户端 `50 NPC混合LOD渲染帧率 > 30fps（移动端基准机型）`。

### N3: ScheduleIdleState（npc_state=6）客户端动画表现未说明

- **建议**：npc_state=6(ScheduleIdle)是NPC在日程路点等待的状态，regression_checks中确认此状态已存在，但plan未说明其动画预期（复用Idle还是专属等待动画如环顾四周）。建议在client.json中补充说明，避免实现者直接套用Idle动画导致日程等待与普通Idle表现一致、缺乏生活感。

---

## 📝 遗漏场景清单

1. **玩家从小镇切换到大世界** — 需在server.json中说明跨场景AOI初始化是否会正确触发BigWorldNpcTypeNtf推送
2. **NPC移动导致进出玩家AOI（而非玩家移动）** — NPC飘出AOI边界后回来时，服务端是否重新推送TypeNtf快照（与C1相关但场景不同）
3. **同帧多个GameEvent触发** — 已有emotionState=Scared的NPC收到第二个GameEvent_Gunshot时，moodLevel是否重置/累加/取最大值；plan未说明多事件的合并语义
4. **BigWorldNpcTypeCfg的FleeRadius字段实际用途** — plan中存在此字段但正文从未说明它是"触发情绪的范围"还是"逃跑目标距离"；建议在server.json字段注释中明确

---

## ✅ 做得好的地方

1. **迭代3修复系列的严谨性**：AOI快照（C3）、客户端自主计算LOD（I6删除lod_level字段）、npc_state与emotion_state同帧推送（I1）——这三条修复体现出对"客户端无效中间状态"和"Server-Authoritative安全"的深度理解，是防止P1上线后大量视觉bug的关键护盾。

2. **npc_state ↔ emotion_state 语义绑定规则**：明确禁止分帧推送（npc_state和emotion_state必须同帧写入再SetSync），消除了"状态短暂不一致"的整类bug，设计严谨，实现者可直接按规则落地。

3. **服务端自主LOD分档 + 多玩家取最近距离策略**：彻底消除了客户端上报LOD的安全风险，且"取最近玩家距离"保证了近处观看体验优先，在性能与表现之间找到了合理平衡点，是符合Server-Authoritative架构原则的好决策。

---

<!-- counts: critical=3 important=5 nice=3 -->
