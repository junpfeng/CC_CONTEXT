---
name: generate-town-road-network
description: 从小镇小地图 S1Town.png 自动提取车辆交通路网，生成 GleyNav RoadPoint 格式 JSON。
argument-hint: "[可选参数: spacing=5 threshold=95 connect=2.5]"
---

从小镇小地图纹理自动提取道路中心线，生成匹配实际道路的车辆路网数据。

## 前置条件

- Python 3 + `scikit-image`, `scipy`, `matplotlib`, `Pillow`
- 小地图文件: `freelifeclient/Assets/PackResources/UI/Icon/Map/S1Town.png`

## 地图坐标映射 (MapUI[22])

| 参数 | 值 | 说明 |
|------|-----|------|
| 逻辑尺寸 | 2048x2048 | 配置表中的图片尺寸 |
| scale | 0.2056 | 逻辑 1px = 0.2056m |
| worldPos | (200, 0, -207) | 左上角世界坐标 |
| 实际图片 | 8742x8742 | 高分辨率版本 |
| 实际 pixel_scale | 0.0482 m/px | = 0.2056 * 2048 / 8742 |

**坐标转换公式：**
```
pixel_scale = MAP_SCALE * LOGICAL_SIZE / ACTUAL_IMAGE_WIDTH
world_x = OFFSET_X - pixel_x * pixel_scale
world_z = OFFSET_Z + pixel_y * pixel_scale
```

> 注意：GleyNav 加载路点后会做 Y 坐标 Raycast 修正（`TrafficWaypointsDataHandlerExternal.RaycastGroundY`），所以 JSON 中的 Y 值不需要精确，填 513.0 即可。

## 生成流程

### Step 1: 道路掩码提取

从灰度小地图中分离道路像素：
- 道路: 亮灰色 (灰度值 95-215)
- 建筑: 深灰色 (50-90)
- 水/边界: 黑色 (<35)
- 背景: 白色 (>230)

```python
road_mask = (arr > 95) & (arr < 215)
# 排除白色背景膨胀区域和水面膨胀区域
road_mask = road_mask & ~bg_dilated & ~water_dilated
# 形态学清理 + 去除小连通域 (<500px)
```

**关键参数**:
- `threshold_low`: 95（降低可捕获更多暗色道路，升高可减少建筑误检）
- `threshold_high`: 215（不要超过 220，否则会包含背景）
- `min_road_size`: 500（最小连通域面积，去除噪点）

### Step 2: 骨架化

使用 `skimage.morphology.skeletonize` 提取道路中心线（单像素宽度）。

### Step 3: 路点采样

沿骨架均匀采样路点，间距约 5m（world）= `5.0 / pixel_scale` 像素。

**关键参数**:
- `spacing`: 5m（太小会生成过多路点导致卡顿，太大会丢失弯道细节）
- 推荐范围: 3-8m

### Step 4: 邻接关系构建

用 KDTree 搜索每个路点附近的候选邻居，检查连线中点是否在道路掩码上：

```python
CONNECT_RADIUS = SAMPLE_SPACING * 2.5  # 搜索半径
# 对每对候选点，沿连线多点采样检查是否穿越非道路区域
```

**关键参数**:
- `connect_multiplier`: 2.5（连接搜索半径 = spacing * 此值）
- 太小会断开连接，太大会产生穿越建筑的错误连接

### Step 5: 输出 GleyNav RoadPoint JSON

每个路点输出为：
```json
{
  "OtherLanes": [],
  "junction_id": 0,
  "road_name": "",
  "cycle": 0,
  "road_type": 1,
  "streetId": 0,
  "neighbors": [邻居索引列表],
  "prev": [前驱索引列表（双向，和 neighbors 相同）],
  "position": {"x": world_x, "y": 513.0, "z": world_z},
  "name": "Gley{index}",
  "listIndex": index
}
```

写入三个文件（保持一致）：
- `Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json`
- `RawTables/Json/Global/traffic_waypoint/road_traffic_gley.json`
- `Assets/PackResources/Config/Data/traffic_waypoint/town_vehicle_road.json`

### Step 6: 可视化验证

生成对比图保存到 `scripts/road_extraction_result.png`：
1. 道路掩码（确认提取完整性）
2. 路点 + 连接叠加在原图上（确认路网拓扑正确）

## 验证方法

生成后应叠加到游戏俯视截图上验证坐标匹配：

```python
# 游戏俯视截图相机参数
cam_pos = (30, 120, -20)
ortho_size = 180
# 用 script-execute 创建临时相机拍摄
```

## 完整脚本位置

`scripts/extract_road_v2.py` — 主生成脚本，可直接运行：
```
python3 scripts/extract_road_v2.py
```

## 已知问题

1. **骨架化在宽道路上可能产生分叉** — 用更大的形态学闭操作合并
2. **弯道路点稀疏** — 降低 spacing 参数
3. **路口处连接过多** — 正常现象，TownTrafficMover 在路口随机选方向
4. **边缘道路可能被截断** — 检查 bg_dilated 膨胀范围是否过大
