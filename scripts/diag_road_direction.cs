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

        var asm = System.AppDomain.CurrentDomain.GetAssemblies()
            .FirstOrDefault(a => a.GetType("Gley.TrafficSystem.Internal.TrafficManager") != null);
        var tmType = asm.GetType("Gley.TrafficSystem.Internal.TrafficManager");
        var instProp = tmType.GetProperty("Instance", BindingFlags.Static | BindingFlags.NonPublic);
        var tm = instProp.GetValue(null);
        var navField = tmType.GetField("TransportGleyNav", BindingFlags.Instance | BindingFlags.Public);
        var nav = navField.GetValue(tm);
        var rpProp = nav.GetType().GetProperty("RoadPoints");
        var rpList = rpProp.GetValue(nav) as System.Collections.IList;

        // 找玩家附近50m内的路点，分析方向
        int nearCount = 0;
        int hasOtherLanes = 0;
        int hasPrev = 0;
        int multiNeighbor = 0;
        for (int i = 0; i < rpList.Count; i++)
        {
            var rp = rpList[i];
            var posField = rp.GetType().GetField("position");
            var posObj = posField.GetValue(rp);
            float rx = (float)posObj.GetType().GetField("x").GetValue(posObj);
            float rz = (float)posObj.GetType().GetField("z").GetValue(posObj);
            float dx = rx - playerPos.x; float dz = rz - playerPos.z;
            if (dx * dx + dz * dz > 2500f) continue; // 50m radius
            nearCount++;

            var nbField = rp.GetType().GetField("neighbors");
            var nbList = nbField.GetValue(rp) as System.Collections.IList;
            if (nbList != null && nbList.Count > 1) multiNeighbor++;

            var prevField = rp.GetType().GetField("prev");
            var prevList = prevField.GetValue(rp) as System.Collections.IList;
            if (prevList != null && prevList.Count > 0) hasPrev++;

            var olField = rp.GetType().GetField("OtherLanes");
            var olList = olField.GetValue(rp) as System.Collections.IList;
            if (olList != null && olList.Count > 0) hasOtherLanes++;
        }

        sb.Append("Near player (50m): ").Append(nearCount).AppendLine(" road points");
        sb.Append("  hasNeighbors>1: ").AppendLine(multiNeighbor.ToString());
        sb.Append("  hasPrev: ").AppendLine(hasPrev.ToString());
        sb.Append("  hasOtherLanes: ").AppendLine(hasOtherLanes.ToString());

        // Sample: pick closest point and show its neighbors/prev/OtherLanes
        float minD = float.MaxValue; int minI = -1;
        for (int i = 0; i < rpList.Count; i++)
        {
            var rp = rpList[i];
            var posObj = rp.GetType().GetField("position").GetValue(rp);
            float rx = (float)posObj.GetType().GetField("x").GetValue(posObj);
            float rz = (float)posObj.GetType().GetField("z").GetValue(posObj);
            float dx = rx - playerPos.x; float dz = rz - playerPos.z;
            float d = dx * dx + dz * dz;
            if (d < minD) { minD = d; minI = i; }
        }
        if (minI >= 0)
        {
            var rp = rpList[minI];
            var nbList = rp.GetType().GetField("neighbors").GetValue(rp) as System.Collections.IList;
            var prevList = rp.GetType().GetField("prev").GetValue(rp) as System.Collections.IList;
            var olList = rp.GetType().GetField("OtherLanes").GetValue(rp) as System.Collections.IList;

            sb.Append("Closest RP[").Append(minI).Append("]: d=").Append(Mathf.Sqrt(minD).ToString("F1")).AppendLine("m");
            sb.Append("  neighbors: ");
            if (nbList != null) foreach (var n in nbList) sb.Append(n).Append(" ");
            sb.AppendLine();
            sb.Append("  prev: ");
            if (prevList != null) foreach (var p in prevList) sb.Append(p).Append(" ");
            sb.AppendLine();
            sb.Append("  OtherLanes: ");
            if (olList != null) foreach (var o in olList) sb.Append(o).Append(" ");
            sb.AppendLine();

            // Show neighbor direction vs prev direction
            if (nbList != null && nbList.Count > 0)
            {
                int nIdx = (int)nbList[0];
                var nRp = rpList[nIdx];
                var nPos = nRp.GetType().GetField("position").GetValue(nRp);
                float nx = (float)nPos.GetType().GetField("x").GetValue(nPos);
                float nz = (float)nPos.GetType().GetField("z").GetValue(nPos);
                var rpPos = rp.GetType().GetField("position").GetValue(rp);
                float cx = (float)rpPos.GetType().GetField("x").GetValue(rpPos);
                float cz = (float)rpPos.GetType().GetField("z").GetValue(rpPos);
                sb.Append("  neighbor dir: (").Append((nx-cx).ToString("F1")).Append(",").Append((nz-cz).ToString("F1")).AppendLine(")");
            }
            if (olList != null && olList.Count > 0)
            {
                int oIdx = (int)olList[0];
                if (oIdx >= 0 && oIdx < rpList.Count)
                {
                    var oRp = rpList[oIdx];
                    var oNb = oRp.GetType().GetField("neighbors").GetValue(oRp) as System.Collections.IList;
                    if (oNb != null && oNb.Count > 0)
                    {
                        int onIdx = (int)oNb[0];
                        var onRp = rpList[onIdx];
                        var onPos = onRp.GetType().GetField("position").GetValue(onRp);
                        float onx = (float)onPos.GetType().GetField("x").GetValue(onPos);
                        float onz = (float)onPos.GetType().GetField("z").GetValue(onPos);
                        var oPos = oRp.GetType().GetField("position").GetValue(oRp);
                        float ox = (float)oPos.GetType().GetField("x").GetValue(oPos);
                        float oz = (float)oPos.GetType().GetField("z").GetValue(oPos);
                        sb.Append("  otherLane dir: (").Append((onx-ox).ToString("F1")).Append(",").Append((onz-oz).ToString("F1")).AppendLine(")");
                    }
                }
            }
        }

        return sb.ToString();
    }
}
