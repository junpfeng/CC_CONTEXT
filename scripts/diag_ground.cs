using UnityEngine;
using System.Text;
public class Script
{
    public static object Main()
    {
        var sb = new StringBuilder();
        var playerCtrl = FL.Gameplay.Modules.BigWorld.PlayerManager.Controller;
        if (playerCtrl == null) return "No player";
        var playerPos = playerCtrl.transform.position;
        sb.Append("Player: ").AppendLine(playerPos.ToString());

        // Raycast down from high above player position on ALL layers
        var origin = new Vector3(playerPos.x, 50f, playerPos.z);
        var hits = Physics.RaycastAll(origin, Vector3.down, 100f);
        sb.Append("RaycastAll hits: ").AppendLine(hits.Length.ToString());
        System.Array.Sort(hits, (a, b) => a.point.y.CompareTo(b.point.y));
        foreach (var h in hits)
        {
            sb.Append("  Y=").Append(h.point.y.ToString("F2"))
              .Append(" layer=").Append(h.collider.gameObject.layer)
              .Append(" name=").Append(h.collider.gameObject.name)
              .Append(" tag=").AppendLine(h.collider.gameObject.tag);
        }

        // Also check at a vehicle position
        sb.AppendLine("--- At (-15.3, 0.9) ---");
        var origin2 = new Vector3(-15.3f, 50f, 0.9f);
        var hits2 = Physics.RaycastAll(origin2, Vector3.down, 100f);
        System.Array.Sort(hits2, (a, b) => a.point.y.CompareTo(b.point.y));
        foreach (var h in hits2)
        {
            sb.Append("  Y=").Append(h.point.y.ToString("F2"))
              .Append(" layer=").Append(h.collider.gameObject.layer)
              .Append(" name=").Append(h.collider.gameObject.name)
              .Append(" tag=").AppendLine(h.collider.gameObject.tag);
        }

        // Check which layer the player is actually standing on
        if (Physics.Raycast(playerPos + Vector3.up * 2f, Vector3.down, out var pHit, 10f))
        {
            sb.Append("PlayerStandingOn: Y=").Append(pHit.point.y.ToString("F2"))
              .Append(" layer=").Append(pHit.collider.gameObject.layer)
              .Append(" name=").AppendLine(pHit.collider.gameObject.name);
        }

        return sb.ToString();
    }
}
