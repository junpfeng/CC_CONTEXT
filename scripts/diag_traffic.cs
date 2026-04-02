using UnityEngine;
using System.Text;
using System.Reflection;
using System.Linq;
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
        if (asm == null) return sb.Append("Asm not found").ToString();
        var moverType = asm.GetType("Gley.TrafficSystem.Internal.TownTrafficMover");
        var movers = Object.FindObjectsOfType(moverType);
        sb.Append("Movers: ").AppendLine(movers.Length.ToString());
        foreach (var m in movers)
        {
            var mb = m as MonoBehaviour;
            if (mb == null) continue;
            var pos = mb.transform.position;
            float dist = Vector3.Distance(pos, playerPos);
            var pathField = moverType.GetField("_path", BindingFlags.NonPublic | BindingFlags.Instance);
            var pathObj = pathField != null ? pathField.GetValue(m) : null;
            int pathCount = 0;
            if (pathObj != null)
            {
                var countProp = pathObj.GetType().GetProperty("Count");
                pathCount = (int)countProp.GetValue(pathObj);
            }
            var idxField = moverType.GetField("_currentPathIndex", BindingFlags.NonPublic | BindingFlags.Instance);
            int idx = idxField != null ? (int)idxField.GetValue(m) : -1;
            var activeField = moverType.GetField("_isActive", BindingFlags.NonPublic | BindingFlags.Instance);
            bool active = activeField != null && (bool)activeField.GetValue(m);
            var speedField = moverType.GetField("_moveSpeed", BindingFlags.NonPublic | BindingFlags.Instance);
            float speed = speedField != null ? (float)speedField.GetValue(m) : -1;
            sb.Append("  V: p=").Append(pos).Append(" d=").Append(dist.ToString("F0"))
              .Append(" act=").Append(active).Append(" spd=").Append(speed.ToString("F1"))
              .Append(" path=").Append(idx).Append("/").AppendLine(pathCount.ToString());
        }

        var tmType = asm.GetType("Gley.TrafficSystem.Internal.TrafficManager");
        var instProp = tmType.GetProperty("Instance", BindingFlags.Static | BindingFlags.NonPublic);
        var tm = instProp != null ? instProp.GetValue(null) : null;
        if (tm == null) return sb.Append("TM null").ToString();
        var navField = tmType.GetField("_transportGleyNav", BindingFlags.Instance | BindingFlags.NonPublic);
        if (navField == null)
        {
            var navProp = tmType.GetProperty("TransportGleyNav", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
            if (navProp == null) return sb.Append("Nav field/prop not found").ToString();
        }

        var handlerProp = tmType.GetProperty("TrafficWaypointsDataHandler", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
        var handler = handlerProp != null ? handlerProp.GetValue(tm) : null;
        if (handler == null) return sb.Append("Handler null").ToString();
        var wpsProp = handler.GetType().GetProperty("AllTrafficWaypoints", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
        var wpsObj = wpsProp != null ? wpsProp.GetValue(handler) : null;
        if (wpsObj == null) return sb.Append("WPs null").ToString();
        var wps = wpsObj as System.Array;
        sb.Append("WPs: ").AppendLine(wps.Length.ToString());

        int nI = -1; float nD = float.MaxValue;
        for (int i = 0; i < wps.Length; i++)
        {
            var wp = wps.GetValue(i);
            if (wp == null) continue;
            var posField = wp.GetType().GetField("position");
            var wpPos = (Vector3)posField.GetValue(wp);
            float dx = wpPos.x - playerPos.x; float dz = wpPos.z - playerPos.z;
            float d = dx * dx + dz * dz;
            if (d < nD) { nD = d; nI = i; }
        }
        if (nI >= 0)
        {
            var wp = wps.GetValue(nI);
            var posField = wp.GetType().GetField("position");
            var wpPos = (Vector3)posField.GetValue(wp);
            var nbField = wp.GetType().GetField("neighbors");
            var nb = nbField != null ? nbField.GetValue(wp) as int[] : null;
            sb.Append("NearWP[").Append(nI).Append("]: ").Append(wpPos).Append(" d=").Append(Mathf.Sqrt(nD).ToString("F1")).Append("m n=").AppendLine(nb != null ? nb.Length.ToString() : "0");

            if (nb != null && nb.Length > 0)
            {
                for (int j = 0; j < Mathf.Min(3, nb.Length); j++)
                {
                    int ni = nb[j];
                    if (ni >= 0 && ni < wps.Length)
                    {
                        var nwp = wps.GetValue(ni);
                        var nPos = (Vector3)nwp.GetType().GetField("position").GetValue(nwp);
                        sb.Append("  ->WP[").Append(ni).Append("]: ").AppendLine(nPos.ToString());
                    }
                }
            }
        }
        return sb.ToString();
    }
}
