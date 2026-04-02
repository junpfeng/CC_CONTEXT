# V2 NPC 路网寻路失效：资源初始化时序 Bug

**日期**: 2026-03-16
**影响范围**: 小镇场景所有 V2 NPC 日程移动
**表现**: NPC 从起点到终点穿墙直线移动，不沿路网行走
**根因**: `initRoadNetwork()` 在 V2 管线初始化之后执行，导致 `ScheduleHandler.roadNetMgr` 永远为 nil

## 问题链路

### 错误的初始化时序（修复前）

```
scene_impl.go init():
  107: switch sceneType
  108:   case TownSceneInfo:
  124:     townRosurceInit(saveInfo)
              └─ 241: if UseSceneNpcArch == 1
                  255: GetResourceAs[RoadNetworkMgr] → nil ❌（路网还没加载）
                  259: InitLocomotionManagers(..., nil)
                       └─ ScheduleHandler.roadNetMgr = nil
  174: initRoadNetwork()  ← 路网在这里才加载，太晚了
```

### 运行时后果

```go
// schedule_handlers.go:156
case 1: // MoveTo
    if h.roadNetMgr != nil && ...  // 永远 false，因为 roadNetMgr 在初始化时被固化为 nil
    // fallback 到直线移动
    ctx.NpcState.SetMoveTarget(entry.TargetPos, ...)  // 直线穿墙
```

### 修复：将路网加载提前到 switch 之前

```
scene_impl.go init():
  107: initRoadNetwork()  ← 提前到 switch 之前
  112: switch sceneType
  113:   case TownSceneInfo:
  129:     townRosurceInit(saveInfo)
              └─ GetResourceAs[RoadNetworkMgr] → ✅ 路网已加载
```

## 为什么 V1 不受影响

V1 行为树节点在**每次执行时**实时查询资源，不在初始化时固化引用：

```go
// behavior_helpers.go:286 — V1 运行时动态获取
roadNetMgr, ok := common.GetResourceAs[*roadnetwork.MapRoadNetworkMgr](ctx.Scene, ...)

// schedule_handlers.go — V2 初始化时固化
func NewScheduleHandler(..., roadNetMgr RoadNetQuerier) // 构造时传入，之后不再查询
```

## 排查过程中的弯路

1. **一开始怀疑客户端同步问题** — 以为服务器路网寻路正确但客户端插值拉直了路径。实际上服务器根本没做路网寻路
2. **混淆了 V1/V2 运行状态** — 日志文件是旧的（V1 运行时产生），但 config.toml 已切换到 V2。应优先确认当前配置和运行状态的一致性
3. **Python A* 模拟误导** — 自己写的 A* 有 bug 导致"找不到路径"，差点误判为路网不连通

## 经验教训

### 1. 资源初始化依赖必须显式声明顺序

**规则**: 如果模块 A 在初始化时获取模块 B 的引用并固化，则 B 必须在 A 之前初始化。尤其当从"运行时动态查询"重构为"初始化时注入"模式时，必须检查初始化顺序。

**检查清单**:
- 新增 `InitXxxManagers()` / `NewXxxHandler()` 时，确认所有参数对应的资源已加载
- 在 `scene_impl.go` 中添加注释标注依赖关系

### 2. "初始化注入" vs "运行时查询"的陷阱

V1 用运行时查询（每帧 `GetResourceAs`），对初始化顺序不敏感但有性能开销。
V2 用初始化注入（构造时传入引用），性能好但**对初始化顺序极度敏感**。

切换模式时，必须同步调整初始化顺序。

### 3. 沉默失败是最危险的 Bug

`roadNetQ = nil` 时没有任何 Warning/Error 日志，代码设计上允许 nil（注释写着"允许为 nil，退化为直线移动"）。这种"优雅降级"在开发阶段反而掩盖了配置错误。

**建议**: 初始化阶段如果预期资源应该存在但获取失败，应该打 Warning 而非静默降级。
