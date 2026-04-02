"""绘制大世界路网图 + 路口红绿灯位置标注，用于调试红绿灯放置"""
import json
import math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# ========== 加载数据 ==========
DATA_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_miami.json"
OUT_DIR = "E:/workspace/PRJ/P1/scripts/"

print("Loading road data...")
with open(DATA_PATH, 'r', encoding='utf-8') as f:
    data = json.load(f)
print(f"Loaded {len(data)} waypoints")

# ========== 图1: 完整路网 + 路口标注 ==========
print("Drawing road network map...")
fig, ax = plt.subplots(1, 1, figsize=(20, 20))
ax.set_title(f'Big World Road Network ({len(data)} waypoints)', fontsize=14)

# 绘制所有路段（neighbors 连线）
road_count = 0
for i, p in enumerate(data):
    pos = p.get('position', {})
    x, z = pos.get('x', 0), pos.get('z', 0)
    for nb in p.get('neighbors', []):
        if 0 <= nb < len(data):
            npos = data[nb].get('position', {})
            nx, nz = npos.get('x', 0), npos.get('z', 0)
            ax.plot([x, nx], [z, nz], 'b-', lw=0.3, alpha=0.3)
            road_count += 1

# 路口节点（junction_id > 0）用颜色标注
junctions = {}
for i, p in enumerate(data):
    jid = p.get('junction_id', 0)
    if jid <= 0:
        continue
    if jid not in junctions:
        junctions[jid] = {'nodes': [], 'entrances': []}
    pos = p['position']
    junctions[jid]['nodes'].append((pos['x'], pos['z']))
    if p.get('cycle', 0) > 0 and p.get('cycle', 0) < 8:
        junctions[jid]['entrances'].append({
            'x': pos['x'], 'z': pos['z'], 'cycle': p['cycle'], 'idx': i
        })

# 绘制路口区域
for jid, jdata in junctions.items():
    if len(jdata['entrances']) < 2:
        continue
    nodes = jdata['nodes']
    xs = [n[0] for n in nodes]
    zs = [n[1] for n in nodes]
    cx, cz = sum(xs)/len(xs), sum(zs)/len(zs)

    # 路口中心点
    ax.plot(cx, cz, 'ro', markersize=3, alpha=0.7)

    # 入口节点
    for e in jdata['entrances']:
        ax.plot(e['x'], e['z'], 'g^', markersize=2, alpha=0.8)

ax.set_xlabel('X')
ax.set_ylabel('Z')
ax.set_aspect('equal')
ax.grid(True, alpha=0.2)

out1 = OUT_DIR + "bigworld_road_network_full.png"
plt.savefig(out1, dpi=150, bbox_inches='tight')
print(f"Saved: {out1}")
plt.close()

# ========== 图2: 路口详图（玩家附近区域） ==========
# 玩家大约在 (-80, -1883) 附近
PLAYER_X, PLAYER_Z = -80, -1883
VIEW_RANGE = 300  # 300m 范围

print(f"Drawing junction detail map near ({PLAYER_X}, {PLAYER_Z})...")
fig, ax = plt.subplots(1, 1, figsize=(16, 16))
ax.set_title(f'Junction Detail (±{VIEW_RANGE}m from player)', fontsize=14)

# 绘制附近路段
for i, p in enumerate(data):
    pos = p.get('position', {})
    x, z = pos.get('x', 0), pos.get('z', 0)
    if abs(x - PLAYER_X) > VIEW_RANGE or abs(z - PLAYER_Z) > VIEW_RANGE:
        continue
    for nb in p.get('neighbors', []):
        if 0 <= nb < len(data):
            npos = data[nb].get('position', {})
            nx, nz = npos.get('x', 0), npos.get('z', 0)
            # 颜色区分路口内外
            jid = p.get('junction_id', 0)
            color = 'orange' if jid > 0 else 'blue'
            ax.plot([x, nx], [z, nz], color=color, lw=0.8, alpha=0.5)

# 绘制路口入口和模拟红绿灯位置
MERGE_DIST_SQR = 12 * 12
LIGHT_PULLBACK = 3.0
LIGHT_SIDE_OFFSET = 6.0

for jid, jdata in junctions.items():
    if len(jdata['entrances']) < 2:
        continue
    nodes = jdata['nodes']
    cx = sum(n[0] for n in nodes) / len(nodes)
    cz = sum(n[1] for n in nodes) / len(nodes)

    if abs(cx - PLAYER_X) > VIEW_RANGE or abs(cz - PLAYER_Z) > VIEW_RANGE:
        continue

    # 路口中心
    ax.plot(cx, cz, 'rs', markersize=6, zorder=5)
    ax.annotate(f'J{jid}', (cx, cz), fontsize=7, color='red', zorder=6)

    # 合并入口（模拟 MergeEntrancesByDirection）
    entrances = jdata['entrances']
    used = [False] * len(entrances)
    merged_groups = []
    for i in range(len(entrances)):
        if used[i]:
            continue
        group = [entrances[i]]
        used[i] = True
        for j in range(i+1, len(entrances)):
            if used[j]:
                continue
            if entrances[j]['cycle'] != entrances[i]['cycle']:
                continue
            dx = entrances[i]['x'] - entrances[j]['x']
            dz = entrances[i]['z'] - entrances[j]['z']
            if dx*dx + dz*dz < MERGE_DIST_SQR:
                group.append(entrances[j])
                used[j] = True
        merged_groups.append(group)

    # 绘制每组入口和模拟红绿灯位置
    colors_cycle = ['green', 'purple', 'cyan', 'magenta']
    for gi, group in enumerate(merged_groups):
        color = colors_cycle[gi % len(colors_cycle)]

        # 所有入口点
        for e in group:
            ax.plot(e['x'], e['z'], '^', color=color, markersize=5, zorder=4)

        # 选最右入口
        ref = group[0]
        outward_x = ref['x'] - cx
        outward_z = ref['z'] - cz
        dist = math.sqrt(outward_x**2 + outward_z**2)
        if dist < 0.1:
            continue
        outward_x /= dist
        outward_z /= dist
        right_x = -outward_z
        right_z = outward_x

        if len(group) > 1:
            max_proj = -1e9
            for e in group:
                proj = (e['x'] - cx) * right_x + (e['z'] - cz) * right_z
                if proj > max_proj:
                    max_proj = proj
                    ref = e
            outward_x = ref['x'] - cx
            outward_z = ref['z'] - cz
            dist = math.sqrt(outward_x**2 + outward_z**2)
            if dist < 0.1:
                continue
            outward_x /= dist
            outward_z /= dist
            right_x = -outward_z
            right_z = outward_x

        # 红绿灯位置
        lx = ref['x'] + outward_x * LIGHT_PULLBACK + right_x * LIGHT_SIDE_OFFSET
        lz = ref['z'] + outward_z * LIGHT_PULLBACK + right_z * LIGHT_SIDE_OFFSET
        ax.plot(lx, lz, 'D', color='red', markersize=8, zorder=6, markeredgecolor='black', markeredgewidth=0.5)

# 玩家位置
ax.plot(PLAYER_X, PLAYER_Z, '*', color='yellow', markersize=15, zorder=7, markeredgecolor='black')
ax.annotate('Player', (PLAYER_X, PLAYER_Z), fontsize=10, color='black', zorder=7)

ax.set_xlim(PLAYER_X - VIEW_RANGE, PLAYER_X + VIEW_RANGE)
ax.set_ylim(PLAYER_Z - VIEW_RANGE, PLAYER_Z + VIEW_RANGE)
ax.set_xlabel('X')
ax.set_ylabel('Z')
ax.set_aspect('equal')
ax.grid(True, alpha=0.3)

# 图例
from matplotlib.lines import Line2D
legend_elements = [
    Line2D([0], [0], color='blue', lw=1, label='Road segments'),
    Line2D([0], [0], color='orange', lw=1, label='Junction segments'),
    Line2D([0], [0], marker='s', color='red', lw=0, markersize=6, label='Junction center'),
    Line2D([0], [0], marker='^', color='green', lw=0, markersize=6, label='Entrance nodes'),
    Line2D([0], [0], marker='D', color='red', lw=0, markersize=8, label='Traffic light (computed)'),
    Line2D([0], [0], marker='*', color='yellow', lw=0, markersize=12, label='Player'),
]
ax.legend(handles=legend_elements, loc='upper right', fontsize=9)

out2 = OUT_DIR + "bigworld_junction_detail.png"
plt.savefig(out2, dpi=150, bbox_inches='tight')
print(f"Saved: {out2}")
plt.close()

print("Done!")
