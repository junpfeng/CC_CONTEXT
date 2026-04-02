# 大世界移除服务器同步交通车设计方案

## 需求回顾

大世界存在两套交通系统同时运行：
1. **服务器同步交通车**（`GTA5TrafficSystem` → `OnTrafficVehicleReq` → 服务器创建 Entity）：模型差、Y坐标不准（飘在天上）、网络同步卡顿、有小地图图标
2. **DotsCity 纯客户端交通车**（`CityManager.ChangeCity` → DOTS ECS `TrafficSpawnerSystem`）：模型逼真、本地物理模拟流畅、无小地图图标

**目标**：大世界只保留 DotsCity，移除服务器同步交通车。小镇不受影响。

## 架构设计

### 改动范围

仅客户端 `freelifeclient/`，服务器无需改动（服务器端 `OnTrafficVehicle` handler 是被动响应客户端请求，客户端不再发请求即可）。

### 改动清单

| # | 文件 | 改动 | 说明 |
|---|------|------|------|
| 1 | `LoadScene.cs` L529-544 | 删除 GTA5TrafficSystem 启动 | 不再生成服务器交通车 |
| 2 | `Vehicle.cs` L500-551 | 大世界 IsTrafficSystem 防御 | 在 shouldRegister 前拦截 |
| 3 | `VehicleNetHandle.cs` L17-30 | 加注释标注废弃 | TrafficLightStateNtf 不再生效 |
| 4 | `GTA5TrafficSystem.cs` | 标记废弃 | 不再被调用的死代码 |
| 5 | `BigWorldTrafficSpawner.cs` | 标记废弃 | 不再被调用的死代码 |

**不改动**：ControlPanel/ControlSakuraPanel/AutomationPanel 中的调试面板（仍允许手动生成测试车辆）。

## 详细设计

### 改动 1：LoadScene.LoadTrafficAsync — 删除 GTA5TrafficSystem 启动

DotsCity 有自己的路网系统（ECS Baked），不依赖 `TrafficManager.OnEnterScene` 的路网数据。`TrafficManager` + `TrafficRoadGraph` 仅供 `GTA5TrafficSystem`/`BigWorldTrafficSpawner` 使用。因此整个 `LoadTrafficAsync` 内容可以移除。

```csharp
// 改动后 (L529-544)
private static async UniTaskVoid LoadTrafficAsync(int sceneCfgId)
{
    try
    {
        // 大世界交通完全由 DotsCity ECS 处理，不再启动服务器同步交通车
        // TrafficManager/TrafficRoadGraph/GTA5TrafficSystem 均不再需要
        MLog.Info?.Log(LogModule.Traffic + "LoadTrafficAsync: DotsCity模式, 跳过服务器交通车, sceneCfgId=" + sceneCfgId);
    }
    catch (System.Exception ex)
    {
        MLog.Error?.Log(LogModule.Traffic + "LoadTrafficAsync: 异常 " + ex.Message);
    }
}
```

### 改动 2：Vehicle.OnInit — 大世界 IsTrafficSystem 防御性拦截

**关键**：防御代码必须在 `shouldRegister` 判断之前（L500），而非 L524 之后。因为 L509-523 已经执行了 RegisterVehicle、设置 isKinematic、禁用 NetTransform 等副作用。

```csharp
// 在 L500 if (netData.VehicleStatus.IsTrafficSystem) 之后，L503 shouldRegister 之前
if (netData.VehicleStatus.IsTrafficSystem)
{
    // 大世界不再使用服务器同步交通车，跳过交通注册
    if (!FL.Gameplay.Manager.SceneManager.IsInTown)
    {
        MLog.Warning?.Log(LogModule.Traffic +
            $"Vehicle: 大世界收到服务器交通车辆，跳过交通注册 entityId={Data.EntityId}");
        isControlledByTraffic = false;
        VehicleEngineComp.TurnOnWheelSupport();
        // 不注册 TrafficManager、不设 kinematic、不添加小地图图标
        // 直接跳到后续初始化
        goto SkipTrafficRegistration;
    }
    // ... 原有 Town 逻辑不变 ...
}
SkipTrafficRegistration:
```

> 注：实际实现中用 if-else 结构替代 goto，此处用 goto 仅为说明控制流。

### 改动 3：VehicleNetHandle.cs — 标注 TrafficLightStateNtf 废弃

```csharp
public void TrafficLightStateNtf(TrafficLightStateNtf request)
{
    // [废弃] 2026-03-24: 大世界已移除服务器同步交通车，GTA5TrafficSystem 不再创建
    // 此协议由服务端推送信号灯状态，但 GTA5TrafficSystem.Instance 将永远为 null
    // 保留代码以兼容调试面板手动生成的交通车
    var trafficSys = Gley.TrafficSystem.Internal.GTA5TrafficSystem.Instance;
    if (trafficSys == null) return;
    // ...
}
```

### 改动 4-5：GTA5TrafficSystem.cs / BigWorldTrafficSpawner.cs — 标记废弃

在类声明上添加：
```csharp
// [废弃] 2026-03-24: 大世界改用 DotsCity ECS 交通，此类不再自动启动
// 保留代码供调试面板和可能的回退使用
```

## 风险评估

| 风险 | 影响 | 缓解 |
|------|------|------|
| 小镇交通被误伤 | 高 | Town 路径完全独立（LoadScene L365-373 / SwitchUniverseNtf L354-363），使用 TownTrafficSpawner |
| DotsCity 交通不受影响 | 低 | CityManager.ChangeCity 在 LoadTrafficAsync 之前调用（L393-400） |
| SwitchUniverseNtf 切回大世界 | 低 | 切回大世界（L463-502）只调用 CityManager.ChangeCity，从未调用 LoadTrafficAsync，与本次改动无关 |
| Vehicle.OnInit 副作用残留 | 高 | 防御代码放在 shouldRegister 之前，避免 RegisterVehicle/isKinematic 等副作用 |

## 验收测试

### [TC-001] 大世界无服务器交通车
前置条件：已登录，进入大世界场景
操作步骤：
  1. [等待] 等待 30 秒让交通系统初始化
  2. [截图] screenshot-game-view 观察地面交通车辆
  3. [验证] 无车辆飘在天上
  4. [验证] console-get-logs 无 "GTA5TrafficSystem: 注册车辆" 日志
  5. [验证] 地面有 DotsCity 交通车正常行驶

### [TC-002] 小地图无服务器交通车图标
前置条件：同 TC-001
操作步骤：
  1. [操作] 打开小地图
  2. [截图] screenshot-game-view
  3. [验证] 无绿色交通车移动图标

### [TC-003] 小镇交通不受影响
前置条件：已登录，进入小镇(Town)场景
操作步骤：
  1. [等待] 等待 30 秒
  2. [截图] screenshot-game-view
  3. [验证] 有交通车辆在路上行驶
  4. [验证] console-get-logs 有 "TownTrafficSpawner" 生成日志
