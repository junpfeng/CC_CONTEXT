#!/usr/bin/env python3
"""MCP 测试工具 - 玩家传送通用脚本

用法:
  # 传送到指定坐标
  python3 scripts/mcp_teleport.py 100 60 -200

  # 传送到指定坐标（逗号分隔）
  python3 scripts/mcp_teleport.py 100,60,-200

  # 获取当前玩家位置
  python3 scripts/mcp_teleport.py --pos

  # 传送到预设位置
  python3 scripts/mcp_teleport.py --preset town_center

  # 传送并等待完成后截图验证
  python3 scripts/mcp_teleport.py 100 60 -200 --verify

设计选择: 使用 GM 传送而非模拟移动输入
  - 即时到位，确定性强（精确坐标）
  - 服务端权威（自动处理下车、交互清理、状态同步）
  - 已有完整链路: GM teleport → TeleportPlayerToPoint → TeleportToPointNtf
  - 模拟移动需处理相机空间转换、障碍物、不确定时间等问题，仅测移动系统本身才需要
"""
import sys
import os
import json
import time

# 确保能 import mcp_call
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_call import mcp_call

# 预设坐标点（大世界常用测试位置）
PRESETS = {
    "town_center": (-701.08, 60.82, -1916.53),
    "town_square": (-992.60, 59.83, -2054.04),
    "town_store": (-920.53, 51.58, -1293.86),
    "town_east": (-594.08, 60.64, -1873.99),
    "town_west": (-1009.41, 60.84, -2095.71),
    "highland": (159.78, 102.44, -2092.88),
    "mountain": (96.31, 115.52, -1585.39),
    "beach": (349.35, 57.66, -2122.99),
    "port": (627.52, 61.92, -1928.80),
    "sky_island": (423.64, 1003.16, -2020.85),
    "floating": (270.50, 989.02, -1845.14),
    "spawn": (175.91, 68.91, -1608.50),
}

# 获取当前玩家位置的 C# 脚本
GET_POS_SCRIPT = """
using UnityEngine;
using FL.Gameplay.Manager;

public class Script
{
    public static string Main()
    {
        if (PlayerManager.Controller == null || PlayerManager.Controller.Data == null)
            return "error:PlayerManager not ready";
        var pos = PlayerManager.Controller.Data.Transform.Position;
        var rot = PlayerManager.Controller.Data.TransformQueue.Rotation.eulerAngles;
        return pos.x + "," + pos.y + "," + pos.z + "|" + rot.x + "," + rot.y + "," + rot.z;
    }
}
"""

# 发送 GM 传送命令的 C# 脚本
TELEPORT_SCRIPT_TEMPLATE = """
using FL.Gameplay.Modules.UI.Pages.Panels;

public class Script
{{
    public static async void Main()
    {{
        await AutoMatch.AutoGm("/ke* gm teleport {x},{y},{z}");
    }}
}}
"""


def get_player_position():
    """获取当前玩家位置"""
    result = mcp_call("script-execute", {
        "className": "Script",
        "methodName": "Main",
        "csharpCode": GET_POS_SCRIPT
    }, timeout=10)

    text = result.get("text", str(result))
    if "error:" in text:
        print(f"[ERROR] {text}")
        return None

    try:
        parts = text.split("|")
        pos_parts = parts[0].split(",")
        pos = (float(pos_parts[0]), float(pos_parts[1]), float(pos_parts[2]))
        rot = None
        if len(parts) > 1:
            rot_parts = parts[1].split(",")
            rot = (float(rot_parts[0]), float(rot_parts[1]), float(rot_parts[2]))
        return {"position": pos, "rotation": rot}
    except (ValueError, IndexError) as e:
        print(f"[ERROR] 解析位置失败: {text} ({e})")
        return None


def teleport_to(x, y, z):
    """传送玩家到指定坐标"""
    script = TELEPORT_SCRIPT_TEMPLATE.format(x=x, y=y, z=z)
    result = mcp_call("script-execute", {
        "className": "Script",
        "methodName": "Main",
        "csharpCode": script
    }, timeout=15)
    return result


def verify_position(target_x, target_y, target_z, tolerance=5.0):
    """验证玩家是否到达目标位置附近"""
    time.sleep(2)  # 等待传送动画
    info = get_player_position()
    if info is None:
        return False
    pos = info["position"]
    dx = pos[0] - target_x
    dy = pos[1] - target_y
    dz = pos[2] - target_z
    dist_sq = dx * dx + dy * dy + dz * dz
    ok = dist_sq <= tolerance * tolerance
    if ok:
        print(f"[OK] 到达目标位置 ({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f})")
    else:
        import math
        print(f"[WARN] 位置偏差 {math.sqrt(dist_sq):.1f}m: 当前({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f}) 目标({target_x:.1f}, {target_y:.1f}, {target_z:.1f})")
    return ok


def screenshot():
    """截图验证"""
    result = mcp_call("screenshot-game-view", {}, timeout=15)
    return result


def parse_coords(args):
    """解析坐标参数，支持 'x y z' 和 'x,y,z' 格式"""
    if len(args) == 1 and "," in args[0]:
        parts = args[0].split(",")
        return float(parts[0]), float(parts[1]), float(parts[2])
    elif len(args) >= 3:
        return float(args[0]), float(args[1]), float(args[2])
    else:
        return None


def print_presets():
    """打印所有预设位置"""
    print("预设位置:")
    for name, (x, y, z) in sorted(PRESETS.items()):
        print(f"  {name:16s} → ({x:.1f}, {y:.1f}, {z:.1f})")


def main():
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        print(__doc__)
        print_presets()
        return

    do_verify = "--verify" in args
    args = [a for a in args if a != "--verify"]

    # 获取当前位置
    if args[0] == "--pos":
        info = get_player_position()
        if info:
            pos = info["position"]
            print(f"位置: {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f}")
            if info["rotation"]:
                rot = info["rotation"]
                print(f"朝向: {rot[0]:.1f}, {rot[1]:.1f}, {rot[2]:.1f}")
        return

    # 列出预设
    if args[0] == "--list":
        print_presets()
        return

    # 预设传送
    if args[0] == "--preset":
        name = args[1] if len(args) > 1 else ""
        if name not in PRESETS:
            print(f"[ERROR] 未知预设 '{name}'")
            print_presets()
            return
        x, y, z = PRESETS[name]
        print(f"传送到预设 [{name}]: ({x:.1f}, {y:.1f}, {z:.1f})")
        teleport_to(x, y, z)
        if do_verify:
            verify_position(x, y, z)
            screenshot()
        return

    # 坐标传送
    coords = parse_coords(args)
    if coords is None:
        print("[ERROR] 无法解析坐标，用法: mcp_teleport.py x y z 或 mcp_teleport.py x,y,z")
        return

    x, y, z = coords
    print(f"传送到: ({x:.1f}, {y:.1f}, {z:.1f})")
    teleport_to(x, y, z)

    if do_verify:
        verify_position(x, y, z)
        screenshot()


if __name__ == "__main__":
    main()
