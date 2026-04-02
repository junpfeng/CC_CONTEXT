# 召唤轮盘 (Summon Wheel)

## 核心需求
在现有轮盘体系中新增一个独立的"召唤轮盘"面板，视觉风格类似 PoseWheel 的圆形扇区布局，包含两个功能槽位：
1. 召唤狗（复用 SummonDogPanel 的网络逻辑）
2. 叫车（复用 PhoneMyCarPanel 的车辆召唤逻辑）

## 调研上下文

### 现有轮盘体系
- PoseWheel（12槽，表情）、WeaponWheel（8槽，武器）、HandheldWheel（8槽，手持物）、RadioWheel（12槽，电台）
- 无公共基类，各轮盘独立实现 Panel→View→Widget 架构
- PoseWheel 无翻页机制（固定12槽），HandheldWheel 有 nextButton/lastButton 翻页

### 召唤狗逻辑（SummonDogPanel.cs + PoseWheelPanel.cs）
- 网络请求：`NetCmd.SummonDog(new SummonDogReq(), callback)`
- 2秒本地冷却
- 错误码 14005 = 附近没有狗
- 成功后关闭面板 + ShowCommonTips("召唤成功！")

### 叫车逻辑（PhoneMyCarPanel.cs）
- 获取车辆列表：`NetCmd.GetAllSelfVehicle(new GetAllSelfVehicleReq(), callback)`
- 展示拥有的车辆（HP/距离/损坏状态）
- 选择车辆后召唤，通过 EventId 通知成功/失败
- 有独立的 PhoneMyCarOptionWidget 展示每辆车

### UI 注册方式
- PanelEnum 枚举注册 + UIConfig.json 配置
- UXML 定义布局（Group_Mobile/ + Group_PC/）
- UIManager.Open<T>() / UIManager.Close(PanelEnum)

### 关键文件路径
- PoseWheelPanel: `Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/PoseWheelPanel.cs`
- PoseWheelView: `Assets/Scripts/Gameplay/Modules/UI/Pages/Views/PoseWheelView.cs`
- SummonDogPanel: `Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/SummonDogPanel.cs`
- PhoneMyCarPanel: `Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/PhoneMyCarPanel.cs`
- UIPanelEnum: `Assets/Scripts/Gameplay/Modules/UI/Pages/Config/UIPanelEnum.cs`
- UIConfig.json: `Assets/PackResources/UI/PanelSettings/UIConfig.json`

## 范围边界
- 做：新建独立的 SummonWheelPanel，包含召唤狗和叫车两个功能
- 不做：修改现有 PoseWheel、不做翻页机制（仅2个功能不需要翻页）

## 初步理解
创建一个新的独立轮盘面板 SummonWheelPanel，视觉上类似 PoseWheel 的圆形布局但槽位更少（2个），每个扇区对应一个召唤功能。点击扇区触发对应的召唤逻辑。

## 确认方案

方案摘要：召唤轮盘 (Summon Wheel)

核心思路：新建独立的 SummonWheelPanel，复用 PoseWheel 的圆形扇区布局模式，初始2个功能槽位，架构支持后续扩展更多槽位。

### 锁定决策

客户端：
- 新增 `SummonWheelPanel` + `SummonWheelView`，独立于 PoseWheel
- 采用 PoseWheel 同款的角度选择算法（`Atan2` 计算扇区），槽位数量数据驱动（非硬编码2个）
- 初始2个功能槽位：召唤狗（左半圆）、叫车（右半圆）
- 快捷键 `O` 打开轮盘，通过 InputSystem 注册
- 召唤狗：复用 `NetCmd.SummonDog()` 逻辑，2s冷却，成功后关闭轮盘 + ShowCommonTips
- 叫车：点击扇区 → 关闭召唤轮盘 → 打开 `PhoneMyCarPanel`
- UXML 布局：Group_Mobile + Group_PC 各一份，扇区用 `MButton` + 图标容器
- PanelEnum 新增 `SummonWheel`，UIConfig.json 注册

扩展性设计：
- 槽位数据用列表驱动（类似 PoseWheel 的 SlotView 列表），新增功能只需加数据+处理回调
- 角度计算按实际槽位数动态分配（360°/N）

不做：
- 不修改现有 PoseWheel / PhoneMyCarPanel
- 不做翻页机制
- 不涉及服务端改动

### 待细化
- UXML 具体视觉样式（扇区背景色、图标资源）由实现阶段参考 PoseWheel 样式确定
- 从 PoseWheel 移除现有的召唤狗按钮（可后续单独做）

### 验收标准
- 按快捷键 O 打开召唤轮盘，显示2个扇区（召唤狗/叫车）
- 鼠标移到扇区有高亮反馈
- 点击召唤狗扇区：发送网络请求，成功后关闭轮盘并提示
- 点击叫车扇区：关闭召唤轮盘，打开 PhoneMyCarPanel
- 编译通过（Unity 无 CS 错误）
