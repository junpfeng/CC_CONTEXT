# 小地图交通车辆图标替换 + 图例Toggle

> **注意**：本文档针对 S1Town 小镇交通系统（轻量方案）。大世界交通系统（GTA5 式）请参阅 `design/ai/big_world_traffic/`。

## 需求

1. 大世界小地图中交通车辆图标从通用标记替换为对应车型图标
2. 参考NPC追踪，添加"交通车辆"图例Toggle，控制显示/隐藏

## 现状分析

- `MapTrafficVehicleLegend` 硬编码 `TrafficVehicleIconId = 50010`（`carSpot.png` 通用标记）
- 无图例Toggle，无法隐藏交通车辆
- `Vehicle.vehicleConfigId` → `VehicleBase.vechicleType` 可获取车辆类型

## 设计

### 1. 配置表变更 (icon.xlsx)

**LegendType_c 新增条目**:
| Id | Name | Order | TypeIcon |
|----|------|-------|----------|
| 126 | 交通车辆 | 50 | myVehicle.png 路径 |

**MapIcon 新增/修改**:
- 50010: legendType 改为 126（归入交通车辆Toggle组）
- 50011: Car 图标 → `myVehicle.png`, legendType=126
- 50012: Motorcycle 图标 → `carSpot.png`(临时), legendType=126
- 其他VehicleType暂用50010 fallback

### 2. 代码变更

**MapLegendBase.cs** - `MapTrafficVehicleLegend`:
- 移除硬编码常量 `TrafficVehicleIconId`
- 添加 `VehicleType → MapIconId` 静态映射
- `SetTrafficVehicleInfo` 新增 `vehicleConfigId` 参数
- 根据 VehicleBase.vechicleType 选择对应 MapIcon

**MapLegendControl.cs**:
- 新增 `TrafficVehicleLegendTypeId = 126`
- 新增 `_showTrafficVehicles = true` + `ShowTrafficVehicles` 属性
- 新增 `ToggleShowTrafficVehicles(bool show)` 方法（触发 _frameUpdate）
- `AddTrafficVehicleLegend` 新增 vehicleConfigId 参数透传

**MapPanel.cs**:
- `RefreshAllLegends`: TrafficVehicle 类型 + toggle关闭时 skip
- `RefreshLegendTypeWidgets`: EnsureToggleButton(TrafficVehicleLegendTypeId)
- `SelectNewType`: 处理 TrafficVehicle toggle 点击

**Vehicle.cs**:
- `AddTrafficVehicleLegend` 调用时传入 `vehicleConfigId`

### 3. 验收测试

- [TC-01] 登录大世界，打开小地图，验证交通车辆显示车型图标
- [TC-02] 点击"交通车辆"图例按钮，验证车辆图标隐藏
- [TC-03] 再次点击，验证车辆图标恢复显示
