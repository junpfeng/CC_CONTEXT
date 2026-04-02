using UnityEngine;
using System.Text;
using System.Linq;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();
        var allColliders = Object.FindObjectsOfType<BoxCollider>();
        var roadColliders = allColliders.Where(c => c.gameObject.layer == 11).ToArray();
        sb.Append("Layer11 BoxColliders: ").AppendLine(roadColliders.Length.ToString());

        var allGOs = Object.FindObjectsOfType<GameObject>();
        var roadGOs = allGOs.Where(g => g.name.Contains("Road") || g.name.Contains("road")).ToArray();
        sb.Append("Road GOs: ").AppendLine(roadGOs.Length.ToString());
        foreach (var g in roadGOs.Take(10))
        {
            sb.Append("  ").Append(g.name).Append(" L=").Append(g.layer)
              .Append(" p=").Append(g.transform.position.ToString("F0"))
              .Append(" s=").AppendLine(g.transform.lossyScale.ToString("F0"));
        }

        if (roadColliders.Length > 0)
        {
            sb.AppendLine("Road collider details:");
            foreach (var c in roadColliders.OrderBy(x => x.gameObject.name).Take(20))
            {
                var t = c.transform;
                var wc = t.TransformPoint(c.center);
                var ws = Vector3.Scale(c.size, t.lossyScale);
                sb.Append("  ").Append(c.gameObject.name)
                  .Append(" c=").Append(wc.ToString("F0"))
                  .Append(" sz=").Append(ws.ToString("F0"))
                  .Append(" r=").AppendLine(t.eulerAngles.ToString("F0"));
            }
        }
        else
        {
            sb.AppendLine("No L11. Layer distribution:");
            var groups = allColliders.GroupBy(c => c.gameObject.layer);
            foreach (var g in groups.OrderByDescending(x => x.Count()).Take(8))
                sb.Append("  L").Append(g.Key).Append(": ").AppendLine(g.Count().ToString());
        }

        return sb.ToString();
    }
}
