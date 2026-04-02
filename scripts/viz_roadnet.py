"""大世界行人路网 vs 车辆路网可视化对比"""
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

PED_FILE  = r"E:\workspace\PRJ\P1\freelifeclient\RawTables\Json\Server\miami_ped_road.json"
VEH_FILE  = r"E:\workspace\PRJ\P1\freelifeclient\RawTables\Json\Global\traffic_waypoint\road_traffic_miami.json"
OUT_FILE  = r"E:\workspace\PRJ\P1\docs\roadnet_compare.png"

print("Loading pedestrian road network...")
with open(PED_FILE, encoding='utf-8') as f:
    ped_data = json.load(f)

ped_x, ped_z = [], []
for network in ped_data.get("lists", []):
    for pt in network.get("points", []):
        pos = pt["position"]
        ped_x.append(pos[0])
        ped_z.append(pos[2])
print(f"  Pedestrian points: {len(ped_x)}")

print("Loading vehicle road network...")
with open(VEH_FILE, encoding='utf-8') as f:
    veh_data = json.load(f)

veh_x, veh_z = [], []
for pt in veh_data:
    pos = pt["position"]
    veh_x.append(pos["x"])
    veh_z.append(pos["z"])
print(f"  Vehicle points: {len(veh_x)}")

# ── 绘图 ──────────────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(24, 9))
fig.patch.set_facecolor('#1a1a2e')
for ax in axes:
    ax.set_facecolor('#16213e')
    ax.tick_params(colors='#aaaaaa')
    for spine in ax.spines.values():
        spine.set_edgecolor('#444466')

DOT = 0.3

def draw_net(ax, xs, zs, color, label, alpha=0.6):
    ax.scatter(xs, zs, s=DOT, c=color, alpha=alpha, linewidths=0, rasterized=True)
    ax.set_xlabel('X', color='#aaaaaa')
    ax.set_ylabel('Z', color='#aaaaaa')
    ax.set_title(label, color='white', fontsize=12, pad=8)
    ax.set_aspect('equal')

# 左：行人路网
draw_net(axes[0], ped_x, ped_z, '#00d4ff', f'行人路网  ({len(ped_x):,} pts)')

# 中：车辆路网
draw_net(axes[1], veh_x, veh_z, '#ff6b35', f'车辆路网  ({len(veh_x):,} pts)')

# 右：叠加对比
axes[2].scatter(ped_x, ped_z, s=DOT, c='#00d4ff', alpha=0.5, linewidths=0, rasterized=True, label='行人')
axes[2].scatter(veh_x, veh_z, s=DOT, c='#ff6b35', alpha=0.5, linewidths=0, rasterized=True, label='车辆')
axes[2].set_xlabel('X', color='#aaaaaa')
axes[2].set_ylabel('Z', color='#aaaaaa')
axes[2].set_title('叠加对比', color='white', fontsize=12, pad=8)
axes[2].set_aspect('equal')

# 统计包围盒
ped_xrange = (min(ped_x), max(ped_x))
ped_zrange = (min(ped_z), max(ped_z))
veh_xrange = (min(veh_x), max(veh_x))
veh_zrange = (min(veh_z), max(veh_z))

stats = (
    f"行人路网  X[{ped_xrange[0]:.0f}, {ped_xrange[1]:.0f}]  Z[{ped_zrange[0]:.0f}, {ped_zrange[1]:.0f}]\n"
    f"车辆路网  X[{veh_xrange[0]:.0f}, {veh_xrange[1]:.0f}]  Z[{veh_zrange[0]:.0f}, {veh_zrange[1]:.0f}]"
)
fig.text(0.5, 0.01, stats, ha='center', color='#aaaaaa', fontsize=9,
         bbox=dict(facecolor='#0f3460', edgecolor='#444466', boxstyle='round,pad=0.4'))

p1 = mpatches.Patch(color='#00d4ff', label='行人路网')
p2 = mpatches.Patch(color='#ff6b35', label='车辆路网')
axes[2].legend(handles=[p1, p2], loc='upper right',
               facecolor='#0f3460', edgecolor='#444466', labelcolor='white')

plt.suptitle('大世界路网对比（miami）', color='white', fontsize=14, y=1.01)
plt.tight_layout()
plt.savefig(OUT_FILE, dpi=150, bbox_inches='tight', facecolor=fig.get_facecolor())
print(f"Saved → {OUT_FILE}")
