#!/usr/bin/env python3
"""可视化新生成的15条巡航路线"""
import json, math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import numpy as np

ROAD_NET = 'E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json'
ROUTES = 'E:/workspace/PRJ/P1/docs/new_traffic_routes.json'
OUTPUT = 'E:/workspace/PRJ/P1/docs/town_cruise_routes.png'

with open(ROAD_NET, 'r') as f:
    raw_nodes = json.load(f)
with open(ROUTES, 'r') as f:
    routes_data = json.load(f)

routes = routes_data['routes']

fig, axes = plt.subplots(3, 5, figsize=(30, 20))
fig.suptitle('Town Vehicle Cruising Routes (15 routes, each covering the whole town)', fontsize=18, fontweight='bold')

colors = cm.tab20(np.linspace(0, 1, 15))

for ri, route in enumerate(routes):
    ax = axes[ri // 5][ri % 5]
    pts = route['world_points']
    xs = [p['x'] for p in pts]
    zs = [p['z'] for p in pts]

    # 画底图路网（灰色）
    for n in raw_nodes:
        x1, z1 = n['position']['x'], n['position']['z']
        for nb_idx in n['neighbors']:
            if nb_idx < len(raw_nodes):
                nb = raw_nodes[nb_idx]
                x2, z2 = nb['position']['x'], nb['position']['z']
                ax.plot([x1, x2], [z1, z2], '-', color='#ddd', linewidth=0.5)

    # 画路线
    ax.plot(xs, zs, '-', color=colors[ri], linewidth=1.5, alpha=0.9)

    # 起点
    ax.plot(xs[0], zs[0], 'o', color='green', markersize=8, zorder=5)
    # 箭头方向（每隔20个点画一个箭头）
    for i in range(0, len(xs)-1, max(1, len(xs)//6)):
        j = min(i+1, len(xs)-1)
        if i != j:
            dx = xs[j] - xs[i]
            dz = zs[j] - zs[i]
            if abs(dx) + abs(dz) > 0.1:
                ax.annotate('', xy=(xs[j], zs[j]), xytext=(xs[i], zs[i]),
                           arrowprops=dict(arrowstyle='->', color=colors[ri], lw=1.5))

    span = math.sqrt((max(xs)-min(xs))**2 + (max(zs)-min(zs))**2)
    ax.set_title(f'Route {ri} ({len(pts)} pts, {span:.0f}m)', fontsize=10)
    ax.set_xlim(-160, 170)
    ax.set_ylim(125, -175)
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.15)
    ax.tick_params(labelsize=7)

plt.tight_layout(rect=[0, 0, 1, 0.96])
plt.savefig(OUTPUT, dpi=120)
print(f'Saved to {OUTPUT}')

# 也画一张全部路线叠加图
fig2, ax2 = plt.subplots(1, 1, figsize=(18, 16))

# 底图路网
for n in raw_nodes:
    x1, z1 = n['position']['x'], n['position']['z']
    for nb_idx in n['neighbors']:
        if nb_idx < len(raw_nodes):
            nb = raw_nodes[nb_idx]
            x2, z2 = nb['position']['x'], nb['position']['z']
            ax2.plot([x1, x2], [z1, z2], '-', color='#eee', linewidth=0.8)

for ri, route in enumerate(routes):
    pts = route['world_points']
    xs = [p['x'] for p in pts]
    zs = [p['z'] for p in pts]
    ax2.plot(xs, zs, '-', color=colors[ri], linewidth=1.8, alpha=0.7, label=f'Route {ri}')
    ax2.plot(xs[0], zs[0], 'o', color=colors[ri], markersize=8, markeredgecolor='black', markeredgewidth=1)

ax2.set_title('All 15 Cruising Routes Overlaid on Road Network', fontsize=14, fontweight='bold')
ax2.legend(loc='upper left', fontsize=8, ncol=3)
ax2.set_aspect('equal')
ax2.grid(True, alpha=0.2)
ax2.invert_yaxis()
plt.tight_layout()
plt.savefig(OUTPUT.replace('.png', '_overlay.png'), dpi=120)
print(f'Saved overlay map')
