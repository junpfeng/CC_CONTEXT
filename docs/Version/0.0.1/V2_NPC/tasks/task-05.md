---
name: Client Controller + 基础组件
status: completed
---

## 范围
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs — 大世界 NPC 主控制器。OnInit 中 AddComp 注册所有组件（TransformComp/MoveComp/AppearanceComp，FSM/Animation 在 task-06 中补充）。OnClear 中逆序清理。不继承 TownNpcController，不引用 S1Town 模块类型
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs — 位置同步组件，基于 TransformSnapshotQueue 插值。LOD 感知：FULL 300ms / REDUCED 500ms+EaseOut / MINIMAL 800ms+线性
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcMoveComp.cs — 移动驱动组件，读取服务器下发的 Movement 数据驱动 Transform
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAppearanceComp.cs — 外观加载组件。根据外观 ID 异步加载 BodyParts 预制件并挂载骨骼节点。三级 fallback：单部件失败→跳过 / 全部失败→body-only / fallback 失败→prefab 默认 mesh。使用 CancellationToken 管理异步生命周期

## 验证标准
- Unity 编译无 CS 错误（通过 MCP console-get-logs 或 Roslyn 检查）
- Controller 不引用 S1Town 命名空间下的任何类型
- 所有 async 操作使用 UniTask + CancellationToken，OnClear 中 Cancel
- 新文件添加 `using UnityEngine;` 并用 using alias 消除 Vector3 歧义（`using Vector3 = UnityEngine.Vector3;`）
- AppearanceComp 外观加载失败不导致 NPC 隐形

## 依赖
- 无（复用现有 NpcDataUpdate/NpcV2Info 协议，无服务端代码依赖）
