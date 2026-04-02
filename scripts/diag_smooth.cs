using UnityEngine;
using System.Text;
using System.Reflection;
using System.Linq;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();
        var asm = System.AppDomain.CurrentDomain.GetAssemblies()
            .FirstOrDefault(a => a.GetType("Gley.TrafficSystem.Internal.TownTrafficMover") != null);
        if (asm == null) return "No asm";
        var moverType = asm.GetType("Gley.TrafficSystem.Internal.TownTrafficMover");
        var movers = Object.FindObjectsOfType(moverType);
        
        var trackField = moverType.GetField("_track", BindingFlags.NonPublic | BindingFlags.Instance);
        var idxField = moverType.GetField("_trackIndex", BindingFlags.NonPublic | BindingFlags.Instance);
        var activeField = moverType.GetField("_isActive", BindingFlags.NonPublic | BindingFlags.Instance);
        
        var playerCtrl = FL.Gameplay.Modules.BigWorld.PlayerManager.Controller;
        var playerPos = playerCtrl != null ? playerCtrl.transform.position : Vector3.zero;
        sb.Append("Player: ").AppendLine(playerPos.ToString());
        sb.Append("Movers: ").AppendLine(movers.Length.ToString());
        
        // 只显示最近5辆
        var sorted = movers.Cast<MonoBehaviour>()
            .OrderBy(m => Vector3.Distance(m.transform.position, playerPos))
            .Take(5).ToArray();
        
        foreach (var m in sorted)
        {
            var pos = m.transform.position;
            float dist = Vector3.Distance(pos, playerPos);
            bool active = activeField != null && (bool)activeField.GetValue(m);
            int trackIdx = idxField != null ? (int)idxField.GetValue(m) : -1;
            var trackObj = trackField != null ? trackField.GetValue(m) : null;
            int trackCount = 0;
            if (trackObj != null)
            {
                var countProp = trackObj.GetType().GetProperty("Count");
                trackCount = countProp != null ? (int)countProp.GetValue(trackObj) : 0;
            }
            var fwd = m.transform.forward;
            sb.Append("  d=").Append(dist.ToString("F0"))
              .Append(" p=").Append(pos.ToString("F1"))
              .Append(" act=").Append(active)
              .Append(" trk=").Append(trackIdx).Append("/").Append(trackCount)
              .Append(" fwd=").AppendLine(fwd.ToString("F2"));
        }
        return sb.ToString();
    }
}
