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
        
        // 取最近的一辆
        var playerCtrl = FL.Gameplay.Modules.BigWorld.PlayerManager.Controller;
        var playerPos = playerCtrl != null ? playerCtrl.transform.position : Vector3.zero;
        var nearest = movers.Cast<MonoBehaviour>()
            .OrderBy(m => Vector3.Distance(m.transform.position, playerPos))
            .First();
        
        var go = nearest.gameObject;
        sb.Append("Vehicle: ").Append(go.name).Append(" pos=").AppendLine(go.transform.position.ToString("F1"));
        
        // 列出所有组件
        var comps = go.GetComponents<Component>();
        sb.Append("Components (").Append(comps.Length).AppendLine("):");
        foreach (var c in comps)
        {
            if (c == null) continue;
            string typeName = c.GetType().Name;
            bool enabled = true;
            if (c is Behaviour b) enabled = b.enabled;
            sb.Append("  ").Append(typeName).Append(" enabled=").AppendLine(enabled.ToString());
        }
        
        // 检查 Rigidbody 状态
        var rb = go.GetComponent<Rigidbody>();
        if (rb != null)
        {
            sb.Append("Rigidbody: kinematic=").Append(rb.isKinematic)
              .Append(" gravity=").Append(rb.useGravity)
              .Append(" vel=").Append(rb.velocity.ToString("F1"))
              .Append(" angVel=").AppendLine(rb.angularVelocity.ToString("F1"));
        }
        
        // 检查父级 Vehicle 的关键字段
        var vehicleType = go.GetComponents<Component>()
            .FirstOrDefault(c => c != null && c.GetType().Name == "Vehicle");
        if (vehicleType != null)
        {
            var extField = vehicleType.GetType().GetField("ExternalDisableNetTransform", 
                BindingFlags.Public | BindingFlags.Instance);
            if (extField != null)
                sb.Append("ExternalDisableNetTransform=").AppendLine(extField.GetValue(vehicleType).ToString());
            
            var trafficField = vehicleType.GetType().GetField("isControlledByTraffic",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (trafficField != null)
                sb.Append("isControlledByTraffic=").AppendLine(trafficField.GetValue(vehicleType).ToString());
        }
        
        return sb.ToString();
    }
}
