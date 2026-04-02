# BigWorld_Animal 修复记录

## Bug 1：投喂交互UI不出现
- **根因**：`MuiPanelOpenTool.OpenPanelWhenEnterScene()` 遗漏打开 `InteractionPanel`，导致 `EShowNpcInteractUI` 事件无订阅者
- **修复**：在 `MuiPanelOpenTool.cs` 的 `OpenPanelWhenEnterScene()` 中添加 `tasks.Add(UIManager.Open<InteractionPanel>())`
- **验证**：InteractionPanel 已加载（`UIManager.TryGetPanel` 返回 true），手动触发事件后交互 UI 正常显示
- **修复文件**：`freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Tools/MuiPanelOpenTool.cs`
- **日期**：2026-03-31

## Bug 2：召唤狗UI无入口
- **根因**：`SummonDogPanel` 仅通过 Alt+P 快捷键打开，无 HUD 按钮入口
- **修复**：在 `HudFuctionWidget.cs` 中动态创建 "召唤" MButton，点击打开 `SummonDogPanel`
- **验证**：按钮出现在 HUD 中（display=Flex），可正常点击
- **修复文件**：`freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Pages/Widgets/HudFuctionWidget.cs`
- **日期**：2026-03-31

## Bug 3：投喂交互UI风格不一致且点击/F键无响应
- **根因**：`AnimalInteractComp` 使用 `EventId.EShowNpcInteractUI` 事件展示 `InteractGetInWidget`（车辆上车气泡），该 widget 无 F 键监听，且 onClick 未接线到 `TriggerFeed()`
- **修复**：改用 `MuiUtil.AddInteractTip(desc, icon, TriggerFeed)` 创建 `InteractionHintWidget`，与其他 NPC 交互风格一致，F 键和点击回调由 widget 原生支持
- **验证**：传送到狗附近（dist=2.4m），isShowing=True，tipId=7；调用 TriggerFeed 后服务器返回喂食成功（followDur=30）
- **修复文件**：`freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Animal/Comp/AnimalInteractComp.cs`
- **日期**：2026-03-31

## Bug 4：投喂按钮可见但点击无反应
- **根因**：运行时 `platformType=Mobile`，使用 `InteractionHintPanel`（Mobile 版）。其 `OnOpen()` 调用 `MuiUtil.DisableAllPickingEvent(_view.hintContainerGroup)` 缺少 `exceptButton=true`，导致预创建的 Widget 中所有 MButton 的 `pickingMode` 被设为 `Ignore`。按钮可见但无法接收指针事件。PC 面板（`InteractionHintPCPanel`）已正确传入 `true`，Mobile 面板遗漏
- **修复**：`InteractionHintPanel.cs` line 42 改为 `MuiUtil.DisableAllPickingEvent(_view.hintContainerGroup, true)`
- **验证**：修复后 12 个 hint button 全部 `pickingMode=Position`（修复前为 `Ignore`），`AddInteractTip` 返回有效 tipId，TriggerFeed 可被成功调用
- **修复文件**：`freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/InteractionHintPanel.cs`
- **日期**：2026-03-31

## Bug 5：喂食成功后狗不跟随（一帧即结束）
- **根因**：`AnimalFollowHandler.OnTick` 的到达检测阈值（`animalFollowArrivedDistSq=16.0` 即 4m）大于喂食距离上限（3m）。喂食完成时狗已在 4m 范围内，首次 tick 立即判定到达并清除 `FollowTargetID`，跟随状态仅持续一帧
- **修复**：新增 `animalFollowMinDurationMs=3000`（3s 最小跟随时间）。在到达检测前计算已跟随时长，`elapsed < 3s` 时跳过到达判定，允许狗先跟随移动一段时间
- **验证**：服务端日志确认 OnEnter→到达间隔从 <1帧 变为 3秒（`22:37:51 OnEnter → 22:37:54 到达`）
- **修复文件**：`P1GoServer/servers/scene_server/internal/common/ai/execution/handlers/animal_follow.go`
- **日期**：2026-03-31

## Bug 6：投喂狗无反应不跟随（距离不一致+RPC错误丢失）
- **根因**：双重 bug。(A) 服务端喂食距离校验（3m）与客户端一致，但客户端用插值后渲染位置判断范围，服务端用原始实体坐标，狗漫游时服务端位置超前导致距离校验失败返回 14002。(B) RPC 错误响应未回传客户端，UniTask 永远 Pending，客户端无任何反馈
- **修复**：(A) 服务端 `animalFeedMaxDistSq` 从 9.0（3m²）放宽到 25.0（5m²），补偿位置同步延迟。(B) 客户端 `SendFeedRequest` 添加 5s CancellationTokenSource 超时兜底
- **验证**：传送到 Dog59 附近，发送 AnimalFeedReq，Gateway 无报错，服务端返回 code=0 followDur=30，客户端收到 AnimalStateChangeNtf NewState=5 MoveSpeed=7
- **修复文件**：`P1GoServer/servers/scene_server/internal/net_func/npc/animal_feed.go`、`freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Animal/Comp/AnimalInteractComp.cs`
- **日期**：2026-04-01
