using UnityEngine;
public class Script {
    public static string Main() {
        var tex = ScreenCapture.CaptureScreenshotAsTexture();
        if (tex == null) return "ScreenCapture failed";
        var bytes = tex.EncodeToPNG();
        System.IO.File.WriteAllBytes("E:/workspace/PRJ/P1/docs/bugs/0.0.3/GM_System/1/images/GM_System_bug1_weapon_wheel_ui.png", bytes);
        Object.DestroyImmediate(tex);
        return "Saved, size=" + bytes.Length;
    }
}
