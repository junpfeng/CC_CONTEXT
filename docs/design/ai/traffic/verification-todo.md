# S1Town 交通系统启用 - 验证任务

## 已完成的改动

### 阶段一：代码改动
- **文件**：`freelifeclient/Assets/Scripts/Gameplay/Managers/LaunchManager/State/LoadScene.cs`
- **改动1**（L331）：Town 加入 openTraffic 读取条件（与 City/Sakura 并列）
- **改动2**（L360）：Town 走独立分支——调用 `TrafficManager.Instance.OnEnterScene()` 加载路点数据，跳过 DotsCity

### 阶段二：配置改动
- **文件**：`freelifeclient/RawTables/map/scene.xlsx` → SceneInfo sheet → row 26（id=22, S1Town）
  - U26 `WaypointFile`：`ScheduleI.json` → `road_traffic_fl.json`
  - Y26 `UseTrafficSystem`：`FALSE` → `TRUE`
- **打表**：`cfg_sceneinfo.bytes` 已重新生成（11,945 字节）
- **数据**：`road_traffic_fl.json` 已拷贝到 `Assets/PackResources/Config/Data/traffic_waypoint/`

## 待验证

1. **启动 Play 模式**，进入 S1Town 小镇场景
2. **检查 Console 日志**：
   - 成功标志：TrafficManager 无报错，GleyNav 加载 road_traffic_fl.json 成功
   - 失败标志：`GleyNav.Init: road data is null or empty` 或其他异常
3. **检查 NPC 日程**：NPC 行为是否正常（waypointFile 字段仅 TrafficManager 读取，不影响 NPC）
4. **预期**：路点数据加载成功，但无车辆出现（DotsCity 未初始化，属于正常）

## 如果验证失败

- **文件找不到**：确认 `Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_fl.json` 存在
- **数据格式不兼容**：GleyNav 可能只支持 Miami 的平面数组格式，不支持 S1Town 的 nodes+links 图结构
  - 需要适配 GleyNav 或转换数据格式
- **编译错误**：检查 LoadScene.cs 改动

## 后续工作（验证通过后）

决定阶段三方案：
- **完整方案**：搭建 S1Town 的 DotsCity 场景（Hub.prefab + EntitySubScene）
- **轻量方案**：在 TownManagerOfManagers 中用 VehicleAIPathPlanningComponent 做非 ECS 车辆 AI

详细分析见 `docs/design/ai/traffic/road-network.md`
