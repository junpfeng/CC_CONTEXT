---
name: 客户端 Entity 组件系统
description: Entity 组件系统命名空间、常见 CS0246 错误、新建 Comp 的最小 using 列表
type: reference
---

## 关键类和命名空间

| 类/接口 | 命名空间 | 文件路径 |
|---------|----------|----------|
| `Comp` (抽象基类) | `FL.Gameplay.Lib` | `Assets/Scripts/Gameplay/Libs/Component/Comp.cs` |
| `IComp` | `FL.Gameplay.Lib` | `Assets/Scripts/Gameplay/Libs/Component/` |
| `ICompOwner` | `FL.Gameplay.Lib` | `Assets/Scripts/Gameplay/Libs/Component/` |
| `IUpdate` | `FL.Gameplay.Lib` | `Assets/Scripts/Gameplay/Libs/Update/IUpdate.cs` |
| `IFixedUpdate` | `FL.Gameplay.Lib` | `Assets/Scripts/Gameplay/Libs/Update/` |
| `ILateUpdate` | `FL.Gameplay.Lib` | `Assets/Scripts/Gameplay/Libs/Update/` |
| `EventId` | `FL.Framework.Manager` | `Assets/Scripts/Gameplay/Managers/Event/EventId.cs` |
| `EventComp` | `FL.Gameplay.Modules.BigWorld` | `Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Common/Comp/EventComp.cs` |

## 易混淆命名空间

| 命名空间 | 包含内容 |
|----------|----------|
| `FL.Framework.Manager` | `EventId`（事件ID常量）、`EventManager`（全局事件管理器） |
| `FL.Gameplay.Manager` | `CameraManager`、`WeaponJsonConfigLoader` 等游戏业务 Manager |

使用 `EventId` 时需要 `using FL.Framework.Manager;`，不要与 `FL.Gameplay.Manager` 混淆。

## 常见问题

### CS0246: Comp / IUpdate 找不到

BigWorld Entity 下的组件类继承 `Comp` 并实现 `IUpdate`，这些类型都在 `FL.Gameplay.Lib` 命名空间中，而组件文件通常在 `FL.Gameplay.Modules.BigWorld` 命名空间。

**修复**: 添加 `using FL.Gameplay.Lib;`

### 新建 Comp 子类的最小 using 列表

```csharp
using FL.Framework.Manager;         // EventId, EventManager
using FL.Gameplay.Lib;              // Comp, IUpdate, ICompOwner
using FL.Gameplay.Manager;          // 业务 Manager (CameraManager 等)
using FL.Gameplay.Modules.BigWorld; // Entity 类型 (如果不在此命名空间下)
using FL.MLogRuntime;               // MLog 日志
using UnityEngine;                  // Unity 类型
```
