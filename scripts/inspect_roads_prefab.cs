using UnityEngine;
using UnityEditor;
using System.Text;
using System.Linq;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();

        // 直接加载 Roads.prefab
        var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(
            "Assets/ArtResources/Scene/Schedule/Roads.prefab");
        if (prefab == null)
        {
            // 尝试搜索
            var guids = AssetDatabase.FindAssets("Roads t:Prefab", new[] { "Assets/ArtResources/Scene/Schedule" });
            sb.Append("Prefab not found at expected path. Search results: ").AppendLine(guids.Length.ToString());
            foreach (var g in guids)
                sb.AppendLine("  " + AssetDatabase.GUIDToAssetPath(g));

            // 也搜索更广
            guids = AssetDatabase.FindAssets("Roads t:Prefab");
            foreach (var g in guids.Take(5))
                sb.AppendLine("  broader: " + AssetDatabase.GUIDToAssetPath(g));
            return sb.ToString();
        }

        sb.Append("Prefab: ").AppendLine(prefab.name);
        sb.Append("Children: ").AppendLine(prefab.transform.childCount.ToString());

        // 遍历所有子对象
        var colliders = prefab.GetComponentsInChildren<BoxCollider>(true);
        sb.Append("BoxColliders: ").AppendLine(colliders.Length.ToString());

        foreach (var c in colliders.Take(20))
        {
            var t = c.transform;
            var ws = Vector3.Scale(c.size, t.lossyScale);
            sb.Append("  ").Append(c.gameObject.name)
              .Append(" L=").Append(c.gameObject.layer)
              .Append(" pos=").Append(t.position.ToString("F0"))
              .Append(" sz=").Append(ws.ToString("F0"))
              .Append(" rot=").AppendLine(t.eulerAngles.ToString("F0"));
        }

        // 也检查 MeshCollider
        var meshCols = prefab.GetComponentsInChildren<MeshCollider>(true);
        sb.Append("MeshColliders: ").AppendLine(meshCols.Length.ToString());

        return sb.ToString();
    }
}
