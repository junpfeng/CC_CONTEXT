---
name: unity-login
description: 自动操控 Unity Editor 完成游戏登录或退出登录，进入/返回登录界面。
argument-hint: "[login|logout|relogin，默认 login]"
---

你是 Unity 游戏自动化专家。全程自动推进，仅在真正阻塞时暂停询问。

## MCP 工具集

本 skill 使用 `mcp__ai-game-developer__*` 工具集（Coplaydev Unity MCP）。

| 用途 | 工具 |
|------|------|
| 检查 Editor 状态 | `editor-application-get-state` |
| 控制 Play/Stop | `editor-application-set-state` |
| Game View 截图 | `screenshot-game-view` |
| 查看控制台日志 | `console-get-logs` |
| 查找 GameObject | `gameobject-find` |
| 查看场景层级 | `scene-get-data` |
| 执行 C# 代码 | `script-execute` |

## 重要技术约束

- 登录界面使用 **UI Toolkit** 渲染（非 uGUI），`gameobject-find` **无法找到** UI Toolkit 按钮
- `screenshot-game-view` **可以截到** UI Toolkit 内容（它截的是 Game View 完整画面）
- `gameobject-find` 查找 `TownPlayer` **不可靠**（即使已登录也可能返回空），不作为唯一判断依据
- Game View 截图可能失败（窗口未打开），需先用 `script-execute` 聚焦 Game View 窗口
- UI Toolkit 按钮点击使用 `ClickEvent.GetPooled()` + `SendEvent()` 方式触发

## 状态检测

**检测是否已在游戏中，按优先级尝试：**

1. `screenshot-game-view` 截图查看实际画面（最可靠）
2. `scene-get-data` 查看场景根对象，判断是否有游戏场景内容
3. `gameobject-find` 查找 `[PlayerManager]` 下是否有子对象（辅助判断）

| 检测结果 | $ARGUMENTS | 执行 |
|----------|------------|------|
| 未在游戏中 | 无 / `login` | → 进入登录流程 |
| 已在游戏中 | 无 / `login` | → 输出"已在游戏中"，结束 |
| 未在游戏中 | `logout` | → 输出"当前未登录"，结束 |
| 已在游戏中 | `logout` | → 进入退出登录流程 |
| 已在游戏中 | `relogin` | → 先退出登录，完成后执行登录流程 |

---

## 登录流程

### Step 0 — 确认 Unity Editor 可用

调用 `editor-application-get-state` 检查连通性和编译状态。
如果 `IsCompiling=true` → 等待编译完成（重试间隔 5s，最多 30s）。
如果连接失败 → 报告"Unity Editor 未连接，请确认 MCP Server 已启动"。

### Step 1 — 进入 Play 模式

先调用 `editor-application-get-state` 检查 `IsPlaying` 状态。

若当前不在 Play 模式：
```
editor-application-set-state(isPlaying=true)
```

等待 10s 后再次检查状态确认已进入 Play 模式。

### Step 1.5 — 确保 Game View 可用

首次截图可能失败（Game View 窗口未打开）。如果 `screenshot-game-view` 返回错误，先执行：

```csharp
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var gameViewType = System.Type.GetType("UnityEditor.GameView,UnityEditor");
        if (gameViewType != null)
            UnityEditor.EditorWindow.GetWindow(gameViewType, false, "Game", true);
        return "Game View focused";
    }
}
```

### Step 2 — 等待游戏初始化并处理登录界面

Editor 模式下游戏**不一定自动登录**，可能停在登录界面。每 10s 截图检查，最多等 60s。

**可能出现的画面及处理：**

| 画面 | 说明 | 处理 |
|------|------|------|
| 黑屏 / 截图失败 | 游戏初始化中 | 等待，每 10s 重试 |
| 闪屏 + 公告弹窗 | 公告面板遮挡登录 | → Step 3a 关闭公告 |
| 闪屏 + "TapTap 登录" 按钮 | 登录界面 | → Step 3b 点击登录 |
| "点击任意处继续" | 登录成功待确认 | → Step 3c 点击继续 |
| 游戏 HUD（摇杆、小地图） | 已登录成功 | → Step 4 |

### Step 3 — 处理登录界面（经验证的代码）

**3a. 关闭公告弹窗**

公告面板在 `SplashAnnouncement` 模板下，其关闭按钮为 `btn-close`：

```csharp
using UnityEngine;
using UnityEngine.UIElements;
public class Script
{
    public static object Main()
    {
        var docs = Object.FindObjectsOfType<UIDocument>();
        foreach (var doc in docs)
        {
            if (doc.rootVisualElement == null) continue;
            var announcement = doc.rootVisualElement.Q("SplashAnnouncement");
            if (announcement == null) continue;
            var closeBtn = announcement.Q<Button>("btn-close");
            if (closeBtn == null) return "btn-close not found in SplashAnnouncement";
            using (var evt = ClickEvent.GetPooled())
            {
                evt.target = closeBtn;
                closeBtn.SendEvent(evt);
            }
            return "Closed announcement";
        }
        return "SplashAnnouncement not found";
    }
}
```

关闭后等 3s 再截图确认。

**3b. 点击登录按钮**

登录按钮名为 `btn-login`：

```csharp
using UnityEngine;
using UnityEngine.UIElements;
public class Script
{
    public static object Main()
    {
        var docs = Object.FindObjectsOfType<UIDocument>();
        foreach (var doc in docs)
        {
            if (doc.rootVisualElement == null) continue;
            var loginBtn = doc.rootVisualElement.Q<Button>("btn-login");
            if (loginBtn == null) continue;
            using (var evt = ClickEvent.GetPooled())
            {
                evt.target = loginBtn;
                loginBtn.SendEvent(evt);
            }
            return "Clicked btn-login";
        }
        return "btn-login not found";
    }
}
```

点击后等 10s（需要网络连接服务器），再截图确认。

**3c. 点击"点击任意处继续"**

继续按钮名为 `btn-continue`：

```csharp
using UnityEngine;
using UnityEngine.UIElements;
public class Script
{
    public static object Main()
    {
        var docs = Object.FindObjectsOfType<UIDocument>();
        foreach (var doc in docs)
        {
            if (doc.rootVisualElement == null) continue;
            var continueBtn = doc.rootVisualElement.Q<Button>("btn-continue");
            if (continueBtn == null) continue;
            using (var evt = ClickEvent.GetPooled())
            {
                evt.target = continueBtn;
                continueBtn.SendEvent(evt);
            }
            return "Clicked btn-continue";
        }
        return "btn-continue not found";
    }
}
```

点击后等 15s（场景加载），再截图确认。

**3d. 控制台日志辅助诊断**

如果上述步骤不生效，调用 `console-get-logs(logTypeFilter="Error", lastMinutes=2, maxEntries=10)` 查看阻塞性错误。

### Step 4 — 确认登录完成并验证场景

**4a. 确认已进入游戏**

`screenshot-game-view` 截图确认看到游戏 HUD（摇杆、小地图、技能按钮等）。

**4b. 验证当前场景（重要！）**

登录后**不一定**进入小镇场景，需要通过代码检测：

```csharp
using UnityEngine;
public class Script
{
    public static object Main()
    {
        try
        {
            bool inTown = FL.Gameplay.Manager.SceneManager.IsInTown;
            var uType = FL.Gameplay.Manager.SceneManager.UniverseType;
            return "IsInTown=" + inTown + " UniverseType=" + uType;
        }
        catch (System.Exception ex) { return "Error: " + ex.Message; }
    }
}
```

> ⚠️ 不要用 `Type.GetType()` 反射，直接引用类型即可（都在 Assembly-CSharp 中）。

**4c. 如果不在小镇，通过 GM 指令进入**

```csharp
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var req = new FL.NetModule.EnterTowmReq();
        FL.NetModule.NetCmd.StartEnterTown(req);
        return "EnterTown requested";
    }
}
```

发送后等待 15-20s 场景加载，再用 4b 的检测脚本确认 `IsInTown=True`。

输出"登录完成，已进入小镇场景"，结束。

---

## 退出登录流程

### Logout Step 1 — 停止 Play 模式

最简单可靠的退出方式：
```
editor-application-set-state(isPlaying=false)
```

如需保持 Play 模式但退回登录界面：
- 通过 `script-execute` 调用 `LoginManager` 的 `HandleLogOutAndClearData()` 方法

### Logout Step 2 — 确认退出完成

调用 `editor-application-get-state` 确认 `IsPlaying=false`（或确认已回到登录界面）。

输出"已退出登录"，结束。

---

## 被动下线（仅供参考）

| 场景 | 触发 | 客户端行为 |
|------|------|-----------|
| 顶号 | 服务器推送 `OtherLogin` | 弹窗 → 自动清理 → 返回登录界面 |
| 被踢 | 服务器推送 `Kick` | 弹窗 → 自动清理 → 返回登录界面 |
| 断线 | 网络中断 | 自动重连最多 5 次，失败后返回登录界面 |

---

## 错误处理

| 现象 | 处理 |
|------|------|
| MCP 连接失败 | 报告"Unity Editor MCP 未连接"，建议检查 MCP Server |
| MCP 工具在 Stop 后丢失 | **已知问题**：退出 Play 模式后 Claude Code MCP 客户端可能断连（Unity 端 SSE 服务仍在运行）。当前会话无法自动恢复，需提示用户重启 Claude Code 会话。可通过 `netstat -ano \| grep ":57036 "` 确认 Unity MCP 端口仍在监听 |
| Game View 截图失败 | 用 `script-execute` 聚焦 Game View 窗口后重试 |
| 编译中 | 等待最多 30s，超时报告 |
| 黑屏超过 60s | `console-get-logs(logTypeFilter="Error")` 采集错误日志，报告阻塞 |
| 服务端未启动 | 读取 `docs/tools/server-ps1.md`，调用 `scripts/server.ps1` 起服 |
| RenderQuality 空引用 | 已知问题，不阻塞登录流程，忽略 |
| AudioManager SetGmeUserId Error | 已知问题，开发环境 UserID < 10000，语音聊天不可用但不阻塞登录 |
| MCP HubConnection reconnecting | Unity MCP 插件的 SignalR 重连日志，不影响游戏功能，但可能导致 Claude Code MCP 工具丢失 |

---

## 反复测试注意事项

反复 login/logout 测试时的关键经验：

1. **单次 login→logout 全链路约 90s**：Play 启动(~25s) → 初始化(~5s) → 关公告 → 登录(~10s) → 继续(~15s) → 验证 → Stop(~10s)
2. **初次 script-execute 可能返回空**：Play 模式刚激活时执行 C# 脚本常返回空值，需重试机制（推荐 3 次，间隔 3s）
3. **登录后 UI 状态**：点击 btn-login 后，btn-login 可能仍然可见（等待服务器响应），此时需要等 10s 后再检查 btn-continue
4. **MCP 断连降级方案**：Claude Code MCP 工具丢失后，可通过 `scripts/mcp_call.py` 直连 Unity MCP SSE 服务（端口 57036）继续操作
5. **自动化测试脚本**：`scripts/auto_login_test.py <轮数>` 可批量运行 login/logout 循环，已验证 6 轮 100% 通过

---

## 关键代码位置（按需查阅）

| 内容 | 路径 |
|------|------|
| 登录/登出核心逻辑 | `Assets/Scripts/Gameplay/Modules/UI/Managers/Account/Login/LoginManager.cs` |
| 清理流程 | `LoginManager.cs:HandleLogOutAndClearData()` |
| FSM 状态 | `Assets/Scripts/Gameplay/Managers/LaunchManager/GameFsm.cs` |
| 重连逻辑 | `Assets/Scripts/Gameplay/Managers/Net/NetManager.Reconnect.cs` |
