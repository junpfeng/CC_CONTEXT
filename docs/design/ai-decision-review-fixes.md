# AI Decision 系统审查问题修复方案

## 审查时间
2026-02-09

## 审查范围
- `servers/scene_server/internal/common/ai/decision/`
- `servers/scene_server/internal/ecs/system/decision/`

---

## P0 - 严重问题（必须修复）

### P0-1: ExitTask 使用错误名称

**文件**: `servers/scene_server/internal/common/ai/decision/agent/gss.go:251-254`

**问题代码**:
```go
if len(planCfg.ExitTask) != 0 {
    tasks = append(tasks, &decision.Task{
        Name: planCfg.EntryTask,  // 错误：应该是 ExitTask
        Type: decision.TaskTypeGSSExit,
    })
}
```

**影响**: ExitTask 的名称被错误设置为 EntryTask，导致执行器执行错误的任务逻辑。

**修复方案**:
```go
if len(planCfg.ExitTask) != 0 {
    tasks = append(tasks, &decision.Task{
        Name: planCfg.ExitTask,  // 修正为 ExitTask
        Type: decision.TaskTypeGSSExit,
    })
}
```

**修改范围**: 1 行

---

### P0-2: rand.Intn(0) 会 panic

**文件**: `servers/scene_server/internal/common/ai/decision/agent/gss.go:349-367`

**问题代码**:
```go
func (b *gssBrain) choiceTransitionByProbability(trans []*config.Transition) *config.Transition {
    maxNum := 0
    for _, t := range trans {
        maxNum += int(t.Probability)
    }
    randNum := rand.Intn(maxNum)  // maxNum 为 0 时 panic
    // ...
}
```

**影响**: 当所有 transition 的 probability 之和为 0 时，服务器崩溃。

**修复方案**:
```go
func (b *gssBrain) choiceTransitionByProbability(trans []*config.Transition) *config.Transition {
    if len(trans) == 0 {
        return nil
    }

    maxNum := 0
    for _, t := range trans {
        maxNum += int(t.Probability)
    }

    // 概率之和为0时，返回第一个作为默认
    if maxNum <= 0 {
        return trans[0]
    }

    randNum := rand.Intn(maxNum)
    // ... 后续逻辑不变
}
```

**修改范围**: 添加 ~8 行保护代码

---

### P0-3: 空指针导致 panic

**文件**: `servers/scene_server/internal/ecs/system/decision/decision.go:178-180`

**问题代码**:
```go
customerEntity, _ := ds.Scene().GetEntity(targetEntityID)
customerNpcComp, _ := common.GetEntityComponentAs[*cnpc.TownNpcComp](customerEntity, common.ComponentType_TownNpc)
customerNpcCfgId := customerNpcComp.Cfg.GetId()  // 如果上面失败会 panic
```

**影响**: 当目标实体不存在或没有 TownNpcComp 组件时，服务器崩溃。

**修复方案**:
```go
customerEntity, ok := ds.Scene().GetEntity(targetEntityID)
if !ok || customerEntity == nil {
    ds.Warningf("[DecisionSystem][processInTrade] customer entity not found, target_entity_id=%d", targetEntityID)
    tradeComp.PopTarget()
    continue
}

customerNpcComp, ok := common.GetEntityComponentAs[*cnpc.TownNpcComp](customerEntity, common.ComponentType_TownNpc)
if !ok || customerNpcComp == nil {
    ds.Warningf("[DecisionSystem][processInTrade] customer npc comp not found, target_entity_id=%d", targetEntityID)
    tradeComp.PopTarget()
    continue
}

customerNpcCfgId := customerNpcComp.Cfg.GetId()
```

**修改范围**: 添加 ~10 行检查代码

---

### P0-4: Plan 执行缺乏原子性

**文件**: `servers/scene_server/internal/ecs/system/decision/executor.go:28-37`

**问题代码**:
```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    for _, task := range req.Plan.Tasks {
        e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
    }
    return nil
}
```

**影响**: 多个 Task 执行中途失败时，已执行的 Task 无法回滚，NPC 处于中间态。

**修复方案 A - 记录执行状态（推荐，改动小）**:
```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    var executedTasks []string
    for _, task := range req.Plan.Tasks {
        success := e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
        if !success {
            e.Scene.Warningf("[Executor][OnPlanCreated] task failed, entity_id=%d, plan=%s, task=%s, executed=%v",
                req.EntityID, req.Plan.Name, task.Name, executedTasks)
            // 当前不做回滚，但记录日志便于排查
            // 后续可以根据 executedTasks 实现补偿逻辑
            return fmt.Errorf("task %s execution failed", task.Name)
        }
        executedTasks = append(executedTasks, task.Name)
    }
    return nil
}

// executeTask 需要返回 bool 表示是否成功
func (e *Executor) executeTask(...) bool {
    // 现有逻辑改为返回成功/失败
}
```

**修复方案 B - 完整事务支持（改动大，可后续优化）**:
```go
type TaskResult struct {
    TaskName string
    Success  bool
    Rollback func()
}

func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    var results []TaskResult

    for _, task := range req.Plan.Tasks {
        result := e.executeTaskWithRollback(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
        results = append(results, result)

        if !result.Success {
            // 反向执行回滚
            for i := len(results) - 2; i >= 0; i-- {
                if results[i].Rollback != nil {
                    results[i].Rollback()
                }
            }
            return fmt.Errorf("task %s failed, rolled back %d tasks", task.Name, len(results)-1)
        }
    }
    return nil
}
```

**建议**: 先采用方案 A，后续根据实际需求决定是否升级到方案 B。

**修改范围**: 方案 A 约 20 行，方案 B 约 50+ 行

---

### P0-5: 交易队列非原子操作

**文件**: `servers/scene_server/internal/ecs/component/npc/trade_proxy_comp.go:66-94`

**问题代码**:
```go
// PopTarget 原子操作弹出队首元素
func (c *TradeProxyComp) PopTarget() (uint64, bool) {
    if len(c.tradeNpcList) == 0 {
        return 0, false
    }
    target := c.tradeNpcList[0]
    c.tradeNpcList = c.tradeNpcList[1:]  // 非原子，注释不准确
    c.SetSync()
    c.SetSave()
    return target, true
}
```

**影响**: 并发调用时可能导致数据竞争。

**修复方案 - 添加文档说明（保守方案）**:
```go
// PopTarget 弹出队首元素
// 注意：此方法非线程安全，只能在 Scene 主循环（单线程）中调用
// 如需在其他 goroutine 调用，需要外部加锁
func (c *TradeProxyComp) PopTarget() (uint64, bool) {
    // ... 现有逻辑
}
```

**修复方案 - 添加互斥锁（完整方案）**:
```go
type TradeProxyComp struct {
    common.ComponentBase
    mu           sync.Mutex  // 新增
    tradeNpcList []uint64
}

func (c *TradeProxyComp) PopTarget() (uint64, bool) {
    c.mu.Lock()
    defer c.mu.Unlock()

    if len(c.tradeNpcList) == 0 {
        return 0, false
    }
    target := c.tradeNpcList[0]
    c.tradeNpcList = c.tradeNpcList[1:]
    c.SetSync()
    c.SetSave()
    return target, true
}

func (c *TradeProxyComp) AddTradeTarget(npcID uint64) {
    c.mu.Lock()
    defer c.mu.Unlock()

    c.tradeNpcList = append(c.tradeNpcList, npcID)
    c.SetSync()
    c.SetSave()
}
```

**建议**: 如果确认只在 Scene 主循环中调用，采用文档说明方案；否则采用互斥锁方案。

**修改范围**: 文档方案 ~5 行，互斥锁方案 ~15 行

---

### P0-6: Peek-Pop 竞态条件

**文件**: `servers/scene_server/internal/ecs/system/decision/decision.go:111-196`

**问题代码**:
```go
func (ds *DecisionSystem) processInTrade(...) {
    for {
        targetEntityID := tradeComp.PeekTarget()  // Peek
        // ... 验证逻辑 ...
        tradeComp.PopTarget()  // Pop（验证失败时）
        continue
    }
    // ...
    targetEntityID := tradeComp.PeekTarget()  // 再次 Peek，可能和之前不同！
    // ...
    tradeComp.PopTarget()  // 成功后 Pop
}
```

**影响**: Peek 和 Pop 之间如果队列被修改，会处理错误的目标。

**修复方案 - 使用 Pop 代替 Peek**:
```go
func (ds *DecisionSystem) processInTrade(npcComp *cnpc.TownNpcComp, npcEntity common.Entity, tradeComp *cnpc.TradeProxyComp, decisionComp *caidecision.DecisionComp) {
    for {
        // 直接 Pop 获取目标，获取即锁定
        targetEntityID, ok := tradeComp.PopTarget()
        if !ok {
            return // 队列为空
        }

        // 验证目标有效性
        customerEntity, ok := ds.Scene().GetEntity(targetEntityID)
        if !ok || customerEntity == nil {
            ds.Debugf("[DecisionSystem][processInTrade] skip invalid target, target_entity_id=%d", targetEntityID)
            continue // 无效目标，继续处理下一个
        }

        customerNpcComp, ok := common.GetEntityComponentAs[*cnpc.TownNpcComp](customerEntity, common.ComponentType_TownNpc)
        if !ok || customerNpcComp == nil {
            ds.Debugf("[DecisionSystem][processInTrade] skip target without npc comp, target_entity_id=%d", targetEntityID)
            continue
        }

        // 其他验证...
        if !isValidTarget(customerNpcComp) {
            continue
        }

        // 找到有效目标，执行交易
        customerNpcCfgId := customerNpcComp.Cfg.GetId()
        // ... 执行交易逻辑 ...

        break // 处理完成，退出循环
    }
}
```

**修改范围**: 重构约 30 行

---

## P1 - 重要问题（建议修复）

### P1-1: 决策模板切换无事务保护

**文件**: `servers/scene_server/internal/common/ai/decision/agent/gss.go:146-184`

**问题**: `ChangeBrainTemp` 方法中多步骤更新，任一步骤失败会留下部分更新状态。

**修复方案**:
```go
func (b *gssBrain) ChangeBrainTemp(info *decision.BrainInfo) error {
    // 1. 准备阶段：获取新配置和创建新计划
    newCfg, ok := b.cfgMgr.GetConfig(info.GSSTempID)
    if !ok {
        return fmt.Errorf("config not found: %s", info.GSSTempID)
    }

    newPlan, err := b.createInitialPlan(newCfg)
    if err != nil {
        return fmt.Errorf("create initial plan failed: %w", err)
    }

    // 2. 保存旧状态用于回滚
    oldCfg := b.config
    oldPlan := b.curPlan
    oldStep := b.step

    // 3. 提交阶段：原子更新
    b.config = newCfg
    b.curPlan = newPlan

    // 4. FSM 状态切换
    if b.fsm != nil {
        ctx := b.fsm.CreateContext(newPlan, newCfg, b.cfgMgr)
        if err := b.fsm.SetState("WaitConsume", ctx); err != nil {
            // 回滚
            b.config = oldCfg
            b.curPlan = oldPlan
            b.step = oldStep
            return fmt.Errorf("fsm set state failed: %w", err)
        }
        b.setStep(DecisionStepWaitConsume)
    }

    return nil
}
```

**修改范围**: 重构约 25 行

---

### P1-2: curPlan 更新窗口问题

**文件**: `servers/scene_server/internal/common/ai/decision/agent/agent.go:70-100`

**问题**: `OnPlanCreated` 失败时，brain 已切换状态但 agent.curPlan 未更新。

**修复方案**:
```go
func (a *agent) Tick() error {
    if err := a.curBrain.Tick(); err != nil {
        return err
    }

    nextPlan, ok := a.curBrain.GetNextPlan()
    if !ok {
        return nil
    }

    // 先更新 curPlan，再执行
    oldPlan := a.curPlan
    a.curPlan = nextPlan

    if err := a.executer.OnPlanCreated(&decision.OnPlanCreatedReq{
        EntityID: a.entityID,
        Plan:     nextPlan,
    }); err != nil {
        // 执行失败，回滚 curPlan
        a.curPlan = oldPlan
        // 通知 brain 重置状态
        a.curBrain.OnPlanExecutionFailed()
        return err
    }

    return nil
}
```

需要在 Brain 接口添加方法：
```go
type Brain interface {
    // ... 现有方法
    OnPlanExecutionFailed() // 新增：计划执行失败时的回调
}
```

**修改范围**: 约 15 行 + 接口扩展

---

### P1-3: Feature 值无版本控制

**文件**: `servers/scene_server/internal/common/ai/decision/gss_brain/value/value_mgr.go`

**问题**: 并发更新 Feature 值可能导致更新丢失。

**修复方案 - 添加版本号（可选优化）**:
```go
type Value interface {
    GetVersion() int64
    SetWithVersion(v any, expectedVersion int64) (bool, error) // CAS 语义
}

// 使用示例
func (f *feature) UpdateValueCAS(key string, newValue any, expectedVersion int64) error {
    val, ok := f.values.GetValue(key)
    if !ok {
        return ErrKeyNotFound
    }

    success, err := val.SetWithVersion(newValue, expectedVersion)
    if !success {
        return ErrVersionConflict
    }
    return err
}
```

**建议**: 当前场景下 Feature 更新主要在 Scene 主循环中进行，并发冲突概率低。可以先不改，加监控日志观察是否有冲突。

**修改范围**: 暂不修改，添加监控

---

### P1-4: Meeting 状态更新分散

**文件**: `servers/scene_server/internal/ecs/system/npc/npc_update.go:75-191`

**问题**: 组件状态和 feature 更新分散，不原子。

**修复方案 - 封装为原子操作**:
```go
// 在 scheduleComp 或 sensor 中添加统一方法
func (s *ScheduleSensor) UpdateMeetingStateAtomic(scheduleComp *ScheduleComp, newState MeetingState, features map[string]any) error {
    // 1. 更新组件状态
    oldState := scheduleComp.GetMeetingState()
    scheduleComp.SetMeetingState(newState)

    // 2. 更新 features
    for key, value := range features {
        if err := s.UpdateFeature(key, value); err != nil {
            // 回滚组件状态
            scheduleComp.SetMeetingState(oldState)
            return err
        }
    }

    return nil
}
```

**修改范围**: 新增方法约 20 行，调用处修改约 10 行

---

### P1-5: 整数溢出风险

**文件**: `servers/scene_server/internal/common/ai/decision/agent/gss.go:349-357`

**问题**: `int64` 转 `int` 可能溢出。

**修复方案**:
```go
func (b *gssBrain) choiceTransitionByProbability(trans []*config.Transition) *config.Transition {
    if len(trans) == 0 {
        return nil
    }

    var maxNum int64 = 0  // 使用 int64 避免溢出
    for _, t := range trans {
        maxNum += t.Probability
        if maxNum > math.MaxInt32 {
            b.logger.Warningf("probability sum overflow, capped at MaxInt32")
            maxNum = math.MaxInt32
            break
        }
    }

    if maxNum <= 0 {
        return trans[0]
    }

    randNum := rand.Int63n(maxNum)  // 使用 Int63n
    // ... 后续逻辑调整
}
```

**修改范围**: 约 10 行

---

### P1-6: 条件递归无运行时深度检查

**文件**: `servers/scene_server/internal/common/ai/decision/gss_brain/condition/mgr.go:130-170`

**问题**: 虽然配置加载时检查深度，但运行时无限制。

**修复方案**:
```go
const MaxConditionRecursionDepth = 10

func (m *ConditionMgr) ExecuteConditionTree(condition *config.Condition, feat gss.Feature) (gss.CondExecResult, error) {
    return m.executeConditionTreeWithDepth(condition, feat, 0)
}

func (m *ConditionMgr) executeConditionTreeWithDepth(condition *config.Condition, feat gss.Feature, depth int) (gss.CondExecResult, error) {
    if depth > MaxConditionRecursionDepth {
        return gss.CondExeResultFailed, fmt.Errorf("condition recursion depth exceeded: %d", depth)
    }

    // ... 现有逻辑，递归调用时传递 depth+1
    result, err = m.executeConditionTreeWithDepth(item.NestCondition, feat, depth+1)
}
```

**修改范围**: 约 10 行

---

## P2 - 改进建议

### P2-1: 缺乏持久化和崩溃恢复

**问题**: DecisionComp 没有持久化支持，重启后状态丢失。

**修复方案**: 参考 TradeProxyComp 的实现，添加 `ToSaveProto/LoadFromProto` 方法。

**建议**: 后续版本规划，当前优先级低。

---

### P2-2: validPlanNames 硬编码重复

**问题**: 多处重复定义相同的有效 plan 名称 map。

**修复方案**:
```go
// 在 executor.go 顶部定义包级变量
var validIdlePlanNames = map[string]bool{
    "home_idle": true,
    "idle":      true,
    // ...
}

// 各方法中使用
func (e *Executor) executeGSSExitTask(...) {
    if !validIdlePlanNames[plan] {
        // ...
    }
}
```

**修改范围**: 提取常量，修改约 5 处引用

---

### P2-3: 执行结果无返回

**问题**: `handle*Task` 方法返回 void。

**修复方案**: 与 P0-4 一起修复，将返回值改为 `bool` 或 `error`。

---

### P2-4: FSM 状态转换无验证

**问题**: 没有状态转换表验证。

**修复方案**:
```go
var validTransitions = map[string][]string{
    "Init":             {"WaitConsume"},
    "WaitConsume":      {"WaitCreateNotify"},
    "WaitCreateNotify": {"WaitConsume"},
}

func (fsm *GssBrainFSM) SetState(stateName string, ctx *Context) error {
    if allowed, ok := validTransitions[fsm.currentState]; ok {
        if !slices.Contains(allowed, stateName) {
            return fmt.Errorf("invalid transition: %s -> %s", fsm.currentState, stateName)
        }
    }
    // ... 现有逻辑
}
```

**修改范围**: 约 15 行

---

### P2-5: EntityID 类型不一致

**问题**: 部分用 `uint32`，部分用 `uint64`。

**修复方案**: 统一为 `uint64`，这需要较大范围的重构，建议作为技术债务后续处理。

**建议**: 暂不修改，记录为技术债务。

---

### P2-6: 日志可能泄露信息

**问题**: Debug 日志输出大量内部状态。

**修复方案**: 确认生产环境日志级别设置为 Info 或以上，不需要代码修改。

---

## 修复优先级

| 优先级 | 问题编号 | 预计工作量 |
|--------|---------|-----------|
| **立即** | P0-1, P0-2, P0-3 | 各 5-10 分钟 |
| **本周** | P0-4(方案A), P0-5(文档), P0-6 | 各 30 分钟 |
| **下周** | P1-1, P1-2, P1-5, P1-6 | 各 30-60 分钟 |
| **后续** | P1-3, P1-4, P2-* | 根据需求排期 |

---

## 待确认事项

1. **P0-5 (交易队列)**：是否确认只在 Scene 主循环中调用？如果是，采用文档说明方案；否则需要加锁。

2. **P0-4 (Plan 原子性)**：是否需要完整的事务回滚支持（方案 B），还是先采用日志记录方案（方案 A）？

3. **P1-3 (Feature 版本控制)**：当前是否观察到并发更新导致的问题？如果没有，可以暂缓处理。

4. **P2-5 (EntityID 类型)**：是否需要统一？这会涉及较大范围修改。

请 review 后告知哪些需要修改、采用哪种方案。
