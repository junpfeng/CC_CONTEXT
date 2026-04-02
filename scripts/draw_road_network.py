"""绘制 road_traffic_fl.json 与 road_traffic_gley.json 路网俯视图对比"""
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

fl_path = "E:/workspace/PRJ/P1/freelifeclient/Assets/DesignConfig/GleyData/MapInfo/road_traffic_fl.json"
gley_path = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json"

with open(fl_path, 'r', encoding='utf-8') as f:
    fl_data = json.load(f)
nodes = fl_data['nodes']
links = fl_data['links']
node_pos = {n['id']: (n['position']['x'], n['position']['z']) for n in nodes}
print(f"FL: {len(nodes)} nodes, {len(links)} links")

with open(gley_path, 'r', encoding='utf-8') as f:
    gley_data = json.load(f)
print(f"Gley: {len(gley_data)} points, sample keys: {list(gley_data[0].keys())[:8]}")

fig, axes = plt.subplots(1, 2, figsize=(24, 12))

# Left: road_traffic_fl.json
ax = axes[0]
ax.set_title(f'road_traffic_fl.json ({len(nodes)} nodes)', fontsize=14)
for link in links:
    s, e = link['start_node'], link['end_node']
    if s in node_pos and e in node_pos:
        ax.plot([node_pos[s][0], node_pos[e][0]], [node_pos[s][1], node_pos[e][1]], 'b-', lw=0.4, alpha=0.5)
xs = [p[0] for p in node_pos.values()]
zs = [p[1] for p in node_pos.values()]
ax.scatter(xs, zs, s=0.3, c='blue', alpha=0.3)
ax.set_xlabel('X'); ax.set_ylabel('Z'); ax.set_aspect('equal'); ax.grid(True, alpha=0.3)

# Right: road_traffic_gley.json
ax2 = axes[1]
ax2.set_title(f'road_traffic_gley.json ({len(gley_data)} points) - CURRENT', fontsize=14)
gxs, gzs = [], []
for p in gley_data:
    pos = p.get('position', {})
    if isinstance(pos, dict):
        gxs.append(pos.get('x', 0)); gzs.append(pos.get('z', 0))
        for nb in p.get('neighbors', []):
            if 0 <= nb < len(gley_data):
                npos = gley_data[nb].get('position', {})
                if isinstance(npos, dict):
                    ax2.plot([pos['x'], npos['x']], [pos['z'], npos['z']], 'r-', lw=0.4, alpha=0.5)
ax2.scatter(gxs, gzs, s=0.3, c='red', alpha=0.3)
ax2.set_xlabel('X'); ax2.set_ylabel('Z'); ax2.set_aspect('equal'); ax2.grid(True, alpha=0.3)

# Same axis range
all_xs = xs + gxs; all_zs = zs + gzs
m = 50
for a in axes:
    a.set_xlim(min(all_xs)-m, max(all_xs)+m)
    a.set_ylim(min(all_zs)-m, max(all_zs)+m)

plt.tight_layout()
out = "E:/workspace/PRJ/P1/scripts/road_network_comparison.png"
plt.savefig(out, dpi=150)
print(f"Saved: {out}")
