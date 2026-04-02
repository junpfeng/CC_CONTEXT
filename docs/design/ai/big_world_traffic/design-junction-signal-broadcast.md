# 路口信号灯数据 + ServerRoadNetwork + 广播 — 技术设计

> 对应 `todo-gta5-refactor.md` 项 1-3

## 1. 需求回顾

| 项 | 现状 | 目标 |
|----|------|------|
| 路口数据 | 50,523 路点 junctionId 全为 0 | 自动检测路口并填充 junction_id/cycle |
| ServerRoadNetwork | `GetServerRoadNetwork()` 返回 nil | 场景初始化时创建实例并注册为 Resource |
| 信号灯广播 | TrafficLightSystem 已实现 Update/GetChangedNtfs | tick 后 AOI 广播 + 新玩家全量同步 |

## 2. 架构设计

### 2.1 系统边界

```
┌─ 客户端 (freelifeclient) ─────────────────────────┐
│  TrafficRoadGraph.BuildJunctionData()              │
│    ↓ (junction_id/cycle 已填充)                     │
│  SignalLightCache ← TrafficLightStateNtf (服务端)   │
│  JunctionDecisionFSM → 查询 SignalLightCache        │
└────────────────────────────────────────────────────┘

┌─ 离线工具 (C# Editor) ────────────────────────────┐
│  JunctionDetectorTool                              │
│    输入: road_traffic_client.json (50K 路点)        │
│    输出: 更新 junction_id/cycle + traffic_server.json (~600KB)│
└────────────────────────────────────────────────────┘

┌─ 服务端 (P1GoServer/scene_server) ────────────────┐
│  traffic_server.json → ServerRoadNetwork (Resource) │
│  ServerRoadNetwork.BuildJunctionConfigs()           │
│    → TrafficLightSystem.InitJunctions()             │
│  TrafficLightSystem.Update() → GetChangedNtfs()     │
│    → AOI 广播 TrafficLightStateNtf                  │
│  玩家进入 → GetAllNtfs() 全量同步                    │
└────────────────────────────────────────────────────┘
```

### 2.2 数据流

```
road_traffic_client.json (51MB, 客户端资源)
  ↓ JunctionDetectorTool (Editor 离线运行一次)
  ├→ road_traffic_client.json (更新 junction_id/cycle)
  └→ traffic_server.json (~200KB, 仅位置+路口配置)
       ↓ 打表拷贝到 bin/config/
       ↓ 服务端启动加载
       → ServerRoadNetwork + TrafficLightSystem
```

## 3. 详细设计

### 3.1 路口自动检测工具 (C# Editor)

**文件**: `freelifeclient/Assets/Scripts/Editor/Tools/JunctionDetectorTool.cs`

**算法**:
1. 加载 road_traffic_client.json 全部 RoadPoint
2. 找"汇聚节点"：`len(prev) >= 3` 的节点（3+ 条入边 = 路口候选）
3. 聚类：BFS 扩展，将距汇聚节点 ≤25m 且同为汇聚节点的聚合为一个 junction
4. 分配 junction_id：从 1 开始递增
5. 确定入口节点：junction 边界上、有外部 prev 的节点标记为入口
6. 分配 cycle（信号相位）：
   - 计算每个入口的方向向量（从外部 prev 指向入口）
   - 对向入口（夹角 > 150°）分配同一 phase
   - 垂直入口分配不同 phase
   - 2 入口 → 2 相位；3-4 入口 → 2-3 相位
7. 写回 road_traffic_client.json（更新 junction_id_int 和 cycle 字段）
8. 生成 traffic_server.json（见 3.2）

**入口 cycle 映射规则**:
- cycle=1: 相位 0（南北方向）
- cycle=2: 相位 1（东西方向）
- cycle=3: 相位 2（转弯专用，如存在）
- cycle=0: 非入口节点（路口内部或普通路段）
- 5+ 入口的大型路口：round-robin 分配 phase（每 2 个对向入口一组）

### 3.2 服务端交通数据文件 (traffic_server.json)

**路径**: `bin/config/traffic_server.json`（打表工具拷贝）

```json
{
  "node_count": 50523,
  "positions": [[x0,z0], [x1,z1], ...],
  "road_types": [1, 2, 1, ...],
  "junctions": [
    {
      "junction_id": 1,
      "phase_count": 2,
      "green_ms": 25000,
      "amber_ms": 3000,
      "entrances": [
        {"node_id": 1234, "phase": 0},
        {"node_id": 1235, "phase": 1},
        {"node_id": 1240, "phase": 0},
        {"node_id": 1241, "phase": 1}
      ]
    }
  ]
}
```

**大小估算**: 50K × 8B (positions) + 50K × 4B (road_types) ≈ 600KB + junctions ~10KB ≈ **~600KB**

### 3.3 服务端数据加载

**文件**: `P1GoServer/common/config/config_road_point/traffic_server_loader.go`

新增 `TrafficServerConfig` 结构和加载函数：

```go
type TrafficServerConfig struct {
    NodeCount  int          `json:"node_count"`
    Positions  [][2]float32 `json:"positions"`
    RoadTypes  []int32      `json:"road_types"`
    Junctions  []JunctionCfg `json:"junctions"`
}

type JunctionCfg struct {
    JunctionId int32        `json:"junction_id"`
    PhaseCount int32        `json:"phase_count"`
    GreenMs    int64        `json:"green_ms"`
    AmberMs    int64        `json:"amber_ms"`
    Entrances  []EntranceCfg `json:"entrances"`
}

type EntranceCfg struct {
    NodeId int32 `json:"node_id"`
    Phase  int32 `json:"phase"`
}
```

加载时机：`LoadAllNetWorld()` 中同目录扫描 `traffic_server.json`。

### 3.4 ServerRoadNetwork 注册为 Resource

**改动**: `server_road_network.go`

1. 实现 `common.Resource` 接口（嵌入 `ResourceBase`）
2. 新增 `ResourceType_TrafficRoadNetwork`
3. `GetServerRoadNetwork(scene)` 改为从 scene 获取 Resource
4. `BuildJunctionConfigs()` 从 `TrafficServerConfig.Junctions` 构建而非硬编码

**场景初始化** (`scene_impl.go`):
```go
// initRoadNetwork() 末尾追加:
if trafficCfg := configroadpoint.GetTrafficServerConfig(); trafficCfg != nil {
    srn := trafficvehicle.NewServerRoadNetwork(trafficCfg.Positions, trafficCfg.RoadTypes)
    if srn != nil {
        srnRes := trafficvehicle.NewServerRoadNetworkResource(s, srn, trafficCfg)
        s.AddResource(srnRes)
    }
}
```

**DensityManager 接入**: `DensityManager` 当前通过 `GetServerRoadNetwork(scene)` 获取实例。改为从 scene Resource 获取后自动接入，无需额外修改 DensityManager 代码。

### 3.5 信号灯广播

**改动**: `traffic_light_system.go` + `scene_impl.go`

#### 3.5.1 tick 后广播变更

在 `TrafficLightSystem.OnAfterTick()` 中广播（而非在 scene tick 循环后单独调用）:

```go
func (s *TrafficLightSystem) OnAfterTick() {
    ntfs := s.GetChangedNtfs()
    if len(ntfs) == 0 {
        return
    }
    scene := s.Scene()
    // 信号灯是全局的，广播给所有在线玩家（非 AOI）
    // 因为信号灯状态变化频率低（~每 25s 一次），全量广播开销极小
    for _, ntf := range ntfs {
        broadcastToAllPlayers(scene, ntf)
    }
}
```

**注意**: TODO 原始规格建议 AOI 广播，此处有意偏离为全量广播。理由:
- 信号灯状态变化频率极低（每个路口 ~25s 切换一次）
- 客户端 SignalLightCache 有本地时间插值，不需要每帧同步
- AOI 广播需要知道路口位置→格子映射，增加复杂度但收益小

#### 3.5.2 新玩家全量同步

在 `enter.go` 的 `LoadingFinish` 处理中，获取 TrafficLightSystem 并发送 GetAllNtfs():

```go
// 同步信号灯状态
if tlSys, ok := scene.GetSystem(common.SystemType_TrafficLight); ok {
    if tls, ok := tlSys.(*trafficvehicle.TrafficLightSystem); ok {
        for _, ntf := range tls.GetAllNtfs() {
            client.SendTrafficLightStateNtf(ntf)
        }
    }
}
```

## 4. 接口契约

### 4.1 协议（已有，无需新增）

```protobuf
// old_proto/scene/vehicle.proto（已定义）
message TrafficLightStateNtf {
    uint32 junction_id = 1;
    repeated TrafficLightEntry lights = 2;
}
message TrafficLightEntry {
    uint32 entrance_index = 1;
    TrafficLightCommand command = 2;
    uint32 remaining_ms = 3;
}
```

### 4.2 客户端 ↔ 服务端

- 服务端 → 客户端: `TrafficLightStateNtf`（信号灯状态变更通知）
- 触发时机: 信号灯相位切换时 + 新玩家进入时
- entrance_index 对应 road_traffic_client.json 中的路点 listIndex

### 4.3 数据文件契约

- `traffic_server.json` 由 JunctionDetectorTool 生成
- 通过打表流程拷贝到 `bin/config/`
- 服务端启动时加载，缺失时 ServerRoadNetwork 不创建（降级为无信号灯模式）

## 5. 验收测试方案

### [TC-001] 路口检测结果验证
前置条件：运行 JunctionDetectorTool
操作步骤：
  1. [Editor] 运行 JunctionDetectorTool
  2. [验证] 检查 road_traffic_client.json 中 junction_id 非零的节点数 > 0
  3. [验证] 检查 traffic_server.json 生成且 junctions 数组非空
  4. [验证] 每个 junction 的 entrances 至少 2 个

### [TC-002] 服务端信号灯初始化
前置条件：traffic_server.json 已部署到 bin/config/
操作步骤：
  1. [服务端] 启动 scene_server
  2. [验证] 日志包含 "ServerRoadNetwork 构建完成" + 节点数
  3. [验证] 日志包含 "初始化 N 个路口信号灯"（N > 0）

### [TC-003] 信号灯广播与客户端同步
前置条件：服务端已初始化信号灯，客户端已登录大世界
操作步骤：
  1. [MCP: script-execute] 读取 SignalLightCache 缓存数量
  2. [验证] 缓存数量 > 0，表示收到服务端同步
  3. [MCP: script-execute] 等待 30s 后再次读取，验证有状态变更
  4. [MCP: screenshot-game-view] 截图确认车辆在路口有停车/通行表现

### [TC-004] 新玩家全量同步
前置条件：信号灯已运行一段时间
操作步骤：
  1. [MCP] 退出登录
  2. [MCP] 重新登录进入大世界
  3. [MCP: script-execute] 立即读取 SignalLightCache 缓存数量
  4. [验证] 缓存数量 = 路口总数（全量同步）

## 6. 风险缓解

| 风险 | 缓解 |
|------|------|
| road_traffic_client.json 51MB 解析慢 | JunctionDetectorTool 是离线工具，不影响运行时 |
| traffic_server.json 缺失 | 降级处理：ServerRoadNetwork 不创建，信号灯系统不初始化，路口按无灯处理 |
| 路口检测算法误判 | 提供 Editor 可视化工具验证检测结果 |
| 广播消息量 | ~295 路口 × 每 25s 一次 ≈ 12 msg/s，忽略不计 |

### [TC-005] 数据缺失降级
前置条件：traffic_server.json 不存在
操作步骤：
  1. [服务端] 删除/重命名 traffic_server.json，启动 scene_server
  2. [验证] 日志无 panic/fatal，正常启动
  3. [验证] GetServerRoadNetwork() 返回 nil
  4. [客户端] 登录进入大世界
  5. [验证] 车辆在路口按无灯模式（等待 5s 超时）通过，不崩溃
