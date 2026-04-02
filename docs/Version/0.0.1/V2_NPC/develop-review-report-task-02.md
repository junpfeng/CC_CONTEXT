═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC (task-02: BigWorld Pipeline Handlers)
  版本：0.0.1
  审查文件：5 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未修改 proto/service 生成代码 |
| 错误处理 | ✅ | 所有 error 显式处理，有 log 输出 |
| Actor 独立性 | ⚠️ | 见 [H1] — 全局 map 返回指针在锁外读写 |
| 消息传递 | ✅ | 无跨 Actor 直接数据访问 |
| defer 释放锁 | ✅ | Mutex 锁均用 defer 释放 |
| safego | ✅ | 无新 goroutine 创建 |
| 全局变量 | ⚠️ | `bwNavStates` 全局 map，见 [H1] |
| YAGNI | ✅ | 实现范围与 plan 一致，无过度设计 |
| 单一职责 | ✅ | 每个 Handler 职责清晰 |
| 测试覆盖 | ✅ | 29 个测试覆盖所有 Handler 的 OnEnter/OnTick/OnExit 及边界条件 |

### 客户端

本次 task-02 无客户端文件变更，不适用。

## 二、Plan 完整性

### 已实现
- [x] BigWorldEngagementHandler — AlertLevel 管理、玩家距离检测、滞回设计(15m/20m)
- [x] BigWorldExpressionHandler — 情绪衰减、Neutral/LookAt/React 子 Handler、动画选择
- [x] BigWorldLocomotionHandler — 速度控制(Idle=0/Walk=1.4/Run=3.5)、移动状态管理
- [x] BigWorldNavigationHandler — 地形Y修正3级降级、红绿灯等待、载具避让、30帧无效Y安全despawn
- [x] bigworld_handlers_test.go — 29个单元测试，覆盖主要路径和边界条件
- [x] TerrainAccessor / TrafficAccessor 可选接口解耦
- [x] Per-entity 导航状态管理 + OnExit 清理

### 遗漏（已知 TODO，非遗忘）
- [ ] **A\* 寻路 + LRU 缓存** — plan 要求 LRU 路径缓存(50条)，当前实现委托 Scene API (RoadNet/NavMesh/DirectPath 三级降级)，无独立 LRU 缓存。若 Scene API 内部已有缓存则无问题，否则需补充。
- [ ] **Server AI LOD 分级** — plan 要求 HIGH/MEDIUM/LOW 三级 LOD 影响 tick 频率。当前 Handler 内无 LOD 逻辑，可能由 Pipeline 层(task-01)统一处理。需确认 LOD 职责归属。
- [ ] **ScheduleState 驱动 AlertLevel** — plan 要求 AlertLevel 基于 ScheduleState，当前仅用玩家距离。develop-log 已记录此 TODO。

### 偏差
- `sync.Map` → `map + sync.Mutex`：plan 说用 sync.Map，实际用 map+Mutex。功能等价，Mutex 更适合已知 key 类型场景，可接受。
- 新增 RoadNet→NavMesh→DirectPath 三级寻路降级：plan 未明确要求，但属于合理健壮性设计。

## 三、边界情况

[HIGH] bigworld_navigation_handler.go:61-64 — **全局 map 返回指针在锁外读写，存在 data race 风险**
  场景: Handler 为无状态单例，如果同一 entityID 意外出现在两个 goroutine 中，`getNavEntityState()` 返回的指针在锁外被并发读写（`ns.invalidYFrames++`、`ns.waitingRedLight = true` 等）
  影响: 理论上 Actor 模型保证同一 entity 不会并发，但防御性不足。若未来架构变化可能触发 data race
  建议: 将导航状态移入 PlanContext.NpcState 跟随 Actor 生命周期；或改用 sync.Map + 每次操作持锁

[MEDIUM] bigworld_navigation_handler.go — **30帧 despawn 阈值为硬编码**
  场景: `invalidYFrames > 30` 触发 despawn，帧率不同时实际等待时间不同
  建议: 改为基于时间(秒)而非帧数，或提取为常量并注释帧率假设

## 四、代码质量

[HIGH] bigworld_expression_handler.go:42-50,110-117,143-151 — **情绪衰减逻辑重复 3 次**
  影响: 修改衰减逻辑需改 3 处，容易遗漏
  建议: 抽取为 `decayEmotion(e *state.EmotionState, dt float64)` 工具函数

[MEDIUM] bigworld_expression_handler.go:119 — **`_ = sy` 显式忽略变量**
  影响: 风格问题，constitution 禁止静默忽略
  建议: 改为 `sx, _, sz, ok := ctx.Scene.GetEntityPos(ctx.EntityID)`

[MEDIUM] bigworld_expression_handler.go — **情绪阈值 1.5/0.5 为魔法数字**
  建议: 提取为常量 `bwEmotionFearThreshold` / `bwEmotionSurpriseThreshold`

[MEDIUM] bigworld_engagement_handler.go:39 — **ThreatDistance 语义歧义**
  影响: 若上游日后改为提供距离平方，此处 `ThreatDistance * ThreatDistance` 变为四次方比较
  建议: 在 PerceptionState 定义处明确标注字段单位（线性米），或提供 `ThreatDistanceSq`

[MEDIUM] bigworld_navigation_handler.go:50 — **`bwNavRedLightWaitOffsetRange` 已声明未使用**
  建议: 按 YAGNI 删除，待实际需要时再添加

## 五、总结

  CRITICAL: 0 个
  HIGH:     2 个（必须修复）
  MEDIUM:   4 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. [H1] 全局 nav 状态 map 的指针在锁外读写，需确认 Actor 模型是否绝对保证单线程访问或改用更安全的方案
  2. [H2] 情绪衰减逻辑重复 3 次，违反 DRY 原则，后续维护易出错
  3. Plan 中 3 个功能项（LRU 缓存、AI LOD、ScheduleState AlertLevel）未实现，需确认是否属于其他 task 范围

<!-- counts: critical=0 high=2 medium=4 -->
