# 设计文档：交通载具功能实现与樱花校园扩展

## 1. 需求回顾

将 `OnTrafficVehicleReq` 协议从 Rust 迁移到 Go 服务器，并支持在樱花校园场景中使用。

**验收标准**：
- Go 服务器实现交通载具生成功能
- 支持大世界和樱花校园场景
- 载具自动消失机制
- 副本场景隔离

---

## 2. 架构设计

### 2.1 系统边界

```
┌─────────────────────────────────────────────────────────┐
│                   Scene Server (Go)                      │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Traffic Vehicle Handler                         │  │
│  │  (处理 OnTrafficVehicleReq)                      │  │
│  └─────────────┬────────────────────────────────────┘  │
│                │                                         │
│                ▼                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Vehicle Spawn Service                           │  │
│  │  - 载具配置验证                                   │  │
│  │  - 实体创建                                       │  │
│  │  - 组件初始化                                     │  │
│  └─────────────┬────────────────────────────────────┘  │
│                │                                         │
│                ▼                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  ECS System                                      │  │
│  │  - VehicleStatusComp (状态组件)                  │  │
│  │  - TransformComp (位置组件)                      │  │
│  │  - NetProxyComp (网络代理)                       │  │
│  │  - TrafficVehicleComp (交通载具标记，新增)       │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 2.2 交通载具 vs 玩家载具

| 特性 | 交通载具 (Traffic Vehicle) | 玩家载具 (Personal Vehicle) |
|------|---------------------------|----------------------------|
| 驾驶者 | NPC | 玩家 |
| 持久化 | 否 | 是（存数据库） |
| 自动消失 | 是（触碰后一段时间） | 否 |
| 所有权 | 无 | 玩家拥有 |
| 用途 | 环境装饰 | 玩家交通工具 |

---

## 3. 详细设计

### 3.1 业务工程设计 (P1GoServer/)

#### 3.1.1 新增组件：TrafficVehicleComp

**路径**：`servers/scene_server/internal/ecs/com/ctraffic_vehicle/traffic_vehicle.go`

**用途**：标记实体为交通载具，管理自动消失逻辑

**结构**：
```go
type TrafficVehicleComp struct {
    common.ComponentBase
    IsTrafficSystem bool      // 是否为交通系统载具
    NeedAutoVanish  bool      // 是否需要自动消失
    TouchedStamp    int64     // 触碰时间戳（毫秒）
    VanishDelay     int64     // 消失延迟（毫秒，默认 5000）
}
```

**关键方法**：
- `NewTrafficVehicleComp() *TrafficVehicleComp`
- `Type() common.ComponentType`
- `ShouldVanish() bool` - 判断是否应该消失
- `OnTouched()` - 被触碰时更新时间戳

#### 3.1.2 修改模块：Vehicle Spawn

**当前状态**：Go 中尚无载具生成逻辑

**实现方案**：创建载具生成辅助函数

**路径**：`servers/scene_server/internal/ecs/spawn/vehicle_spawn.go`（新建）

**核心函数**：
```go
// SpawnTrafficVehicle 生成交通载具
func SpawnTrafficVehicle(
    scene common.Scene,
    vehicleCfgId int32,
    location *proto.Vector3,
    rotation *proto.Vector3,
    colorList []int32,
) (common.Entity, error)
```

**实现逻辑**：
1. 验证载具配置ID
2. 创建实体
3. 添加 TransformComp（位置、旋转）
4. 添加 VehicleStatusComp（状态）
5. 添加 TrafficVehicleComp（交通标记）
6. 添加 NetProxyComp（网络同步）
7. 设置颜色列表
8. 返回实体ID

#### 3.1.3 协议处理器

**路径**：`servers/scene_server/internal/net_func/vehicle/traffic_vehicle.go`（新建）

**结构**：
```go
type VehicleHandler struct {
    scene common.Scene
    ctx   *rpc.RpcContext
}

func (h *VehicleHandler) OnTrafficVehicle(
    req *proto.OnTrafficVehicleReq,
) (*proto.OnTrafficVehicleRes, *proto_code.RpcError)
```

**处理流程**：
1. 验证场景类型（支持的场景才能生成）
2. 调用 SpawnTrafficVehicle 生成载具
3. 返回载具实体ID

**场景类型判断**：
```go
switch h.scene.GetSceneType().(type) {
case *common.CitySceneInfo:
    // 大世界 - 支持
case *common.SakuraSceneInfo:
    // 樱花校园 - 支持
case *common.DungeonSceneInfo:
    // 副本 - 不支持
    return nil, proto_code.NewErrorMsg("Traffic vehicles not supported in dungeons")
default:
    // 其他场景 - 待定
}
```

#### 3.1.4 自动消失系统

**路径**：`servers/scene_server/internal/ecs/system/traffic_vehicle_system.go`（新建）

**功能**：定期检查交通载具是否需要消失

```go
type TrafficVehicleSystem struct {
    *system.SystemBase
}

func (s *TrafficVehicleSystem) Update(dt time.Duration) {
    // 遍历所有 TrafficVehicleComp
    // 检查 ShouldVanish()
    // 如果应该消失，移除实体
}
```

**检查频率**：每秒检查一次

#### 3.1.5 组件类型注册

**修改文件**：`servers/scene_server/internal/common/component_type.go`

**新增枚举**：
```go
const (
    // ... 现有枚举
    ComponentType_TrafficVehicle ComponentType = XX  // 分配新ID
)
```

### 3.2 协议工程设计 (proto/)

**无需修改**：`OnTrafficVehicleReq` 和 `OnTrafficVehicleRes` 协议已存在

### 3.3 配置工程设计 (config/)

**无需修改**：使用现有的载具配置表（cfg_vehicle）

### 3.4 数据库设计

**无需修改**：交通载具不持久化

### 3.5 Rust 参考实现

**参考文件**：
- `server_old/servers/scene/src/scene_service/service_for_scene.rs:on_traffic_vehicle()`
- `server_old/servers/scene/src/vehicle_spawn/*.rs`（如有）

**关键逻辑对标**：

| Rust 实现 | Go 实现 |
|-----------|---------|
| `VehicleSpawnInfo::get_spawn_info()` | `SpawnTrafficVehicle()` |
| `vehicle_spawn.vehicle_status.is_traffic_system = true` | `TrafficVehicleComp.IsTrafficSystem = true` |
| `vehicle_spawn.vehicle_status.need_auto_vanish = true` | `TrafficVehicleComp.NeedAutoVanish = true` |
| `vehicle_spawn.vehicle_status.touched_stamp = now + 5000` | `TrafficVehicleComp.TouchedStamp = now + 5000` |
| `VehicleSpawnInfo::create_entity_for_spawn_info()` | `scene.CreateEntity() + AddComponent()` |

---

## 4. 接口定义

### 4.1 对外接口（协议处理）

**接口名称**：`OnTrafficVehicle`

**请求**：
```protobuf
message OnTrafficVehicleReq {
    int32 vehicle_cfg_id = 1;            // 载具配置ID
    base.Vector3 location = 2;           // 生成位置
    base.Vector3 rotation = 3;           // 生成旋转
    int32 target_seat = 4;               // 目标座位（暂未使用）
    repeated base.IVector3 color_list = 5; // 颜色列表
}
```

**响应**：
```protobuf
message OnTrafficVehicleRes {
    uint64 vehicle_entity = 1;  // 载具实体ID
}
```

**错误码**：
- `INVALID_VEHICLE_CFG_ID` - 载具配置ID无效
- `SCENE_NOT_SUPPORT` - 场景不支持交通载具
- `CREATE_ENTITY_FAILED` - 实体创建失败

### 4.2 内部接口（组件）

**TrafficVehicleComp 接口**：
```go
// ShouldVanish 判断是否应该消失
func (t *TrafficVehicleComp) ShouldVanish(currentTime int64) bool {
    if !t.NeedAutoVanish {
        return false
    }
    return currentTime > t.TouchedStamp
}

// OnTouched 被触碰时调用
func (t *TrafficVehicleComp) OnTouched(currentTime int64) {
    t.TouchedStamp = currentTime + t.VanishDelay
    t.SetSync()
}
```

---

## 5. 数据结构

### 5.1 TrafficVehicleComp 详细定义

```go
package ctraffic_vehicle

import (
    "mp/servers/scene_server/internal/common"
)

type TrafficVehicleComp struct {
    common.ComponentBase
    IsTrafficSystem bool  // 是否为交通系统载具（固定为 true）
    NeedAutoVanish  bool  // 是否需要自动消失（固定为 true）
    TouchedStamp    int64 // 触碰时间戳（毫秒），超过此时间后自动消失
    VanishDelay     int64 // 消失延迟（毫秒），默认 5000
}

func NewTrafficVehicleComp() *TrafficVehicleComp {
    return &TrafficVehicleComp{
        IsTrafficSystem: true,
        NeedAutoVanish:  true,
        VanishDelay:     5000, // 5秒后消失
    }
}

func (t *TrafficVehicleComp) Type() common.ComponentType {
    return common.ComponentType_TrafficVehicle
}

// ShouldVanish 判断是否应该消失
func (t *TrafficVehicleComp) ShouldVanish(currentTime int64) bool {
    if !t.NeedAutoVanish {
        return false
    }
    return currentTime > t.TouchedStamp
}

// OnTouched 被触碰时调用（延长存活时间）
func (t *TrafficVehicleComp) OnTouched(currentTime int64) {
    t.TouchedStamp = currentTime + t.VanishDelay
    t.SetSync()
}

// SetInitialTouchedStamp 设置初始触碰时间戳（创建时调用）
func (t *TrafficVehicleComp) SetInitialTouchedStamp(currentTime int64) {
    t.TouchedStamp = currentTime + t.VanishDelay
}
```

---

## 6. 场景隔离设计

### 6.1 支持的场景类型

**实现方式**：在协议处理器中进行场景类型检查

```go
func (h *VehicleHandler) OnTrafficVehicle(
    req *proto.OnTrafficVehicleReq,
) (*proto.OnTrafficVehicleRes, *proto_code.RpcError) {
    // 场景类型检查
    switch h.scene.GetSceneType().(type) {
    case *common.CitySceneInfo:
        // 大世界 - 允许
    case *common.SakuraSceneInfo:
        // 樱花校园 - 允许
    case *common.DungeonSceneInfo:
        // 副本 - 拒绝
        return nil, proto_code.NewErrorMsg("Traffic vehicles not supported in dungeons")
    case *common.TownSceneInfo:
        // 小镇 - 待确认（默认拒绝）
        return nil, proto_code.NewErrorMsg("Traffic vehicles not supported in town")
    default:
        return nil, proto_code.NewErrorMsg("Unknown scene type")
    }

    // ... 继续处理
}
```

### 6.2 场景类型枚举（可选）

如果需要更灵活的配置，可以添加场景类型枚举：

```go
type TrafficVehicleSceneType int

const (
    TrafficVehicleScene_City   TrafficVehicleSceneType = 0  // 大世界
    TrafficVehicleScene_Sakura TrafficVehicleSceneType = 1  // 樱花校园
)

// 配置驱动的场景支持
var supportedScenes = map[TrafficVehicleSceneType]bool{
    TrafficVehicleScene_City:   true,
    TrafficVehicleScene_Sakura: true,
}
```

---

## 7. 事务性设计

### 7.1 实体创建事务

**原则**：先验证后创建

**流程**：
```go
func SpawnTrafficVehicle(...) (common.Entity, error) {
    // 1. 前置验证（不修改任何状态）
    cfg := config.GetCfgVehicleById(vehicleCfgId)
    if cfg == nil {
        return 0, errors.New("invalid vehicle cfg id")
    }
    if location == nil || rotation == nil {
        return 0, errors.New("invalid location or rotation")
    }

    // 2. 创建实体（修改状态）
    entity := scene.CreateEntity()

    // 3. 添加组件（失败时清理）
    defer func() {
        if err != nil {
            scene.RemoveEntity(entity)  // 回滚
        }
    }()

    // 添加各组件...
    return entity, nil
}
```

### 7.2 并发控制

**无需加锁**：
- 实体创建由 Scene 的单线程模型保证安全
- 组件添加是原子操作

### 7.3 幂等性

**不需要幂等性设计**：
- 每次请求生成新的载具实体
- 不涉及状态修改，只是创建新对象

### 7.4 错误处理

**错误分类**：
1. **配置错误**：载具配置ID无效 → 返回错误，不创建实体
2. **场景限制**：场景不支持 → 返回错误
3. **创建失败**：实体创建失败 → 清理已创建的实体

---

## 8. 并发控制

**无需特殊并发控制**：
- Scene Server 的 ECS 系统是单线程模型
- 所有实体和组件操作在同一个 goroutine 中执行
- 协议处理器在 Scene 的主循环中调用

---

## 9. 接口契约

### 9.1 协议工程 ↔ 业务工程

**消息格式**：已定义，无需修改

**版本兼容性**：
- 字段全部为可选（optional）
- 新增字段不影响老版本

### 9.2 配置工程 ↔ 业务工程

**配置依赖**：
- `cfg_vehicle` - 载具配置表
- 字段：载具ID、模型、属性等

**配置缺失处理**：
- 载具配置ID不存在 → 返回错误，不创建实体

---

## 10. 风险与缓解

| 风险 | 严重性 | 缓解措施 |
|------|--------|----------|
| Go 载具生成逻辑与 Rust 不一致 | 中 | 对标 Rust 实现，逐行对比逻辑 |
| 自动消失机制失效导致载具堆积 | 中 | 添加定时清理逻辑 + 日志监控 |
| 场景切换时交通载具状态 | 低 | 交通载具不跨场景，切换时自动清理 |
| 载具配置ID在不同场景兼容性 | 低 | 使用统一配置表 |
| ECS 组件ID冲突 | 低 | 确认新的 ComponentType 枚举值未被占用 |

---

## 11. 文件修改清单

| 文件路径 | 修改类型 | 内容 |
|---------|---------|------|
| `servers/scene_server/internal/common/component_type.go` | 修改 | 新增 `ComponentType_TrafficVehicle` 枚举 |
| `servers/scene_server/internal/ecs/com/ctraffic_vehicle/` | 新建目录 | 创建交通载具组件包 |
| `servers/scene_server/internal/ecs/com/ctraffic_vehicle/traffic_vehicle.go` | 新建 | TrafficVehicleComp 组件定义 |
| `servers/scene_server/internal/ecs/spawn/vehicle_spawn.go` | 新建 | 载具生成辅助函数 |
| `servers/scene_server/internal/ecs/system/traffic_vehicle_system.go` | 新建 | 自动消失检查系统 |
| `servers/scene_server/internal/net_func/vehicle/` | 新建目录 | 创建载具协议处理包 |
| `servers/scene_server/internal/net_func/vehicle/traffic_vehicle.go` | 新建 | OnTrafficVehicle 协议处理器 |
| `servers/scene_server/internal/net_func/temp/external.go` | 修改 | 移除 "not implemented" 占位符，调用新的处理器 |
| `servers/scene_server/internal/ecs/scene_impl.go` | 修改 | 注册 TrafficVehicleSystem |

---

## 12. 测试计划

### 12.1 单元测试

- [ ] `TrafficVehicleComp.ShouldVanish()` 逻辑测试
- [ ] `SpawnTrafficVehicle()` 参数验证测试
- [ ] 场景类型检查测试

### 12.2 集成测试

- [ ] 大世界场景生成交通载具
- [ ] 樱花校园场景生成交通载具
- [ ] 副本场景拒绝生成交通载具
- [ ] 自动消失机制测试（5秒后消失）

### 12.3 压测

- [ ] 单场景生成 100 个交通载具
- [ ] 验证自动清理机制有效性

---

## 13. 上线计划

### 13.1 分阶段实施

**Phase 1**：基础功能实现
- 实现 TrafficVehicleComp
- 实现 SpawnTrafficVehicle
- 实现协议处理器
- 支持大世界场景

**Phase 2**：樱花校园扩展
- 添加樱花校园场景支持
- 场景隔离测试

**Phase 3**：自动消失机制
- 实现 TrafficVehicleSystem
- 定期清理逻辑

### 13.2 灰度策略

1. 先在测试环境验证
2. 大世界场景先上线
3. 樱花校园场景跟随上线

---

## 14. 监控指标

- 交通载具创建数量（按场景类型统计）
- 交通载具存活数量（实时监控）
- 自动消失触发次数
- 创建失败次数及原因

---

## 15. 参考资料

- Rust 实现：`server_old/servers/scene/src/scene_service/service_for_scene.rs`
- 协议定义：`proto/old_proto/scene/scene.proto`
- 玩家载具组件：`servers/scene_server/internal/ecs/com/cplayer/player_vehicle.go`
