using UnityEngine;
using System.Text;
using FL.Gameplay.Config;
using FL.Gameplay.Modules.UI;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();
        
        // 读取 MapUI 配置
        foreach (var kv in ConfigLoader.MapUIMap)
        {
            var m = kv.Value;
            sb.Append("MapUI[").Append(m.id).Append("]: icon=").Append(m.icon)
              .Append(" w=").Append(m.width).Append(" h=").Append(m.height)
              .Append(" scale=").Append(m.scale)
              .Append(" worldPos=").AppendLine(m.worldPos.ToString());
        }
        
        // 读取 MapManager 运行时值
        sb.Append("MapManager: offsetX=").Append(MapManager.WorldPosOffsetX)
          .Append(" offsetY=").Append(MapManager.WorldPosOffsetY)
          .Append(" scale=").Append(MapManager.MapScale)
          .Append(" w=").Append(MapManager.MapWidth)
          .Append(" h=").AppendLine(MapManager.MapHeight.ToString());
        
        // 也拍一张白天清晰的全镇俯视图
        var go = new GameObject("OverviewCam");
        var cam = go.AddComponent<Camera>();
        go.transform.position = new Vector3(30, 120, -20);
        go.transform.rotation = Quaternion.Euler(90, 0, 0);
        cam.orthographic = true;
        cam.orthographicSize = 180;
        cam.nearClipPlane = 0.1f;
        cam.farClipPlane = 300f;
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.2f, 0.3f, 0.2f);
        var mainCam = Camera.main;
        if (mainCam != null)
            cam.cullingMask = mainCam.cullingMask;
        
        int w = 2048, h = 2048;
        var rt = new RenderTexture(w, h, 24);
        cam.targetTexture = rt;
        cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();
        cam.targetTexture = null;
        RenderTexture.active = null;
        Object.DestroyImmediate(rt);
        Object.DestroyImmediate(go);
        
        var bytes = tex.EncodeToPNG();
        Object.DestroyImmediate(tex);
        System.IO.File.WriteAllBytes("E:/workspace/PRJ/P1/scripts/town_overview.png", bytes);
        sb.Append("Overview saved: ").AppendLine(bytes.Length.ToString());
        
        return sb.ToString();
    }
}
