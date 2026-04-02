# 鸟类视觉增强设计方案

## 需求回顾

鸟太小了，在游戏中看不到在哪以及飞行轨迹。

## 问题分析

1. **模型太小**：BirdPrefab1.prefab 的 localScale=(1,1,1)，FBX 模型本身体量小，远距离几乎不可见
2. **飞行高度偏高**：飞行高度范围 5-20m（相对地面），人物视角仰望不易追踪
3. **生成数量少**：当前只生成 3 只鸟，观感稀疏

## 方案设计

### 1. 客户端：放大鸟类模型（AnimalController）

在 `AnimalController.OnInitiated()` 中，鸟类（AnimalType==2）设置模型缩放为 3 倍。

**修改文件**: `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Animal/AnimalController.cs`

```csharp
// OnInitiated() 中，SnapToGround 之后：
if (_animalType == 2)
    transform.localScale = Vector3.one * 3f;
```

选择 3 倍而非更大：鸟类碰撞胶囊半径 0.2m，3 倍后 0.6m，合理。过大会显得不自然。

### 2. 服务端：降低飞行高度 + 扩大飞行半径

**修改文件**: `P1GoServer/servers/scene_server/internal/common/ai/execution/handlers/animal_bird_flight.go`

| 参数 | 原值 | 新值 | 原因 |
|------|------|------|------|
| birdFlightMinAlt | 5.0m | 3.0m | 降低最低高度，更容易看到 |
| birdFlightCeiling | 20.0m | 12.0m | 降低天花板，防止飞太高消失 |
| birdFlightRadiusMax | 20.0m | 40.0m | 扩大飞行范围，轨迹更明显 |

### 3. 服务端：增加鸟类生成数量

**修改文件**: `P1GoServer/servers/scene_server/internal/common/ai/animal/animal_spawner.go`

将鸟类期望生成数量从 3 只增加到 6 只，成群飞行更容易注意到。

## 验收测试方案

```
[TC-001] 鸟类可见性验证
前置条件：已登录进入大世界
操作步骤：
  1. [MCP] screenshot-game-view 截图观察天空
  2. [MCP] script-execute 查找鸟类实体位置
  3. [验证] 鸟在画面中清晰可见，体量合适
  4. [MCP] 等待 10s 后再次截图，观察飞行轨迹变化
  5. [验证] 能明显观察到鸟在移动
```

## 风险评估

- 缩放 3 倍不会穿模（鸟在空中，不与地面/建筑碰撞）
- 降低飞行高度到 3m 最低，不会穿地（服务端基于 GroundAltitude 偏移计算）
