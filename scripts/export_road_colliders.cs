using UnityEngine;
using UnityEditor;
using System.Text;
using System.Linq;
using System.Collections.Generic;
public class Script
{
    public static object Main()
    {
        var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(
            "Assets/ArtResources/Scene/Schedule/Roads.prefab");
        if (prefab == null) return "Prefab not found";

        var colliders = prefab.GetComponentsInChildren<BoxCollider>(true);
        var sb = new StringBuilder();
        sb.AppendLine("[");
        
        bool first = true;
        foreach (var c in colliders)
        {
            var t = c.transform;
            var worldCenter = t.TransformPoint(c.center);
            var worldSize = Vector3.Scale(c.size, t.lossyScale);
            var rot = t.eulerAngles;
            
            // 跳过太小的（标记点）
            float maxDim = Mathf.Max(worldSize.x, Mathf.Max(worldSize.y, worldSize.z));
            if (maxDim < 1f) continue;
            
            if (!first) sb.AppendLine(",");
            first = false;
            sb.Append("{");
            sb.Append("\"n\":\"").Append(c.gameObject.name).Append("\",");
            sb.Append("\"cx\":").Append(worldCenter.x.ToString("F2")).Append(",");
            sb.Append("\"cy\":").Append(worldCenter.y.ToString("F2")).Append(",");
            sb.Append("\"cz\":").Append(worldCenter.z.ToString("F2")).Append(",");
            sb.Append("\"sx\":").Append(worldSize.x.ToString("F2")).Append(",");
            sb.Append("\"sy\":").Append(worldSize.y.ToString("F2")).Append(",");
            sb.Append("\"sz\":").Append(worldSize.z.ToString("F2")).Append(",");
            sb.Append("\"rx\":").Append(rot.x.ToString("F1")).Append(",");
            sb.Append("\"ry\":").Append(rot.y.ToString("F1")).Append(",");
            sb.Append("\"rz\":").Append(rot.z.ToString("F1"));
            sb.Append("}");
        }
        
        sb.AppendLine("]");
        
        var path = "E:/workspace/PRJ/P1/scripts/road_colliders_export.json";
        System.IO.File.WriteAllText(path, sb.ToString());
        return "Exported " + colliders.Length + " colliders to " + path;
    }
}
