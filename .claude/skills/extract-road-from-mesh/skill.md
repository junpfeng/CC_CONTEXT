---
name: extract-road-from-mesh
description: 从 Unity 场景道路 FBX 网格提取精确道路几何数据（中心线、宽度、分类），生成路网可视化。
argument-hint: "[可选: fbx_path=Road_Sch.fbx output=docs/town_road_meshes.txt]"
---

从 Unity 场景中的道路 FBX 网格提取精确几何数据，用于路网可视化和车辆路网生成。

## 与 generate-town-road-network 的区别

| 维度 | 本 skill（Mesh 提取） | generate-town-road-network（小地图提取） |
|------|----------------------|---------------------------------------|
| 数据源 | FBX 道路网格顶点 | 小地图纹理 S1Town.png |
| 精度 | 亚米级（网格顶点精度） | 约 0.05m/px（依赖图像处理质量） |
| 输出 | 每条道路的宽度、长度、中心线、分类 | 路点 + 邻接关系（GleyNav 格式） |
| 用途 | 可视化、道路几何分析、验证 | 直接生成可运行的车辆路网数据 |
| 依赖 | Unity MCP（script-execute） | Python scikit-image |

两个 skill 互补：本 skill 提取精确道路几何用于验证，generate-town-road-network 生成可运行路网数据。

## 前置条件

- Unity Editor 已打开 S1Town 场景（或对应 Prefab 已加载）
- Unity MCP 可用（`mcp_call.py` 或 `mcp__ai-game-developer__script-execute`）
- 道路 FBX 文件存在：`Assets/ArtResources/Scene/Schedule/Schedule_Terrain/Model/Road_Sch.fbx`

## S1Town 道路层级结构

```
S1Town_Design (Clone)/S1Town/Terrian/Roads/
├── Road_Sch/          # 主道路容器
│   └── Road_Sch/      # 61 个子 mesh（pos=(7.1, 0.1, 45.6)）
│       ├── Road_Sch_01 ~ Road_Sch_43      # 地面道路（43条）
│       ├── Road_Sch_Highway_01 ~ 10        # 高架主干道（10条）
│       ├── Road_Sch_XX_Crosswalks          # 人行横道（8条）
│       └── Road_Sch_28/General_ScheduleI_Road10_BridgeApproach  # 桥梁
└── Foundation/        # 地基（桥梁、分区）
```

## 提取流程

### Step 1: 启用 FBX Read/Write

FBX 默认 `isReadable=false`，网格顶点不可读。需先通过 ModelImporter 开启：

```csharp
var importer = AssetImporter.GetAtPath(fbxPath) as ModelImporter;
if (!importer.isReadable)
{
    importer.isReadable = true;
    importer.SaveAndReimport();  // 触发重新导入
}
```

> ⚠️ 这会修改 FBX 的 import settings（.meta 文件），完成后应还原为 `isReadable=false` 以节省内存。

### Step 2: 提取每条道路的几何数据

对 FBX 中每个 Mesh 子资源：

```csharp
var objs = AssetDatabase.LoadAllAssetsAtPath(fbxPath);
foreach (var obj in objs)
{
    if (!(obj is Mesh mesh) || mesh.vertexCount == 0) continue;
    var verts = mesh.vertices;
    // 计算包围盒、宽度、长度
    // 沿主轴 binning 计算中心线采样点
}
```

**中心线计算方法**：
1. 判断主轴：`spanX > spanZ` → 主轴为 X，否则为 Z
2. 沿主轴分 N 个 bin（N = min(20, verts/10)）
3. 每个 bin 内所有顶点取平均 → 中心线采样点

**宽度计算**：`min(spanX, spanZ)` — 道路的窄边即为宽度

### Step 3: 道路分类

| 名称模式 | 分类 | 特征 |
|---------|------|------|
| `Road_Sch_Highway_XX` | highway | Y≈8-11m（高架），宽 14m，全沿 X≈-11.4 |
| `Road_Sch_XX_Crosswalks` | crosswalk | 小面积，宽 2-14m |
| `Road_Sch_XX` | ground | Y≈0，宽 10-41m |

### Step 4: 输出

**文本格式**（`docs/town_road_meshes.txt`），每行一条道路：
```
名称|顶点数|宽度|长度|yMin|yMax|中心线点1(x,y,z)|中心线点2|...
```

示例：
```
Road_Sch_01|142|10.0|35.3|4.0|4.1|123.3,4.0,-59.4|154.5,4.0,-59.4|157.2,4.1,-59.4
Road_Sch_Highway_01|5378|31.8|109.0|7.4|11.5|1.4,8.9,-171.1|6.6,9.0,-165.8|...
```

### Step 5: 可视化 HTML

生成 `docs/town_road_network.html`，用 Canvas 绘制：
- 地面道路：蓝色系（按宽度分深浅），`lineWidth = 道路宽度 * 缩放`
- 高架主干道：红色
- 人行横道：白色虚线
- 行人路网（叠加）：紫色

交互：拖拽平移、滚轮缩放、悬停查看道路详情、F 适配、R 重置。

### Step 6: 还原 FBX 设置

```csharp
importer.isReadable = false;
importer.SaveAndReimport();
```

## 提取脚本

**Unity C# 脚本**：`scripts/extract_road_mesh.cs`
**调用方式**：
```bash
python3 scripts/mcp_call.py script-execute scripts/_tmp_params.json
```

其中 `_tmp_params.json` 由 Python 生成：
```python
import json
code = open('scripts/extract_road_mesh.cs').read()
params = {'csharpCode': code, 'className': 'Script', 'methodName': 'Main'}
json.dump(params, open('scripts/_tmp_params.json', 'w'))
```

**可视化生成脚本**：`scripts/gen_road_map.py`
```bash
python3 scripts/gen_road_map.py
```

## S1Town 道路数据统计

| 类别 | 数量 | 宽度范围 | Y 范围 | 特征 |
|------|------|---------|--------|------|
| 地面道路 | 43 | 10-41m | -4 ~ 4m | 含弯道、交叉口 |
| 高架主干道 | 10 | 14m | 7.4-11.5m | 全沿 X=-11.4 南北走向 |
| 人行横道 | 8 | 2-14m | 0m / -4m | 路口标记 |
| **总计** | **61** | | | |

## 已知限制

1. **中心线是近似值** — 基于顶点 binning 平均，弯道处可能偏移
2. **FBX 坐标是模型空间** — 需要考虑场景中的父级 Transform（Road_Sch 父级 pos=(7.1, 0.1, 45.6)，但 FBX 顶点已是世界坐标偏移后的值）
3. **不包含车道信息** — 网格只有几何形状，无车道数、行驶方向等语义信息
4. **需 Unity MCP** — 无法离线运行，必须 Unity Editor 在线
