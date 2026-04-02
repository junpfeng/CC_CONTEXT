# 交通系统——待实现项方案

> 本文档对应 [`docs/Version/template/traffic.md`](../template/traffic.md) 中所有标注 ⚠️ 待实现 / ⚠️ 不存在 的部分。
> 参考实现：`E:\workspace\PRJ\P1_1\`（已验证可运行，与本项目同级目录）。

---

## 总览

| # | 项目 | 所属端 | 参考文件（P1_1） |
|---|------|--------|-----------------|
| 1 | `TrafficConfig` ECS 资源 | 服务端 | `E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\ecs/res/traffic_config.go` |
| 2 | `TrafficSeedSystem` ECS 系统 | 服务端 | `E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\ecs/system/traffic_seed/traffic_seed_system.go` |
| 3 | `PromoteTrafficVehicle` 处理函数 | 服务端 | `E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\net_func/vehicle/vehicle_system_v2.go` |
| 4 | 系统类型 / 资源类型常量注册 | 服务端 | `E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\common\ecs.go`, `E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\common\resource_type.go` |
| 5 | `TrafficJsonConfigLoader.cs` | 客户端 | `E:\workspace\PRJ\P1_1\freelifeclient\Assets\Scripts\Gameplay\Config\TrafficJsonConfigLoader.cs` |
| 6 | `VehicleJsonConfigLoader.cs` | 客户端 | `E:\workspace\PRJ\P1_1\freelifeclient\Assets\Scripts\Gameplay\Config\VehicleJsonConfigLoader.cs` |
| 7 | `traffic_settings.json` | 配置 | `E:\workspace\PRJ\P1_1\freelifeclient\RawTables\Json\Global\traffic/traffic_settings.json` |
| 8 | `traffic_create.json` | 配置 | `E:\workspace\PRJ\P1_1\freelifeclient\RawTables\Json\Global\traffic/traffic_create.json` |
| 9 | `vehicle_create_rules.json` | 配置 | `E:\workspace\PRJ\P1_1\freelifeclient\RawTables\Json\Global\vehicle/vehicle_create_rules.json` |

> vehicles.json / vehicle_base.json 当前以 Excel 管理，暂不迁移 JSON，保持现状。

---

## 1. TrafficConfig ECS 资源

**目标路径**：`P1GoServer/servers/scene_server/internal/ecs/res/traffic_config.go`

**参考**：`E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\ecs/res/traffic_config.go`

### 实现要点

```go
package resource

import "mp/servers/scene_server/internal/common"

type TrafficConfig struct {
    common.ResourceBase

    CurrentSeed           int64
    SeedVersion           uint32
    BaseDensity           float32
    CurrentDensity        float32
    LastSeedChangeTime    int64
    SeedChangeIntervalSec int64   // 默认 300
    MaxTrafficVehicles    int32   // 默认 50
    MaxPromotedPerPlayer  int32   // 默认 3
    MaxPromotedPerScene   int32   // 默认 50
    PromoteCooldownMs     int64   // 默认 2000

    PlayerPromoteCount    map[uint64]int32
    ScenePromoteCount     int32
    PlayerLastPromoteTime map[uint64]int64
}

func NewTrafficConfig(scene common.Scene) *TrafficConfig
func (t *TrafficConfig) CanPromote(playerUID uint64, nowMs int64) (bool, int32)
func (t *TrafficConfig) RecordPromote(playerUID uint64, nowMs int64)
func (t *TrafficConfig) RemovePromote(playerUID uint64)
```

### 注册步骤

1. 在 `P1GoServer/servers/scene_server/internal/common/resource_type.go` 末尾追加常量：
   ```go
   ResourceType_TrafficConfig // 交通种子与密度管理
   ```
2. 在场景初始化（`P1GoServer/servers/scene_server/internal/scene_impl.go` 或等价文件）中添加：
   ```go
   scene.AddResource(resource.NewTrafficConfig(scene))
   ```

---

## 2. TrafficSeedSystem ECS 系统

**目标路径**：`P1GoServer/servers/scene_server/internal/ecs/system/traffic_seed/traffic_seed_system.go`

**参考**：`E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\ecs/system/traffic_seed/traffic_seed_system.go`

### 实现要点

```go
// Update 逻辑
func (s *TrafficSeedSystem) Update() {
    trafficCfg, ok := common.GetResourceAs[*resource.TrafficConfig](s.Scene(), common.ResourceType_TrafficConfig)
    if !ok { return }

    nowSec := mtime.NowSecondTickWithOffset()

    // 首次初始化
    if trafficCfg.CurrentSeed == 0 {
        trafficCfg.CurrentSeed = mtime.NowMilliTickWithOffset()
        trafficCfg.SeedVersion = 1
        trafficCfg.LastSeedChangeTime = nowSec
        trafficCfg.SetSync()
        return
    }

    // 定时轮换
    if nowSec-trafficCfg.LastSeedChangeTime < trafficCfg.SeedChangeIntervalSec {
        return
    }
    trafficCfg.CurrentSeed = mtime.NowMilliTickWithOffset()
    trafficCfg.SeedVersion++
    trafficCfg.LastSeedChangeTime = nowSec
    trafficCfg.SetSync()
}
```

### 注册步骤

1. 在 `P1GoServer/servers/scene_server/internal/common/ecs.go` SystemType 常量块追加：
   ```go
   SystemType_TrafficSeed // 交通种子系统
   ```
2. 在场景系统注册处（与 `TrafficVehicleSystem` 同一位置）追加：
   ```go
   scene.AddSystem(trafficseed.NewTrafficSeedSystem(scene))
   ```

---

## 3. PromoteTrafficVehicle 处理函数

**目标路径**：`P1GoServer/servers/scene_server/internal/net_func/vehicle/vehicle_system_v2.go`

**参考**：`E:\workspace\PRJ\P1_1\P1GoServer\servers\scene_server\internal\net_func/vehicle/vehicle_system_v2.go`

当前文件存在但缺少该函数。需在文件末尾追加：

```go
func (h *VehicleHandler) PromoteTrafficVehicle(req *proto.ReqPromoteTrafficVehicle) (*proto.ResPromoteTrafficVehicle, *proto_code.RpcError) {
    if h.playerEntity == nil {
        return nil, proto_code.NewErrorMsg("PromoteTrafficVehicle: player entity not found")
    }

    trafficCfg, ok := common.GetResourceAs[*resource.TrafficConfig](h.scene, common.ResourceType_TrafficConfig)
    if !ok {
        log.Errorf("[PromoteTrafficVehicle] TrafficConfig not found")
        return nil, proto_code.NewErrorMsg("TrafficConfig not found")
    }

    nowMs := mtime.NowMilliTickWithOffset()
    playerUID := h.playerEntity.ID()

    canPromote, errCode := trafficCfg.CanPromote(playerUID, nowMs)
    if !canPromote {
        return &proto.ResPromoteTrafficVehicle{ErrorCode: errCode}, nil
    }

    // 种子一致性校验
    if int64(req.Seed) != trafficCfg.CurrentSeed {
        return &proto.ResPromoteTrafficVehicle{
            ErrorCode: int32(proto.VehicleErrorCode_INVALID_SEED),
        }, nil
    }

    vehicleEntity, err := spawn.SpawnPromotedVehicle(
        h.scene,
        req.VehicleCfgId,
        req.PositionX, req.PositionY, req.PositionZ,
        0,
        playerUID,
    )
    if err != nil {
        log.Errorf("[PromoteTrafficVehicle] spawn failed, err=%v, cfg_id=%v, player_entity_id=%v",
            err, req.VehicleCfgId, playerUID)
        return &proto.ResPromoteTrafficVehicle{
            ErrorCode: int32(proto.VehicleErrorCode_VEHICLE_LIMIT_REACHED),
        }, nil
    }

    trafficCfg.RecordPromote(playerUID, nowMs)

    return &proto.ResPromoteTrafficVehicle{
        ErrorCode:    int32(proto.VehicleErrorCode_SUCCESS),
        VehicleNetId: vehicleEntity.ID(),
    }, nil
}
```

**前提**：Proto 中 `ReqPromoteTrafficVehicle` / `ResPromoteTrafficVehicle` 消息及 `VehicleErrorCode_INVALID_SEED`（15）、`PROMOTE_LIMIT_REACHED`（28）、`PROMOTE_COOLDOWN`（29） 已在 `old_proto/scene/vehicle.proto` 中定义并生成。参考 `E:\workspace\PRJ\P1_1\old_proto\scene\vehicle.proto`。若未生成，先运行 `old_proto/_tool_new/1.generate.py`。

---

## 4. TrafficJsonConfigLoader.cs

**目标路径**：`freelifeclient/Assets/Scripts/Gameplay/Managers/Config/TrafficJsonConfigLoader.cs`

**参考**：`E:\workspace\PRJ\P1_1\freelifeclient\Assets\Scripts\Gameplay\Config\TrafficJsonConfigLoader.cs`（可直接复制，namespace 保持 `FL.Gameplay.Config`）

### 数据类

```csharp
public class TrafficSettingJsonConfig {
    [JsonProperty("MaxTrafficVehicleNum")]    public int maxTrafficVehicleNum { get; set; }
    [JsonProperty("MaxTrafficNpcNum")]        public int maxTrafficNpcNum { get; set; }
    [JsonProperty("TransformUpdateInterval")] public int transformUpdateInterval { get; set; }
}

public class TrafficCreateRuleJsonConfig {
    [JsonProperty("Id")]                    public int   Id { get; set; }
    [JsonProperty("VehicleGenerateCoolDown")] public int VehicleGenerateCoolDown { get; set; }
    [JsonProperty("VehiclePool")]           public int   VehiclePool { get; set; }
    [JsonProperty("VehicleMaxCount")]       public int   VehicleMaxCount { get; set; }
    [JsonProperty("VehicleDensityDistance")] public float VehicleDensityDistance { get; set; }
    [JsonProperty("VehicleCreateRate")]     public int   VehicleCreateRate { get; set; }
}
```

### 初始化调用位置

在场景进入时（大世界 `InitTraffic` 或等价入口）调用：
```csharp
TrafficJsonConfigLoader.Init();
```

---

## 5. VehicleJsonConfigLoader.cs

**目标路径**：`freelifeclient/Assets/Scripts/Gameplay/Managers/Config/VehicleJsonConfigLoader.cs`

**参考**：`E:\workspace\PRJ\P1_1\freelifeclient\Assets\Scripts\Gameplay\Config\VehicleJsonConfigLoader.cs`（631 行，包含 18 种配置类型）

直接复制后确认：
- namespace 为 `FL.Gameplay.Config`
- 路径常量 `"../../Configs/vehicle"`（Editor）/ `"StreamingAssets/vehicle"`（Runtime）与项目目录结构匹配
- 依赖 `Newtonsoft.Json`（项目已引入）
- 依赖 `FL.MLogRuntime.MLog`（已存在）

---

## 6. 配置文件

### traffic_settings.json

**目标路径**：`freelifeclient/RawTables/Json/Global/traffic/traffic_settings.json`

```json
{
  "MaxTrafficVehicleNum": 50,
  "MaxTrafficNpcNum": 0,
  "TransformUpdateInterval": 100
}
```

### traffic_create.json

**目标路径**：`freelifeclient/RawTables/Json/Global/traffic/traffic_create.json`

```json
{
  "region": [],
  "vehicle_create_rule": [
    {
      "Id": 1,
      "Desc": "大世界默认交通密度",
      "VehicleGenerateCoolDown": 2000,
      "VehiclePool": 20,
      "VehicleMaxCount": 30,
      "VehicleDensityDistance": 300.0,
      "VehicleCreateRate": 3
    }
  ],
  "npc_create_rule": []
}
```

### vehicle_create_rules.json

**目标路径**：`freelifeclient/RawTables/Json/Global/vehicle/vehicle_create_rules.json`

```json
[
  {
    "Id": 1,
    "Desc": "NPC交通车辆",
    "IsNpc": true,
    "VehiclePoolGroupId": 1
  },
  {
    "Id": 2,
    "Desc": "玩家个人车辆",
    "IsNpc": false,
    "VehiclePoolGroupId": 0
  }
]
```

> **打表**：配置写入后需通过打表工具同步到 `bin/config/`。参考 [`docs/tools/server-ps1.md`](../../tools/server-ps1.md)。

---

## 实现顺序建议

```
1. 服务端常量注册（resource_type.go / ecs.go）
2. TrafficConfig 资源实现
3. TrafficSeedSystem 实现 + 场景注册
4. PromoteTrafficVehicle 函数追加 + Proto 确认
5. 服务端编译验证：make build
6. 客户端配置文件创建（traffic_settings.json / traffic_create.json）
7. TrafficJsonConfigLoader.cs 复制 + namespace 调整
8. VehicleJsonConfigLoader.cs 复制 + 路径确认
9. 客户端编译验证：Unity MCP console-get-logs
```

---

## 关联文档

- 设计文档：[`docs/Version/template/traffic.md`](../template/traffic.md)
- 路网数据：[`docs/viz/roadnet_compare.html`](../../viz/roadnet_compare.html)
- 打表流程：[`docs/tools/server-ps1.md`](../../tools/server-ps1.md)
- 参考实现（完整）：`E:\workspace\PRJ\P1_1\`
