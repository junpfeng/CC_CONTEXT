# C# 脚本模板（MCP script-execute 用）

> 使用 `FL.NetModule` 时必须加 `Vector2`/`Vector3` using alias 消歧义（见 feedback_netmodule_using_alias）。

## GM 指令发送模板

```csharp
using UnityEngine;
using Vector2 = UnityEngine.Vector2;
using Vector3 = UnityEngine.Vector3;
using FL.NetModule;
public class Script {
    public static object Main() {
        var req = new GMOperateReq();
        req.OperateCmd = "/ke* gm {command} {params}";
        NetCmd.GmOperate(req, res => {});
        return "GM sent: {command}";
    }
}
```

## 传送到指定位置

```csharp
var req = new FL.NetModule.GMOperateReq();
req.OperateCmd = "/ke* gm teleport {x} {y} {z}";
FL.NetModule.NetCmd.GmOperate(req, res => {});
return "Teleport sent";
```

## 读取玩家当前位置

```csharp
var player = FL.Gameplay.Manager.PlayerManager.LocalPlayer;
var pos = player.Transform.position;
return "PlayerPos=" + pos.x.ToString("F1") + "," + pos.y.ToString("F1") + "," + pos.z.ToString("F1");
```

## 模拟摇杆输入移动

```csharp
// 注意：MovementXy 是相机空间，需做世界→相机投影
var input = FL.Gameplay.Manager.InputManager.Instance;
// 设置移动方向后等几秒观察
```
