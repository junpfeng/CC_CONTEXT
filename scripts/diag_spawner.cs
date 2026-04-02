using UnityEngine;
using System.Text;
using System.Reflection;
using System.Linq;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();
        
        // 检查 TrafficManager 路网
        var asm = System.AppDomain.CurrentDomain.GetAssemblies()
            .FirstOrDefault(a => a.GetType("Gley.TrafficSystem.Internal.TrafficManager") != null);
        var tmType = asm.GetType("Gley.TrafficSystem.Internal.TrafficManager");
        var instProp = tmType.GetProperty("Instance", BindingFlags.Static | BindingFlags.NonPublic);
        var tm = instProp.GetValue(null);
        
        var initMethod = tmType.GetMethod("IsInitialized", BindingFlags.Public | BindingFlags.Instance);
        bool inited = (bool)initMethod.Invoke(tm, null);
        sb.Append("TM initialized: ").AppendLine(inited.ToString());
        
        var navField = tmType.GetField("TransportGleyNav", BindingFlags.Instance | BindingFlags.Public);
        var nav = navField.GetValue(tm);
        if (nav == null) return sb.Append("Nav is NULL").ToString();
        
        var rpProp = nav.GetType().GetProperty("RoadPoints");
        var rpList = rpProp.GetValue(nav) as System.Collections.IList;
        sb.Append("RoadPoints: ").AppendLine(rpList != null ? rpList.Count.ToString() : "null");
        
        // 检查路点是否有 neighbors
        if (rpList != null && rpList.Count > 0)
        {
            int withNeighbors = 0;
            for (int i = 0; i < Mathf.Min(rpList.Count, 100); i++)
            {
                var rp = rpList[i];
                var nbField = rp.GetType().GetField("neighbors");
                var nbList = nbField.GetValue(rp) as System.Collections.IList;
                if (nbList != null && nbList.Count > 0) withNeighbors++;
            }
            sb.Append("First 100 with neighbors: ").AppendLine(withNeighbors.ToString());
        }
        
        // 检查 spawner 状态
        var spawnerType = asm.GetType("Gley.TrafficSystem.Internal.TownTrafficSpawner");
        var spawnerInst = spawnerType.GetProperty("Instance", BindingFlags.Static | BindingFlags.Public);
        var spawner = spawnerInst.GetValue(null);
        
        var isSpawning = spawnerType.GetField("_isSpawning", BindingFlags.NonPublic | BindingFlags.Instance);
        var spawnedCount = spawnerType.GetField("_spawnedCount", BindingFlags.NonPublic | BindingFlags.Instance);
        sb.Append("Spawner: isSpawning=").Append(isSpawning.GetValue(spawner))
          .Append(" count=").AppendLine(spawnedCount.GetValue(spawner).ToString());
        
        // 手动测试 PickSpawnPosition
        var playerPos = FL.Gameplay.Modules.BigWorld.PlayerManager.Controller?.transform.position ?? Vector3.zero;
        sb.Append("Player: ").AppendLine(playerPos.ToString());
        
        return sb.ToString();
    }
}
