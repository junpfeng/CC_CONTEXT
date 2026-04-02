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
            .FirstOrDefault(a => a.GetType("Gley.TrafficSystem.Internal.TrafficManager") != null);
        if (asm == null) return "No asm";
        var tmType = asm.GetType("Gley.TrafficSystem.Internal.TrafficManager");
        var instProp = tmType.GetProperty("Instance", BindingFlags.Static | BindingFlags.NonPublic);
        var tm = instProp != null ? instProp.GetValue(null) : null;
        if (tm == null) return "TM null";
        
        var navField = tmType.GetField("TransportGleyNav", BindingFlags.Instance | BindingFlags.Public);
        var nav = navField != null ? navField.GetValue(tm) : null;
        sb.Append("Nav: ").AppendLine(nav != null ? "exists" : "NULL");
        
        if (nav != null)
        {
            var rpProp = nav.GetType().GetProperty("RoadPoints");
            if (rpProp != null)
            {
                var rpList = rpProp.GetValue(nav) as System.Collections.IList;
                sb.Append("RoadPoints: ").AppendLine(rpList != null ? rpList.Count.ToString() : "null");
                
                if (rpList != null && rpList.Count > 0)
                {
                    int withNb = 0;
                    for (int i = 0; i < rpList.Count; i++)
                    {
                        var rp = rpList[i];
                        var nbField = rp.GetType().GetField("neighbors");
                        if (nbField != null)
                        {
                            var nbList = nbField.GetValue(rp) as System.Collections.IList;
                            if (nbList != null && nbList.Count > 0) withNb++;
                        }
                    }
                    sb.Append("With neighbors: ").Append(withNb).Append("/").AppendLine(rpList.Count.ToString());
                }
            }
        }

        // Spawner state
        var spawnerType = asm.GetType("Gley.TrafficSystem.Internal.TownTrafficSpawner");
        if (spawnerType != null)
        {
            var instField = spawnerType.GetField("_instance", BindingFlags.Static | BindingFlags.NonPublic);
            var spawner = instField != null ? instField.GetValue(null) : null;
            if (spawner != null)
            {
                var isSpawning = spawnerType.GetField("_isSpawning", BindingFlags.NonPublic | BindingFlags.Instance);
                var count = spawnerType.GetField("_spawnedCount", BindingFlags.NonPublic | BindingFlags.Instance);
                sb.Append("isSpawning=").Append(isSpawning?.GetValue(spawner))
                  .Append(" count=").AppendLine(count?.GetValue(spawner)?.ToString());
            }
            else sb.AppendLine("Spawner instance null");
        }
        
        return sb.ToString();
    }
}
