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
            .FirstOrDefault(a => a.GetType("Gley.TrafficSystem.Internal.TrafficManager") != null);
        if (asm == null) return "Asm not found";
        var tmType = asm.GetType("Gley.TrafficSystem.Internal.TrafficManager");
        var instProp = tmType.GetProperty("Instance", BindingFlags.Static | BindingFlags.NonPublic);
        var tm = instProp != null ? instProp.GetValue(null) : null;
        if (tm == null) return "TM null";

        // TransportGleyNav is public field
        var navField = tmType.GetField("TransportGleyNav", BindingFlags.Instance | BindingFlags.Public);
        var nav = navField != null ? navField.GetValue(tm) : null;
        if (nav == null) return sb.Append("Nav null").ToString();

        var rpProp = nav.GetType().GetProperty("RoadPoints");
        var rpList = rpProp != null ? rpProp.GetValue(nav) as System.Collections.IList : null;
        if (rpList == null) return sb.Append("RoadPoints null").ToString();
        sb.Append("RoadPoints: ").AppendLine(rpList.Count.ToString());

        // Find 5 nearest road points to player (XZ)
        int[] nearIdx = new int[5];
        float[] nearDist = new float[5];
        for (int i = 0; i < 5; i++) { nearIdx[i] = -1; nearDist[i] = float.MaxValue; }

        for (int i = 0; i < rpList.Count; i++)
        {
            var rp = rpList[i];
            var posProp = rp.GetType().GetField("position");
            if (posProp == null) continue;
            var posObj = posProp.GetValue(rp);
            // JVector3 has x,y,z fields
            var xf = posObj.GetType().GetField("x");
            var zf = posObj.GetType().GetField("z");
            if (xf == null || zf == null) continue;
            float rx = (float)xf.GetValue(posObj);
            float rz = (float)zf.GetValue(posObj);
            float dx = rx - playerPos.x;
            float dz = rz - playerPos.z;
            float d = dx * dx + dz * dz;
            for (int j = 0; j < 5; j++)
            {
                if (d < nearDist[j])
                {
                    for (int k = 4; k > j; k--) { nearIdx[k] = nearIdx[k-1]; nearDist[k] = nearDist[k-1]; }
                    nearIdx[j] = i;
                    nearDist[j] = d;
                    break;
                }
            }
        }

        sb.AppendLine("Nearest raw RoadPoints to player:");
        for (int i = 0; i < 5; i++)
        {
            if (nearIdx[i] < 0) continue;
            var rp = rpList[nearIdx[i]];
            var posObj = rp.GetType().GetField("position").GetValue(rp);
            var xf = posObj.GetType().GetField("x");
            var yf = posObj.GetType().GetField("y");
            var zf = posObj.GetType().GetField("z");
            float rx = (float)xf.GetValue(posObj);
            float ry = (float)yf.GetValue(posObj);
            float rz = (float)zf.GetValue(posObj);
            var nbField = rp.GetType().GetField("neighbors");
            var nbList = nbField != null ? nbField.GetValue(rp) as System.Collections.IList : null;
            int nbCount = nbList != null ? nbList.Count : 0;
            sb.Append("  RP[").Append(nearIdx[i]).Append("]: raw=(").Append(rx.ToString("F1")).Append(",").Append(ry.ToString("F1")).Append(",").Append(rz.ToString("F1"))
              .Append(") d=").Append(Mathf.Sqrt(nearDist[i]).ToString("F1")).Append("m nb=").AppendLine(nbCount.ToString());
        }

        // Also do a ground raycast at player pos to confirm ground layer
        int groundMask = 1 << 6;
        if (Physics.Raycast(new Vector3(playerPos.x, 50f, playerPos.z), Vector3.down, out var hit, 100f, groundMask))
            sb.Append("Ground@player: Y=").AppendLine(hit.point.y.ToString("F2"));
        else
            sb.AppendLine("Ground@player: NO HIT on layer 6");

        // Raycast at a vehicle cluster position
        if (Physics.Raycast(new Vector3(-15.3f, 50f, 0.9f), Vector3.down, out var hit2, 100f, groundMask))
            sb.Append("Ground@(-15.3,0.9): Y=").AppendLine(hit2.point.y.ToString("F2"));
        else
            sb.AppendLine("Ground@(-15.3,0.9): NO HIT");

        if (Physics.Raycast(new Vector3(167.6f, 50f, -135.6f), Vector3.down, out var hit3, 100f, groundMask))
            sb.Append("Ground@(167.6,-135.6): Y=").AppendLine(hit3.point.y.ToString("F2"));
        else
            sb.AppendLine("Ground@(167.6,-135.6): NO HIT");

        return sb.ToString();
    }
}
