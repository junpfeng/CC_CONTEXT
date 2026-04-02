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
        var moverType = asm.GetType("Gley.TrafficSystem.Internal.TownTrafficMover");
        var movers = Object.FindObjectsOfType(moverType);
        if (movers.Length == 0) return "No movers";
        
        var playerCtrl = FL.Gameplay.Modules.BigWorld.PlayerManager.Controller;
        var playerPos = playerCtrl != null ? playerCtrl.transform.position : Vector3.zero;
        var nearest = movers.Cast<MonoBehaviour>()
            .OrderBy(m => Vector3.Distance(m.transform.position, playerPos)).First();
        var go = nearest.gameObject;
        
        // 检查子对象上的组件
        sb.AppendLine("Child components:");
        for (int i = 0; i < go.transform.childCount; i++)
        {
            var child = go.transform.GetChild(i);
            var childComps = child.GetComponents<Component>();
            foreach (var c in childComps)
            {
                if (c == null) continue;
                string name = c.GetType().Name;
                if (name == "Transform") continue;
                bool enabled = true;
                if (c is Behaviour b) enabled = b.enabled;
                sb.Append("  [").Append(child.name).Append("] ").Append(name)
                  .Append(" en=").AppendLine(enabled.ToString());
            }
        }
        
        // 检查 Vehicle 上 VehicleNetTransformComp（可能是内部 Comp）
        var vehicleComp = go.GetComponent<Component>();
        var allTypes = go.GetComponents<Component>().Select(c => c?.GetType().Name ?? "null");
        
        // 用反射检查 Vehicle 的 Comp 系统
        var vehicle = go.GetComponents<Component>()
            .FirstOrDefault(c => c != null && c.GetType().Name == "Vehicle");
        if (vehicle != null)
        {
            // 检查 ExternalDisableNetTransform
            var fields = vehicle.GetType().GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            foreach (var f in fields)
            {
                if (f.Name.Contains("NetTransform") || f.Name.Contains("External") || f.Name.Contains("traffic") || f.Name.Contains("Traffic"))
                {
                    var val = f.GetValue(vehicle);
                    sb.Append("Vehicle.").Append(f.Name).Append(" = ").AppendLine(val?.ToString() ?? "null");
                }
            }
            
            // 检查 FloatingObject
            var floating = go.GetComponent<Component>();
            var floatComp = go.GetComponents<Component>()
                .FirstOrDefault(c => c != null && c.GetType().Name == "FloatingObject");
            if (floatComp != null)
            {
                sb.Append("FloatingObject enabled=");
                if (floatComp is Behaviour fb) sb.AppendLine(fb.enabled.ToString());
            }
        }
        
        // 连续记录 5 帧的位置变化
        sb.Append("CurrentPos: ").AppendLine(go.transform.position.ToString("F3"));
        
        return sb.ToString();
    }
}
