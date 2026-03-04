# 任务清单：行为树系统支持小镇和樱花校园 NPC

**文档版本**: v1.0
**创建日期**: 2026-02-25
**需求文档**: `requirements/bt-town-sakura-compatibility.md`
**设计文档**: `design-bt-town-sakura-compatibility.md`

---

## 任务概览

| 阶段 | 任务数 | 预估代码量 | 状态 |
|------|--------|-----------|------|
| 阶段 A：基础设施搭建 | 3 | ~190 行 | ⏳ 待开始 |
| 阶段 B：BtContext 能力注册机制 | 3 | ~100 行 | ⏳ 待开始 |
| 阶段 C：节点重构 | 4 | ~60 行 | ⏳ 待开始 |
| 阶段 D：测试与验证 | 3 | ~150 行 | ⏳ 待开始 |
| **总计** | **13** | **~500 行** | - |

---

## 阶段 A：基础设施搭建

### [TASK-001] 创建能力接口包

**优先级**: P0（最高）
**预估时间**: 30 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/capability/capability.go`

**任务内容**：
- [ ] 创建 `capability` 包目录
- [ ] 定义 `PositionInitializer` 接口
  ```go
  type PositionInitializer interface {
      GetInitialPosition() (common.Vector3, bool)
  }
  ```
- [ ] 定义 `IdleBehaviorProvider` 接口
  ```go
  type IdleBehaviorProvider interface {
      SetOutDurationTime(duration int64)
  }
  ```
- [ ] 添加包注释和必要的 import

**验收标准**：
- [ ] 文件创建成功，路径正确
- [ ] 接口方法签名正确
- [ ] 包可以被其他模块 import（测试：在其他包 import 不报错）
- [ ] 代码通过 `go build`

**依赖**：无

**预估代码量**：~50 行

---

### [TASK-002] 创建适配器包（小镇）

**优先级**: P1（高）
**预估时间**: 45 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/adapters/town_adapter.go`

**任务内容**：
- [ ] 创建 `adapters` 包目录
- [ ] 实现 `TownPositionInitializer` 结构体
  ```go
  type TownPositionInitializer struct {
      npcCfgId int32
      townMgr  *town.TownNpcMgr
  }
  ```
- [ ] 实现 `GetInitialPosition()` 方法
  - 优先从 `townMgr.GetSavedPosition(npcCfgId)` 获取
  - 回退到 `config.GetCfgTownNpcById(npcCfgId).DefaultPos`
- [ ] 实现 `TownIdleBehaviorProvider` 结构体
  ```go
  type TownIdleBehaviorProvider struct {
      comp *cnpc.TownNpcComp
  }
  ```
- [ ] 实现 `SetOutDurationTime()` 方法（委托给 TownNpcComp）
- [ ] 添加接口实现验证
  ```go
  var _ capability.PositionInitializer = (*TownPositionInitializer)(nil)
  var _ capability.IdleBehaviorProvider = (*TownIdleBehaviorProvider)(nil)
  ```

**验收标准**：
- [ ] TownPositionInitializer 实现 PositionInitializer 接口
- [ ] 位置获取逻辑：保存位置 > 配置位置
- [ ] TownIdleBehaviorProvider 实现 IdleBehaviorProvider 接口
- [ ] 接口验证编译通过
- [ ] 代码通过 `go build`

**依赖**：TASK-001

**预估代码量**：~80 行

---

### [TASK-003] 创建适配器包（樱校）

**优先级**: P1（高）
**预估时间**: 30 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/adapters/sakura_adapter.go`

**任务内容**：
- [ ] 实现 `SakuraPositionInitializer` 结构体
  ```go
  type SakuraPositionInitializer struct {
      npcCfgId int32
  }
  ```
- [ ] 实现 `GetInitialPosition()` 方法
  - 返回硬编码原点 `Vector3{X: 0, Y: 0, Z: 0}, true`
- [ ] 实现 `SakuraIdleBehaviorProvider` 结构体
  ```go
  type SakuraIdleBehaviorProvider struct {
      comp *cnpc.SakuraNpcComp
  }
  ```
- [ ] 实现 `SetOutDurationTime()` 方法（委托给 SakuraNpcComp）
- [ ] 添加接口实现验证

**验收标准**：
- [ ] SakuraPositionInitializer 返回 (0,0,0)
- [ ] SakuraIdleBehaviorProvider 委托给 SakuraNpcComp
- [ ] 接口验证编译通过
- [ ] 代码通过 `go build`

**依赖**：TASK-001

**预估代码量**：~60 行

---

## 阶段 B：BtContext 能力注册机制

### [TASK-004] 修改 BtContext 数据结构

**优先级**: P0（最高）
**预估时间**: 15 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/context/context.go`

**任务内容**：
- [ ] 删除 `policeComp component.IComponent` 字段
- [ ] 添加 `capabilities map[reflect.Type]interface{}` 字段
- [ ] 修改 `Reset()` 方法
  - 删除 `ctx.policeComp = nil` 行
  - 添加 `ctx.capabilities = nil` 行

**验收标准**：
- [ ] policeComp 字段已删除
- [ ] capabilities 字段已添加
- [ ] Reset() 方法更新正确
- [ ] 代码通过 `go build`

**依赖**：无

**预估代码量**：~10 行修改

---

### [TASK-005] 实现能力查询 API

**优先级**: P0（最高）
**预估时间**: 30 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/context/context.go`

**任务内容**：
- [ ] 实现 `GetCapability()` 方法
  ```go
  func (ctx *BtContext) GetCapability(capabilityType interface{}) (interface{}, bool) {
      if ctx.capabilities == nil {
          return nil, false
      }
      t := reflect.TypeOf(capabilityType).Elem()
      cap, exists := ctx.capabilities[t]
      return cap, exists
  }
  ```
- [ ] 实现 `GetCapabilityAs[T]()` 泛型方法
  ```go
  func GetCapabilityAs[T any](ctx *BtContext) (T, bool) {
      var zero T
      cap, exists := ctx.GetCapability((*T)(nil))
      if !exists {
          return zero, false
      }
      typed, ok := cap.(T)
      return typed, ok
  }
  ```
- [ ] 实现 `registerCapability()` 私有方法
  ```go
  func (ctx *BtContext) registerCapability(capabilityType interface{}, adapter interface{}) {
      if ctx.capabilities == nil {
          ctx.capabilities = make(map[reflect.Type]interface{})
      }
      t := reflect.TypeOf(capabilityType).Elem()
      ctx.capabilities[t] = adapter
  }
  ```

**验收标准**：
- [ ] GetCapability 返回 (interface{}, bool)
- [ ] GetCapabilityAs 支持泛型查询
- [ ] registerCapability 使用 reflect.Type 作为 key
- [ ] 代码通过 `go build`

**依赖**：TASK-004

**预估代码量**：~30 行

---

### [TASK-006] 实现能力注册逻辑

**优先级**: P1（高）
**预估时间**: 60 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/context/context.go`

**任务内容**：
- [ ] 实现 `registerCapabilities()` 方法（场景检测）
  ```go
  func (ctx *BtContext) registerCapabilities() {
      scene := ctx.Scene()
      if scene == nil { return }

      sceneInfo := scene.GetSceneInfo()
      switch sceneInfo.(type) {
      case *common.TownSceneInfo:
          ctx.registerTownCapabilities(ctx.Entity(), scene)
      case *common.SakuraSceneInfo:
          ctx.registerSakuraCapabilities(ctx.Entity(), scene)
      }
  }
  ```
- [ ] 实现 `registerTownCapabilities()` 方法
  - 注册 TownPositionInitializer
  - 注册 TownIdleBehaviorProvider
- [ ] 实现 `registerSakuraCapabilities()` 方法
  - 注册 SakuraPositionInitializer
  - 注册 SakuraIdleBehaviorProvider
- [ ] 在 `Reset()` 方法末尾调用 `ctx.registerCapabilities()`

**验收标准**：
- [ ] 小镇场景正确注册小镇适配器
- [ ] 樱校场景正确注册樱校适配器
- [ ] Reset() 调用 registerCapabilities()
- [ ] 代码通过 `go build`

**依赖**：TASK-002, TASK-003, TASK-005

**预估代码量**：~60 行

---

## 阶段 C：节点重构

### [TASK-007] 重构 IdleBehavior 节点

**优先级**: P2（中）
**预估时间**: 30 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/nodes/behavior_nodes.go`

**任务内容**：
- [ ] 定位 `IdleBehavior.OnEnter()` 方法
- [ ] 删除以下代码：
  ```go
  townNpcComp, ok := component.GetComponentAs[*cnpc.TownNpcComp](
      ctx.Entity(), component.ComponentType_TownNpc)
  if !ok {
      return node.BtNodeStatusFailed
  }
  townNpcComp.SetOutDurationTime(n.duration)
  ```
- [ ] 替换为能力接口调用：
  ```go
  if idleProvider, ok := context.GetCapabilityAs[capability.IdleBehaviorProvider](ctx); ok {
      idleProvider.SetOutDurationTime(n.duration)
  }
  // 注意：能力不存在时不失败，继续执行
  ```

**验收标准**：
- [ ] 不再直接访问 TownNpcComp
- [ ] 使用能力接口查询
- [ ] 能力缺失时不阻塞流程
- [ ] 代码通过 `go build`

**依赖**：TASK-006

**预估代码量**：~15 行修改

---

### [TASK-008] 重构 SetInitialPositionNode 节点

**优先级**: P2（中）
**预估时间**: 45 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/nodes/init_position.go`

**任务内容**：
- [ ] 定位 `SetInitialPositionNode.OnEnter()` 方法
- [ ] 删除以下代码：
  ```go
  townNpcMgr, ok := GetResourceAs[*town.TownNpcMgr](scene)
  if !ok { return node.BtNodeStatusFailed }

  pos := townNpcMgr.GetSavedPosition(npcCfgId)
  if pos == nil {
      npcCfg := config.GetCfgTownNpcById(npcCfgId)
      pos = &Vector3{...}
  }
  ```
- [ ] 替换为能力接口调用：
  ```go
  posInit, ok := context.GetCapabilityAs[capability.PositionInitializer](ctx)
  if !ok {
      ctx.Error("[SetInitialPosition] NPC lacks PositionInitializer capability")
      return node.BtNodeStatusFailed
  }

  initialPos, hasPos := posInit.GetInitialPosition()
  if !hasPos {
      ctx.Error("[SetInitialPosition] Failed to get initial position")
      return node.BtNodeStatusFailed
  }

  transformComp := ctx.GetTransformComp()
  if transformComp == nil {
      return node.BtNodeStatusFailed
  }
  transformComp.SetPosition(initialPos)
  ```

**验收标准**：
- [ ] 不再直接访问 TownNpcMgr
- [ ] 不再直接调用 GetCfgTownNpcById()
- [ ] 使用能力接口查询位置
- [ ] 代码通过 `go build`

**依赖**：TASK-006

**预估代码量**：~25 行修改

---

### [TASK-009] 重构 SetTownNpcOutDurationNode 节点

**优先级**: P2（中）
**预估时间**: 30 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/nodes/dialog.go`

**任务内容**：
- [ ] 重命名结构体：`SetTownNpcOutDurationNode` → `SetNpcOutDurationNode`
- [ ] 修改 `OnEnter()` 方法：
  ```go
  duration := ctx.GetBlackboardInt64(n.durationKey)

  if idleProvider, ok := context.GetCapabilityAs[capability.IdleBehaviorProvider](ctx); ok {
      idleProvider.SetOutDurationTime(duration)
      return node.BtNodeStatusSuccess
  }

  ctx.Debug("[SetNpcOutDuration] NPC lacks IdleBehaviorProvider, skipping")
  return node.BtNodeStatusSuccess
  ```
- [ ] 更新所有相关的函数名、注释

**验收标准**：
- [ ] 节点改名为 SetNpcOutDurationNode
- [ ] 使用能力接口
- [ ] 能力缺失时返回 Success（不阻塞）
- [ ] 代码通过 `go build`

**依赖**：TASK-006

**预估代码量**：~15 行修改

---

### [TASK-010] 更新节点工厂注册

**优先级**: P3（低）
**预估时间**: 15 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/nodes/factory.go`

**任务内容**：
- [ ] 找到节点工厂注册位置
- [ ] 更新 SetNpcOutDurationNode 的注册：
  ```go
  factory.Register("SetNpcOutDurationNode", createSetNpcOutDurationNode)
  ```
- [ ] 添加别名注册（保持 JSON 兼容）：
  ```go
  factory.Register("SetTownNpcOutDurationNode", createSetNpcOutDurationNode)
  ```
- [ ] 更新 `createSetNpcOutDurationNode` 工厂函数

**验收标准**：
- [ ] SetNpcOutDurationNode 注册成功
- [ ] SetTownNpcOutDurationNode 别名指向同一工厂
- [ ] 现有 JSON 配置无需修改
- [ ] 代码通过 `go build`

**依赖**：TASK-009

**预估代码量**：~5 行修改

---

## 阶段 D：测试与验证

### [TASK-011] 新增樱校 NPC 集成测试

**优先级**: P3（低）
**预估时间**: 90 分钟
**文件**: `servers/scene_server/internal/common/ai/bt/sakura_integration_test.go`（新建）

**任务内容**：
- [ ] 创建樱校场景测试环境
  - 创建 SakuraSceneInfo
  - 添加 SakuraNpcMgr 资源
  - 创建樱校 NPC Entity
  - 添加 SakuraNpcComp 和 SakuraNpcControlComp
- [ ] 测试用例 1：`TestSakuraNpc_InitTree`
  - 加载 `init.json` 行为树
  - 验证 SetInitialPositionNode 返回 (0,0,0)
- [ ] 测试用例 2：`TestSakuraNpc_DailyScheduleTree`
  - 加载 `daily_schedule.json` 行为树
  - 验证 IdleBehavior 正确调用 SetOutDurationTime()
- [ ] 测试用例 3：`TestSakuraNpc_DialogTree`
  - 加载 `dialog.json` 行为树
  - 验证对话行为正常
- [ ] 测试用例 4：`TestSakuraNpc_CapabilityRegistration`
  - 验证樱校场景能正确注册 SakuraPositionInitializer
  - 验证樱校场景能正确注册 SakuraIdleBehaviorProvider

**验收标准**：
- [ ] 樱校 NPC 能成功加载共享行为树
- [ ] SetInitialPositionNode 返回 (0,0,0)
- [ ] IdleBehavior 正确设置 outDurationTime
- [ ] 所有测试用例通过

**依赖**：TASK-007, TASK-008, TASK-009

**预估代码量**：~150 行

---

### [TASK-012] 小镇 NPC 回归测试

**优先级**: P3（低）
**预估时间**: 60 分钟
**文件**: 现有测试文件 + 验证工作

**任务内容**：
- [ ] 运行所有现有单元测试：`go test ./servers/scene_server/internal/common/ai/bt/...`
- [ ] 运行小镇 NPC 集成测试（如有）
- [ ] 验证以下关键行为：
  - Dan NPC 初始化位置正确
  - Customer NPC 空闲行为正确
  - Dealer NPC 日常调度正确
  - Blackman NPC 警察执法逻辑正确
- [ ] 对比重构前后的日志输出（确保逻辑等价）

**验收标准**：
- [ ] 所有现有单元测试通过
- [ ] 小镇 NPC 行为与重构前完全一致
- [ ] 位置初始化逻辑等价（保存位置 > 配置位置）
- [ ] 外出时长设置逻辑等价

**依赖**：TASK-007, TASK-008, TASK-009

**预估代码量**：验证工作，无新增代码

---

### [TASK-013] 构建验证

**优先级**: P3（低）
**预估时间**: 30 分钟
**文件**: 无

**任务内容**：
- [ ] 执行 `make build`
  - 验证所有服务器构建成功
  - 检查编译警告
- [ ] 执行 `make lint`
  - 验证代码风格检查通过
  - 修复任何 lint 错误
- [ ] 执行 `make test`
  - 验证所有测试通过
  - 检查测试覆盖率
- [ ] 生成测试报告

**验收标准**：
- [ ] `make build` 无错误
- [ ] `make lint` 通过
- [ ] `make test` 全部通过
- [ ] 无回归问题

**依赖**：TASK-011, TASK-012

**预估代码量**：无

---

## 任务执行策略

### 并行执行建议

**第 1 批（可并行）**：
- TASK-001（能力接口）
- TASK-004（BtContext 数据结构）

**第 2 批（可并行，依赖第 1 批）**：
- TASK-002（小镇适配器）
- TASK-003（樱校适配器）
- TASK-005（能力查询 API）

**第 3 批（串行，依赖第 2 批）**：
- TASK-006（能力注册逻辑）

**第 4 批（可并行，依赖第 3 批）**：
- TASK-007（IdleBehavior 重构）
- TASK-008（SetInitialPositionNode 重构）
- TASK-009（SetNpcOutDurationNode 重构）

**第 5 批（串行，依赖第 4 批）**：
- TASK-010（工厂注册）

**第 6 批（可并行，依赖第 5 批）**：
- TASK-011（樱校测试）
- TASK-012（小镇测试）

**第 7 批（串行，依赖第 6 批）**：
- TASK-013（构建验证）

---

## 风险与缓解

| 风险 | 相关任务 | 缓解措施 |
|------|---------|---------|
| **能力接口设计不当** | TASK-001 | 先实现最小接口，后续可扩展 |
| **BtContext 修改破坏现有逻辑** | TASK-004-006 | 仔细审查 Reset() 调用链，保留原有组件缓存 |
| **节点重构破坏小镇 NPC** | TASK-007-009 | TASK-012 完整回归测试 |
| **樱校测试环境搭建困难** | TASK-011 | 参考现有小镇测试代码模式 |

---

## 进度追踪

| 阶段 | 完成任务 | 总任务 | 进度 |
|------|---------|--------|------|
| 阶段 A | 0 | 3 | 0% |
| 阶段 B | 0 | 3 | 0% |
| 阶段 C | 0 | 4 | 0% |
| 阶段 D | 0 | 3 | 0% |
| **总计** | **0** | **13** | **0%** |

---

**文档状态**: ✅ 待执行
**下一步**: Phase 4 实现
