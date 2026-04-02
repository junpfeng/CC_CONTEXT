using UnityEditor;
using UnityEngine;
using System.Text;
using System.IO;
using System.Collections.Generic;

public class Script
{
    public static object Main()
    {
        string fbxPath = "Assets/ArtResources/Scene/Schedule/Schedule_Terrain/Model/Road_Sch.fbx";
        var objs = AssetDatabase.LoadAllAssetsAtPath(fbxPath);

        var sb = new StringBuilder();

        foreach (var obj in objs)
        {
            if (!(obj is Mesh mesh) || mesh.vertexCount == 0) continue;
            var verts = mesh.vertices;

            float minX=float.MaxValue,maxX=float.MinValue;
            float minZ=float.MaxValue,maxZ=float.MinValue;
            float minY=float.MaxValue,maxY=float.MinValue;

            foreach (var v in verts)
            {
                if(v.x<minX)minX=v.x; if(v.x>maxX)maxX=v.x;
                if(v.z<minZ)minZ=v.z; if(v.z>maxZ)maxZ=v.z;
                if(v.y<minY)minY=v.y; if(v.y>maxY)maxY=v.y;
            }

            float spanX = maxX - minX;
            float spanZ = maxZ - minZ;
            float width = Mathf.Min(spanX, spanZ);
            float length = Mathf.Max(spanX, spanZ);
            bool primaryIsX = spanX > spanZ;

            // Compute center line: bin vertices along primary axis, average cross-axis
            int bins = Mathf.Max(2, Mathf.Min(20, verts.Length / 10));
            float pMin = primaryIsX ? minX : minZ;
            float pMax = primaryIsX ? maxX : maxZ;
            float binSize = (pMax - pMin) / bins;

            var binSums = new Vector3[bins];
            var binCounts = new int[bins];

            foreach (var v in verts)
            {
                float pVal = primaryIsX ? v.x : v.z;
                int bi = Mathf.Clamp((int)((pVal - pMin) / binSize), 0, bins - 1);
                binSums[bi] += v;
                binCounts[bi]++;
            }

            // Output: name|verts|width|length|yMin|yMax|centerline_points
            sb.Append(mesh.name);
            sb.Append("|" + verts.Length);
            sb.Append("|" + width.ToString("F1"));
            sb.Append("|" + length.ToString("F1"));
            sb.Append("|" + minY.ToString("F1"));
            sb.Append("|" + maxY.ToString("F1"));

            // Center line points
            for (int i = 0; i < bins; i++)
            {
                if (binCounts[i] == 0) continue;
                var avg = binSums[i] / binCounts[i];
                sb.Append("|" + avg.x.ToString("F1") + "," + avg.y.ToString("F1") + "," + avg.z.ToString("F1"));
            }
            sb.AppendLine();
        }

        string outPath = Path.Combine(Application.dataPath, "../../docs/town_road_meshes.txt");
        outPath = Path.GetFullPath(outPath);
        Directory.CreateDirectory(Path.GetDirectoryName(outPath));
        File.WriteAllText(outPath, sb.ToString());
        return "Exported " + objs.Length + " assets, file: " + outPath;
    }
}
