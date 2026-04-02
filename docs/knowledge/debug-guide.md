# 调试指南

## 客户端日志系统（freelifeclient）

采集时按优先级顺序检查，**目录/文件不存在则跳过并记录 `[源名] 不可用：路径不存在`**。

### 日志源

| 源 ID | 日志系统 | 路径 | 说明 |
|--------|----------|------|------|
| client_mlog_editor | MLog 文件日志 | `freelifeclient/Dist/Logs/*.log` | 编辑器模式，Debug 级别 |
| client_mlog_runtime | MLog 文件日志 | `{persistentDataPath}/Log/*.log` | 运行时构建，Info 级别 |
| unity_console | Unity Console | MCP `read_console` | 编辑器在线时可用 |
| unity_player_log | Unity Player.log | 平台默认路径（见下方） | 运行时崩溃/异常 |
| client_crashsight | CrashSight | SDK 管理 + 云端 | native 崩溃、异常上报 |
| client_cls | 腾讯云 CLS | 云端（ap-shanghai） | 线上日志聚合，需登录控制台查看 |
| client_tapsdk | TapSDK OpenLog | `{persistentDataPath}/OpenlogData/` | 第三方 SDK 日志 |

### MLog 详细说明

- **初始化**：`GameStart.cs` 行 104-106
- **文件格式**：`yyyy-MM-dd_HH-mm-ss.log`
- **最大保留**：10 个文件（`MaxLogFileCount`）
- **日志级别**：Debug / Info / Warning / Error
- **模块分类**：50+ 模块（Net、Gameplay、AI、UI、Scene、Audio、Vehicle、Interaction 等），通过 `MLog.Module("Name")` 创建
- **核心文件**：
  - `Assets/Scripts/3rd/MLog/Runtime/FileLog.cs` — 文件写入，路径定义（行 14-16）
  - `Assets/Scripts/Gameplay/LogModule.cs` — 模块枚举

### Unity Player.log 平台路径

| 平台 | 路径 |
|------|------|
| Windows Editor | `%LOCALAPPDATA%/Unity/Editor/Editor.log` |
| Windows Player | `%USERPROFILE%/AppData/LocalLow/<Company>/<Product>/Player.log` |
| Android | `adb logcat` 或 `{persistentDataPath}/Player.log` |
| iOS | Xcode Console |

### persistentDataPath 各平台值

| 平台 | 路径 |
|------|------|
| Windows | `%USERPROFILE%/AppData/LocalLow/<CompanyName>/<ProductName>/` |
| Android | `/storage/emulated/0/Android/data/<package>/files/` |
| iOS | `<sandbox>/Documents/` |

### 截图采样（视觉类调试）

Unity MCP 的 `manage_camera` 支持单帧截图，不支持录制视频。但可以通过**关键时刻采样**替代连续录制，用于定位视觉/动画/UI 类 bug：

| 采样策略 | 做法 | 适用场景 |
|----------|------|----------|
| 操作前后对比 | 操作前截一张 → 执行操作 → 操作后截一张 | UI 状态异常、布局错乱 |
| 时序采样 | 间隔 1-2 秒连续截 3-5 张 | 动画卡顿、状态切换异常 |
| 多视角采样 | 同一时刻切换不同相机/角度各截一张 | 渲染异常、遮挡问题 |

使用方式：MCP `manage_camera`（action=`capture`），每次调用约 200-500ms 延迟。截图以 base64 返回，**单次采样不超过 5 张**以控制上下文体积。

> 如需高帧率连续录制，应通过 `execute_menu_item` 驱动 Unity Recorder 包（需项目已安装）。

### 采集建议

- **编辑器调试**：优先 `unity_console`（实时），其次 `client_mlog_editor`（`Dist/Logs/` 下最新文件）
- **运行时问题**：优先 `client_mlog_runtime`，其次 `unity_player_log`
- **视觉类问题**：截图采样（见上方），配合 `scene_hierarchy` + `component_data` 交叉验证
- **线上崩溃**：`client_crashsight` 云端查看
- **线上行为异常**：`client_cls` 云端查询
- **第三方 SDK 问题**：`client_tapsdk`
