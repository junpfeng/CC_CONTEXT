# Plan Review 报告

> **版本**: 0.0.2 / V2_NPC
> **Review 日期**: 2026-03-27
> **Plan 路径**: docs/version/0.0.2/V2_NPC/plan/（client.json / server.json / protocol.json / flow.json / testing.json）

---

## 📊 总评

| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ⚠️ 有遗漏 | 2 |
| 边界条件 | ⚠️ 有遗漏 | 3 |
| 协议设计 | ⚠️ 有遗漏 | 2 |
| 服务端设计 | ⚠️ 有遗漏 | 1 |
| 客户端设计 | ⚠️ 有遗漏 | 3 |
| 安全防滥用 | ✅ 完善 | 0 |
| 可测试性 | ⚠️ 有遗漏 | 1 |

**总体评价**：Plan 整体架构完整、迭代深度充分（19 轮），核心机制（WalkZone 配额、circuit breaker、LOD 事件驱动）设计合理；主要风险集中在两个阻塞性问题——行人路网数据构建步骤缺失（REQ-003 系统基础数据）和 LegendType 配置 ID 存在三方冲突，需要在开发前明确解决。

---

## 🔴 必须修复（Critical）

> 不修复会导致功能不可用、数据丢失或安全漏洞

### C1: 行人路网数据构建步骤完全缺失（REQ-003 未覆盖）

- **位置**：flow.json 第 1 节"场景初始化"；server.json BigWorldNpcSpawner
- **问题**：Plan 中 BigWorldNpcSpawner.initSpawnPoints 和 FindPathByType(footwalk) 均假设 footwalk 子路网数据已存在于 JSON 文件中并可直接加载。但 feature.json REQ-003 明确要求**构建**行人路网——从车辆路网派生，沿法线偏移 3-5m 生成 50K+ 路点，标注 roadType=footwalk。Plan 中没有描述：
  1. 构建工具/脚本是什么（一次性离线生成？还是运行时动态计算？）
  2. 生成后的路网文件存放路径（与车辆路网 JSON 并列？单独目录？）
  3. roadType 字段如何写入现有路网格式
- **影响**：footwalk 路网数据缺失时，NPC 生成位置查询返回空，整个 AOI 驱动生成链路完全失效，P0 功能不可用。
- **建议**：在 flow.json 或新增 data-prep.json 中补充"行人路网构建"节点：
  - 明确使用离线脚本（如 Python）处理 bigworld_road.json，按 roadType=vehicle 路网边法线偏移 4m 插值路点
  - 输出文件路径：`bin/config/bigworld_ped_waypoints.json`，格式与车辆路网一致，新增 `"road_type": "footwalk"` 字段
  - 补充数据验证步骤（SV-003/SV-004 脚本可复用）

---

### C2: LegendType 配置表 ID 三方冲突

- **位置**：client.json 小地图图例节；feature.json REQ-013
- **问题**：三个来源给出了不一致的值：
  - `feature.json` REQ-013：`LegendType ID = 127`
  - `plan` 迭代记录（I3/迭代 3）：`LegendType=14`（即 MapLegendType 枚举值，**不是配置表 ID**）
  - 现有代码 `MapLegendControl.cs:1914`：`BigWorldNpcLegendTypeId = 128`

  Plan 中的 "14" 是 C# 枚举 `MapLegendType.BigWorldNpc` 的索引值（正确），但配置表行 ID 究竟是 127 还是 128 两处冲突。
- **影响**：实现时若使用 127，现有代码常量（128）逻辑会失效；若使用 128，与 feature.json 规格不一致可能导致配置表冲突（另一个 ID=127 的图例类型）；无论哪种，小地图 NPC 图例不显示。
- **建议**：
  1. 查阅 `RawTables/` 中 LegendType 配置表，确认 BigWorldNpc 行的实际 ID
  2. 若配置表已有 ID=128 行，更新 feature.json 为 128 并更新常量
  3. 若配置表还未添加该行，选定 ID（建议用 128，与现有代码常量一致）后在 plan 中固化
  4. 在 plan 中明确区分"枚举值=14"和"配置表ID=128（或127）"，避免混淆

---

## 🟡 建议修复（Important）

> 不修复可能导致边界场景 bug 或体验问题

### I1: Circuit Breaker 触发后 NPC 预算无恢复路径

- **位置**：server.json PatrolHandler circuit breaker 节；flow.json 异常处理
- **问题**：AssignFailed=true 的 NPC 保持 Idle 状态等待 30s 自然回收。但 Plan 没有考虑极端情况：如果所有 50 个 NPC 都因路线满员触发 circuit breaker（比如巡逻路线配置数量不足），系统会进入 50 NPC 全部 Idle、0 个行走的僵局，且持续至少 30s。30s 后回收再生成仍然满员，循环死锁。
- **建议**：
  - 增加 AssignFailed NPC 的早退出策略：标记后立即触发 10s 缩短回收（而非等 30s）
  - 或在 AssignFailed 时主动通知 Spawner 暂停该 cfgId 的生成，避免新生成的同类 NPC 继续失败
  - 补充 SV-001 验证：路线总容量 ≥ 1.5x 预算（plan 已有此规则，但未强制在运行时检查）

---

### I2: AppearanceComp 异步加载与 NPC 回收的竞态未处理

- **位置**：client.json BigWorldNpcAppearanceComp 节
- **问题**：Plan 描述了"加载完成时用 MoveComp.CurrentPosition 防止瞬移"，但未指定：NPC 在模型加载期间被回收（Controller.OnClear 调用）时，如何取消正在进行的异步加载任务？若不取消，加载回调执行时访问已被清理的组件会引发 NullReferenceException。
- **建议**：在 AppearanceComp 设计中明确：
  - 使用 CancellationTokenSource（在 OnInit 创建，OnClear 中 Cancel）
  - 加载完成回调开头检查 `ct.IsCancellationRequested`，若已取消直接 Destroy 加载的模型
  - 参考宪法规则：UniTask 异步必须支持取消（feedback_unitask_cancellation）

---

### I3: FsmComp 事件订阅取消时机未明确

- **位置**：client.json BigWorldNpcFsmComp 节
- **问题**：Plan 描述 FsmComp 订阅 `MoveComp.OnMoveModeChanged` 事件，用于 Reduced/Minimal LOD 下缓存行为状态。但 Plan 未明确在 `OnClear` 中 Unsubscribe 该事件。若不取消订阅，Controller 回收后事件仍可能触发，导致访问已清理对象。
- **建议**：在 client.json FsmComp 生命周期节明确补充：
  ```csharp
  public override void OnClear() {
      _moveComp.OnMoveModeChanged -= OnMoveModeChangedHandler; // 必须取消订阅
      // ...
  }
  ```
  并在 testing.json CT-003 生命周期测试中增加验证点：回收后事件不再触发。

---

### I4: 重连时 NpcV2Info 重复推送的客户端处理未定义

- **位置**：protocol.json 重连节；flow.json 场景初始化流程
- **问题**：Plan 说"重连时服务端全量推送 AOI 内所有 NPC 的 NpcV2Info"。但未定义客户端的去重逻辑：如果 EntityId 已存在于 BigWorldNpcManager，是先 OnClear 再重建，还是忽略重复消息？不处理会导致同一 NPC 有两个 Controller 实例，引发双重动画、双重渲染。
- **建议**：在 flow.json 或 client.json 中补充：重连时客户端先调用 `BigWorldNpcManager.ClearAll()`，再处理全量 NpcV2Info；或在 `OnNpcV2Info` 处理中检测已存在的 EntityId 先移除再重建。

---

### I5: WalkZone AABB 膨胀量未指定

- **位置**：server.json WalkZone 配额系统；flow.json AOI 配额驱动生成
- **问题**：Plan 说"point-in-AABB 膨胀判断（无需精确面积）"，但未给出膨胀距离（meters）或系数。膨胀量过大导致相邻分区重叠，同一路点被多个 Zone 统计；膨胀量为 0 会遗漏 AABB 边界路点。
- **建议**：明确膨胀值，如 `aabbExpand = 5f`（meters），并在 npc_zone_quota.json 中加入该字段以便热更。同时在 SV 验证脚本中加入区域路点重叠率检查（建议 < 10%）。

---

## 🟢 可选优化（Nice to have）

### N1: 缺少 NPC 系统监控指标定义

- **建议**：在 testing.json 或 server.json 中列出应新增的监控指标，如：各 Zone 当前活跃 NPC 数、每分钟 spawn/recycle 次数、circuit breaker 触发率、LOD 分布比例（Full/Reduced/Minimal）。这些指标在线上排查 NPC 消失/堆积问题时至关重要。

### N2: 服务器重启后无冷启动限流

- **建议**：服务器重启后，WalkZone 配额系统会在第一个 TickQuota 周期（5s）内尝试生成接近 50 个 NPC，对寻路系统造成瞬时压力。建议在 `scene_impl.go` 初始化时设置 `warmupBatches=5`，前 25s 每个 5s 周期最多生成 10 个 NPC。

### N3: 关键日志事件无示例格式

- **建议**：在 server.json 或 testing.json 中为以下事件给出日志格式示例，避免实现时不统一：
  - NPC spawn：`[BigWorldSpawner] npc_entity_id=xxx npc_cfg_id=xxx zone=downtown patrol_route=xxx`
  - circuit breaker 触发：`[PatrolHandler] circuit_breaker_triggered npc_entity_id=xxx retry=3`
  - NPC recycle：`[BigWorldSpawner] npc_recycled npc_entity_id=xxx reason=aoi_out delay_ms=30000`

---

## 📝 遗漏场景清单

1. **行人路网为空时的降级策略** — 需要在 flow.json 异常处理节补充：如果 footwalk 路网文件加载失败或路点数为 0，Spawner 应记录 Error 日志并完全禁用 NPC 生成（而非静默失效）

2. **多玩家同时在线的配额竞争** — 需要在 server.json WalkZone 配额节补充：当多个玩家 AOI 覆盖同一 Zone 时，配额是否重复计算？建议明确"配额基于 Zone 总预算，与玩家数无关"

3. **NPC 生成位置与玩家重叠** — flow.json 中 NPC spawn 位置选择无最近玩家距离检查，可能在玩家脚边突然出现 NPC，需要补充最小生成距离（如玩家 10m 以外）

4. **巡逻路线节点数为 1 时的循环处理** — server.json PatrolHandler 未描述只有 1 个节点的路线如何处理（理论上到达即出发，是否有最短停留时间保护？）

5. **客户端场景切换时 pending set 残留** — flow.json BigWorldNpcManager.OnSceneUnload 清理了 Controller，但 `_pendingResyncSet` 中等待处理的 EntityId 是否也同步清空？若不清空，进入下个场景后可能触发对无效 EntityId 的处理

---

## ✅ 做得好的地方

1. **Circuit Breaker 设计**（server.json PatrolHandler）：用 AssignFailed 标记 + 5s 防抖 + maxRetry=3 彻底解决了路线满员时的 CPU 螺旋问题，量化分析（1000次/s → 10次/s）给出了具体数据支撑，设计决策清晰。

2. **LOD 事件驱动架构**（client.json FsmComp + MoveComp）：用 `OnMoveModeChanged` 事件 + `_pendingBehaviorState` 缓存取代轮询，精准解决了 Reduced/Minimal LOD 下 FSM 停 Tick 导致状态丢失的问题，是一个优雅的事件驱动解决方案。

3. **多轮迭代的修复溯源**（plan/ 各文件迭代记录）：每个修复点都标注了触发原因（如 C2 加载位置修正源于"加载完成后 NPC 已移动 N 米导致瞬移"），这种"问题→根因→修复"的链路记录极大降低了后续实现时的理解成本。

---

<!-- counts: critical=2 important=5 nice=3 -->
