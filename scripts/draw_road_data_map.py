"""绘制红绿灯放置依据：路网数据图（路点+连接+路口+入口+红绿灯计算位置）"""
import json, math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Circle

DATA_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_miami.json"
OUT = "E:/workspace/PRJ/P1/scripts/bigworld_road_data_map.png"

# 视野范围（和 Scene View 一致：center=(-80,-1883), size=500）
CX, CZ = -80, -1883
HALF = 500

print("Loading...")
with open(DATA_PATH, 'r') as f:
    data = json.load(f)

fig, ax = plt.subplots(1, 1, figsize=(20, 20))
ax.set_title('Road Network Data Map (traffic light placement basis)', fontsize=14)

# ===== 1. 路段连接（蓝色细线）=====
for i, p in enumerate(data):
    pos = p.get('position', {})
    x, z = pos.get('x', 0), pos.get('z', 0)
    if abs(x - CX) > HALF or abs(z - CZ) > HALF:
        continue
    jid = p.get('junction_id', 0)
    for nb in p.get('neighbors', []):
        if 0 <= nb < len(data):
            npos = data[nb].get('position', {})
            nx, nz = npos.get('x', 0), npos.get('z', 0)
            if jid > 0:
                ax.plot([x, nx], [z, nz], color='#FFA500', lw=1.0, alpha=0.4)
            else:
                ax.plot([x, nx], [z, nz], color='#4488CC', lw=0.6, alpha=0.4)

# ===== 2. 路点散点（灰色小点）=====
road_xs, road_zs = [], []
junc_xs, junc_zs = [], []
for p in data:
    pos = p.get('position', {})
    x, z = pos.get('x', 0), pos.get('z', 0)
    if abs(x - CX) > HALF or abs(z - CZ) > HALF:
        continue
    if p.get('junction_id', 0) > 0:
        junc_xs.append(x)
        junc_zs.append(z)
    else:
        road_xs.append(x)
        road_zs.append(z)

ax.scatter(road_xs, road_zs, s=0.5, c='#4488CC', alpha=0.3, zorder=2)
ax.scatter(junc_xs, junc_zs, s=1.5, c='#FFA500', alpha=0.5, zorder=3)

# ===== 3. 路口分析 + 红绿灯位置计算 =====
junctions = {}
for i, p in enumerate(data):
    jid = p.get('junction_id', 0)
    if jid <= 0:
        continue
    pos = p['position']
    x, z = pos['x'], pos['z']
    if abs(x - CX) > HALF + 50 or abs(z - CZ) > HALF + 50:
        continue
    if jid not in junctions:
        junctions[jid] = {'nodes': [], 'entrances': []}
    junctions[jid]['nodes'].append((x, z))
    cycle = p.get('cycle', 0)
    if 0 < cycle < 8:
        junctions[jid]['entrances'].append({'x': x, 'z': z, 'cycle': cycle, 'idx': i})

MERGE_DIST_SQR = 12 * 12
PULLBACK = 3.0
SIDE_OFFSET = 6.0

for jid, jd in junctions.items():
    if len(jd['entrances']) < 2:
        continue
    nodes = jd['nodes']
    cx = sum(n[0] for n in nodes) / len(nodes)
    cz = sum(n[1] for n in nodes) / len(nodes)

    # 路口中心
    ax.plot(cx, cz, 's', color='red', markersize=5, zorder=5)
    ax.annotate(f'{jid}', (cx + 3, cz + 3), fontsize=5, color='red', zorder=6)

    # 入口节点
    for e in jd['entrances']:
        ax.plot(e['x'], e['z'], '^', color='#00CC00', markersize=4, zorder=4)

    # 合并同方向入口
    entrances = jd['entrances']
    used = [False] * len(entrances)
    groups = []
    for i in range(len(entrances)):
        if used[i]:
            continue
        grp = [entrances[i]]
        used[i] = True
        for j in range(i+1, len(entrances)):
            if used[j] or entrances[j]['cycle'] != entrances[i]['cycle']:
                continue
            dx = entrances[i]['x'] - entrances[j]['x']
            dz = entrances[i]['z'] - entrances[j]['z']
            if dx*dx + dz*dz < MERGE_DIST_SQR:
                grp.append(entrances[j])
                used[j] = True
        groups.append(grp)

    # 计算红绿灯位置
    for grp in groups:
        ref = grp[0]
        ox = ref['x'] - cx
        oz = ref['z'] - cz
        d = math.sqrt(ox*ox + oz*oz)
        if d < 0.1:
            continue
        ox /= d
        oz /= d
        rx, rz = -oz, ox

        if len(grp) > 1:
            best_proj = -1e9
            for e in grp:
                proj = (e['x'] - cx) * rx + (e['z'] - cz) * rz
                if proj > best_proj:
                    best_proj = proj
                    ref = e
            ox = ref['x'] - cx
            oz = ref['z'] - cz
            d = math.sqrt(ox*ox + oz*oz)
            if d < 0.1:
                continue
            ox /= d
            oz /= d
            rx, rz = -oz, ox

        lx = ref['x'] + ox * PULLBACK + rx * SIDE_OFFSET
        lz = ref['z'] + oz * PULLBACK + rz * SIDE_OFFSET
        ax.plot(lx, lz, 'D', color='#FF0000', markersize=7, zorder=7,
                markeredgecolor='black', markeredgewidth=0.5)

        # 入口→红绿灯连线
        ax.plot([ref['x'], lx], [ref['z'], lz], '-', color='red', lw=0.8, alpha=0.6, zorder=4)

        # 来车方向箭头
        arr_x = lx + ox * (-8)
        arr_z = lz + oz * (-8)
        ax.annotate('', xy=(lx, lz), xytext=(arr_x, arr_z),
                     arrowprops=dict(arrowstyle='->', color='gray', lw=1), zorder=4)

ax.set_xlim(CX - HALF, CX + HALF)
ax.set_ylim(CZ - HALF, CZ + HALF)
ax.set_xlabel('X (world)')
ax.set_ylabel('Z (world)')
ax.set_aspect('equal')
ax.grid(True, alpha=0.15)

legend_elements = [
    Line2D([0], [0], color='#4488CC', lw=1, label='Road segment'),
    Line2D([0], [0], color='#FFA500', lw=1, label='Junction segment'),
    Line2D([0], [0], marker='.', color='#4488CC', lw=0, markersize=4, label='Road waypoint'),
    Line2D([0], [0], marker='.', color='#FFA500', lw=0, markersize=5, label='Junction waypoint'),
    Line2D([0], [0], marker='s', color='red', lw=0, markersize=6, label='Junction center'),
    Line2D([0], [0], marker='^', color='#00CC00', lw=0, markersize=6, label='Entrance node (cycle>0)'),
    Line2D([0], [0], marker='D', color='red', lw=0, markersize=8, label='Traffic light (computed)'),
    Line2D([0], [0], color='gray', lw=1, marker='>', markersize=5, label='Approach direction'),
]
ax.legend(handles=legend_elements, loc='upper left', fontsize=9, framealpha=0.9)

plt.savefig(OUT, dpi=150, bbox_inches='tight')
print(f"Saved: {OUT}")
plt.close()
