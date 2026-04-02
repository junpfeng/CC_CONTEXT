using UnityEngine;
using System.Text;
using System.Reflection;
using System.Linq;
using System.Collections.Generic;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();
        var playerCtrl = FL.Gameplay.Modules.BigWorld.PlayerManager.Controller;
        if (playerCtrl == null) return "No player";
        var playerPos = playerCtrl.transform.position;
        sb.Append("Player: ").AppendLine(playerPos.ToString());

        var asm = System.AppDomain.CurrentDomain.GetAssemblies()
            .FirstOrDefault(a => a.GetType("Gley.TrafficSystem.Internal.TownTrafficMover") != null);
        if (asm == null) return "Asm not found";
        var moverType = asm.GetType("Gley.TrafficSystem.Internal.TownTrafficMover");
        var movers = Object.FindObjectsOfType(moverType);

        // 找距离玩家最近的一辆车
        float minDist = float.MaxValue;
        Object nearest = null;
        foreach (var m in movers)
        {
            var mb = m as MonoBehaviour;
            if (mb == null) continue;
            float d = Vector3.Distance(mb.transform.position, playerPos);
            if (d < minDist) { minDist = d; nearest = m; }
        }
        if (nearest == null) return sb.Append("No movers").ToString();

        var nearMb = nearest as MonoBehaviour;
        sb.Append("NearestVehicle: ").Append(nearMb.transform.position).Append(" dist=").AppendLine(minDist.ToString("F0"));

        // 读取路径
        var pathField = moverType.GetField("_path", BindingFlags.NonPublic | BindingFlags.Instance);
        var pathObj = pathField.GetValue(nearest);
        if (pathObj == null) return sb.Append("path null").ToString();
        var path = pathObj as List<int>;
        var idxField = moverType.GetField("_currentPathIndex", BindingFlags.NonPublic | BindingFlags.Instance);
        int currentIdx = (int)idxField.GetValue(nearest);

        sb.Append("Path: ").Append(path.Count).Append(" pts, currentIdx=").AppendLine(currentIdx.ToString());

        // 获取 waypointsHandler
        var handlerField = moverType.GetField("_waypointsHandler", BindingFlags.NonPublic | BindingFlags.Instance);
        var handler = handlerField.GetValue(nearest);
        if (handler == null) return sb.Append("handler null").ToString();
        var getPosMethod = handler.GetType().GetMethod("GetPosition", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);

        // 输出当前路径的路点位置（当前点前后各5个）
        int startShow = Mathf.Max(0, currentIdx - 2);
        int endShow = Mathf.Min(path.Count, currentIdx + 8);
        sb.AppendLine("Path waypoints (corrected positions):");
        for (int i = startShow; i < endShow; i++)
        {
            int wpIdx = path[i];
            var wpPos = (Vector3)getPosMethod.Invoke(handler, new object[] { wpIdx });
            string marker = i == currentIdx ? " <-- CURRENT" : "";
            sb.Append("  [").Append(i).Append("] WP").Append(wpIdx).Append(": ").Append(wpPos).AppendLine(marker);
        }

        // 检查路点之间的间距
        sb.AppendLine("Distances between consecutive waypoints:");
        for (int i = startShow; i < endShow - 1; i++)
        {
            var p1 = (Vector3)getPosMethod.Invoke(handler, new object[] { path[i] });
            var p2 = (Vector3)getPosMethod.Invoke(handler, new object[] { path[i + 1] });
            float dx = p2.x - p1.x; float dz = p2.z - p1.z;
            float dist = Mathf.Sqrt(dx * dx + dz * dz);
            sb.Append("  [").Append(i).Append("]->[").Append(i + 1).Append("]: ").Append(dist.ToString("F1")).AppendLine("m");
        }

        // 检查 Raycast 地面在这些路点位置的 Y 值
        sb.AppendLine("Ground Y at waypoint XZ (layer 6):");
        int groundMask = 1 << 6;
        for (int i = startShow; i < endShow; i++)
        {
            var wpPos = (Vector3)getPosMethod.Invoke(handler, new object[] { path[i] });
            if (Physics.Raycast(new Vector3(wpPos.x, 50f, wpPos.z), Vector3.down, out var hit, 100f, groundMask))
                sb.Append("  WP").Append(path[i]).Append(": groundY=").AppendLine(hit.point.y.ToString("F2"));
            else
                sb.Append("  WP").Append(path[i]).AppendLine(": NO GROUND HIT");
        }

        return sb.ToString();
    }
}
