---
name: 客户端面板与快捷键
status: pending
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Managers/Input/InputEventId.cs — 新增 SummonDogPanel 快捷键事件 ID 常量
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/RUI/Panels/SummonDogPanel/SummonDogPanel.cs — 面板逻辑层：
  - PanelBase 继承，InitEx/BindUIEvents/OnShowEx/OnCloseEx 生命周期
  - Alt+P 快捷键注册（参考 OpenMap 模式，在 GameplayManager 级注册监听）
  - 召唤按钮点击 → 检查 2s 本地冷却（Time.realtimeSinceStartup）→ 按钮 Loading 状态
  - NetCmd.SummonDog async/await UniTask 发送请求（参考 AnimalInteractComp 的 NetCmd.AnimalFeed）
  - CancellationTokenSource 管理（OnShowEx 创建，OnCloseEx Cancel+Dispose）
  - 成功：关闭面板 + 短暂成功提示 2-3s
  - 失败 14005：面板保持 + 显示「附近没有可召唤的狗」2-3s
  - 失败 14006/其他：显示通用错误提示
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/RUI/Panels/SummonDogPanel/SummonDogPanelView.cs — View 层 UI 组件绑定（召唤按钮、关闭按钮、提示文本）
- 新增: freelifeclient/Assets/PackResources/UI/Prefab/SummonDogPanel.prefab — 面板 Prefab（通过 Unity MCP 创建，按钮 ≥44x44）

## 验证标准
- 客户端编译无 CS 错误（Unity MCP console-get-logs 检查）
- using 命名空间正确，无 Vector3 歧义（显式 using UnityEngine）
- using FL.NetModule 时添加 Vector2/Vector3 alias 消歧义
- CancellationToken 正确传递给 NetCmd 调用
- InputEventId 新常量不与现有 ID 冲突

## 依赖
- 依赖 task-01（需要生成的客户端 C# Proto 代码和 NetCmd 方法）
