"""将路网数据叠加到大世界卫星地图上，生成对比图"""
import json, math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
from matplotlib.lines import Line2D

DATA_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_miami.json"
# 用 SouthBeach.png（更清晰的老版本）
MAP_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/UI/Icon/Map/SouthBeach.png"
# SouthBeachNew 参数：4000x2500, scale=1, 左上角=(2489, 0, -2560.5)
# SouthBeach.png 可能不同尺寸，先用 SouthBeachNew 的参数
MAP_W, MAP_H = 4000, 2500
MAP_SCALE = 1.0
MAP_TL_X, MAP_TL_Z = 2489, -2560.5

OUT_1 = "E:/workspace/PRJ/P1/scripts/map1_road_network_data.png"
OUT_2 = "E:/workspace/PRJ/P1/scripts/map2_satellite_road_overlay.png"

print("Loading road data...")
with open(DATA_PATH, 'r') as f:
    data = json.load(f)

# 世界坐标 → 地图像素坐标
# MapManager: mapPos = (offsetX - worldX, worldZ - offsetZ) / scale
# 即 px = (TL_X - worldX) / scale, py = (worldZ - TL_Z) / scale
def world_to_px(wx, wz):
    px = (MAP_TL_X - wx) / MAP_SCALE
    py = (wz - MAP_TL_Z) / MAP_SCALE
    return px, py

# ===== 图1: 纯路网数据图 =====
print("Drawing map 1: road network data...")
fig, ax = plt.subplots(1, 1, figsize=(20, 12.5))
ax.set_facecolor('#1a1a2e')
ax.set_title('Map 1: Road Network Data (50523 waypoints, 294 junctions)', fontsize=14, color='white')

# 路段
for i, p in enumerate(data):
    pos = p.get('position', {})
    x1, z1 = pos.get('x', 0), pos.get('z', 0)
    px1, py1 = world_to_px(x1, z1)
    jid = p.get('junction_id', 0)
    for nb in p.get('neighbors', []):
        if 0 <= nb < len(data):
            npos = data[nb].get('position', {})
            x2, z2 = npos.get('x', 0), npos.get('z', 0)
            px2, py2 = world_to_px(x2, z2)
            if jid > 0:
                ax.plot([px1, px2], [py1, py2], color='#FF8C00', lw=0.8, alpha=0.5)
            else:
                ax.plot([px1, px2], [py1, py2], color='#4488FF', lw=0.5, alpha=0.4)

# 路口中心 + 入口 + 红绿灯
junctions = {}
for i, p in enumerate(data):
    jid = p.get('junction_id', 0)
    if jid <= 0: continue
    if jid not in junctions:
        junctions[jid] = {'nodes': [], 'entrances': []}
    pos = p['position']
    junctions[jid]['nodes'].append((pos['x'], pos['z']))
    cycle = p.get('cycle', 0)
    if 0 < cycle < 8:
        junctions[jid]['entrances'].append({'x': pos['x'], 'z': pos['z'], 'cycle': cycle})

for jid, jd in junctions.items():
    if len(jd['entrances']) < 2: continue
    nodes = jd['nodes']
    cx = sum(n[0] for n in nodes) / len(nodes)
    cz = sum(n[1] for n in nodes) / len(nodes)
    pcx, pcy = world_to_px(cx, cz)
    ax.plot(pcx, pcy, 's', color='#FF4444', markersize=3, zorder=5)

    # 合并入口 + 计算红绿灯
    entrances = jd['entrances']
    used = [False] * len(entrances)
    for i in range(len(entrances)):
        if used[i]: continue
        grp = [entrances[i]]
        used[i] = True
        for j in range(i+1, len(entrances)):
            if used[j] or entrances[j]['cycle'] != entrances[i]['cycle']: continue
            dx = entrances[i]['x'] - entrances[j]['x']
            dz = entrances[i]['z'] - entrances[j]['z']
            if dx*dx + dz*dz < 144:
                grp.append(entrances[j])
                used[j] = True
        # 红绿灯位置
        ref = grp[0]
        ox, oz = ref['x'] - cx, ref['z'] - cz
        d = math.sqrt(ox*ox + oz*oz)
        if d < 0.1: continue
        ox /= d; oz /= d
        rx, rz = -oz, ox
        if len(grp) > 1:
            best = -1e9
            for e in grp:
                proj = (e['x'] - cx) * rx + (e['z'] - cz) * rz
                if proj > best: best = proj; ref = e
            ox, oz = ref['x'] - cx, ref['z'] - cz
            d = math.sqrt(ox*ox + oz*oz)
            if d < 0.1: continue
            ox /= d; oz /= d
            rx, rz = -oz, ox
        lx = ref['x'] + ox * 3 + rx * 6
        lz = ref['z'] + oz * 3 + rz * 6
        plx, ply = world_to_px(lx, lz)
        ax.plot(plx, ply, 'D', color='#00FF00', markersize=4, zorder=6, markeredgecolor='white', markeredgewidth=0.3)

ax.set_xlim(0, MAP_W)
ax.set_ylim(MAP_H, 0)  # Y 翻转（图片坐标系）
ax.set_aspect('equal')
ax.set_xlabel('px (1px = 1m)', color='white')
ax.set_ylabel('py', color='white')
ax.tick_params(colors='white')
legend = [
    Line2D([0], [0], color='#4488FF', lw=1, label='Road segment'),
    Line2D([0], [0], color='#FF8C00', lw=1, label='Junction area'),
    Line2D([0], [0], marker='s', color='#FF4444', lw=0, markersize=5, label='Junction center'),
    Line2D([0], [0], marker='D', color='#00FF00', lw=0, markersize=6, label='Traffic light'),
]
ax.legend(handles=legend, loc='upper left', fontsize=9, facecolor='#333', labelcolor='white')
plt.savefig(OUT_1, dpi=150, bbox_inches='tight', facecolor='#1a1a2e')
print(f"Saved: {OUT_1}")
plt.close()

# ===== 图2: 卫星地图 + 路网叠加 =====
print("Drawing map 2: satellite overlay...")
try:
    img = mpimg.imread(MAP_PATH)
    print(f"  Map image: {img.shape}")
except Exception as e:
    print(f"  Failed to load map: {e}")
    img = None

fig, ax = plt.subplots(1, 1, figsize=(20, 12.5))
ax.set_title('Map 2: Satellite Map + Road Network Overlay', fontsize=14)

if img is not None:
    # 地图图片可能和配置尺寸不同，需缩放
    img_h, img_w = img.shape[:2]
    ax.imshow(img, extent=[0, MAP_W, MAP_H, 0], aspect='equal', alpha=0.8)

# 叠加路网（半透明）
for i, p in enumerate(data):
    pos = p.get('position', {})
    x1, z1 = pos.get('x', 0), pos.get('z', 0)
    px1, py1 = world_to_px(x1, z1)
    jid = p.get('junction_id', 0)
    for nb in p.get('neighbors', []):
        if 0 <= nb < len(data):
            npos = data[nb].get('position', {})
            x2, z2 = npos.get('x', 0), npos.get('z', 0)
            px2, py2 = world_to_px(x2, z2)
            if jid > 0:
                ax.plot([px1, px2], [py1, py2], color='yellow', lw=0.8, alpha=0.6)
            else:
                ax.plot([px1, px2], [py1, py2], color='cyan', lw=0.5, alpha=0.4)

# 红绿灯
for jid, jd in junctions.items():
    if len(jd['entrances']) < 2: continue
    nodes = jd['nodes']
    cx = sum(n[0] for n in nodes) / len(nodes)
    cz = sum(n[1] for n in nodes) / len(nodes)
    entrances = jd['entrances']
    used = [False] * len(entrances)
    for i in range(len(entrances)):
        if used[i]: continue
        grp = [entrances[i]]
        used[i] = True
        for j in range(i+1, len(entrances)):
            if used[j] or entrances[j]['cycle'] != entrances[i]['cycle']: continue
            dx = entrances[i]['x'] - entrances[j]['x']
            dz = entrances[i]['z'] - entrances[j]['z']
            if dx*dx + dz*dz < 144:
                grp.append(entrances[j])
                used[j] = True
        ref = grp[0]
        ox, oz = ref['x'] - cx, ref['z'] - cz
        d = math.sqrt(ox*ox + oz*oz)
        if d < 0.1: continue
        ox /= d; oz /= d
        rx, rz = -oz, ox
        if len(grp) > 1:
            best = -1e9
            for e in grp:
                proj = (e['x'] - cx) * rx + (e['z'] - cz) * rz
                if proj > best: best = proj; ref = e
            ox, oz = ref['x'] - cx, ref['z'] - cz
            d = math.sqrt(ox*ox + oz*oz)
            if d < 0.1: continue
            ox /= d; oz /= d
            rx, rz = -oz, ox
        lx = ref['x'] + ox * 3 + rx * 6
        lz = ref['z'] + oz * 3 + rz * 6
        plx, ply = world_to_px(lx, lz)
        ax.plot(plx, ply, 'D', color='#FF0000', markersize=5, zorder=6, markeredgecolor='white', markeredgewidth=0.5)

ax.set_xlim(0, MAP_W)
ax.set_ylim(MAP_H, 0)
ax.set_aspect('equal')
ax.set_xlabel('px (1px = 1m)')
ax.set_ylabel('py')
legend = [
    Line2D([0], [0], color='cyan', lw=1, label='Road segment'),
    Line2D([0], [0], color='yellow', lw=1, label='Junction area'),
    Line2D([0], [0], marker='D', color='red', lw=0, markersize=6, label='Traffic light'),
]
ax.legend(handles=legend, loc='upper left', fontsize=9)
plt.savefig(OUT_2, dpi=150, bbox_inches='tight')
print(f"Saved: {OUT_2}")
plt.close()
print("Done!")
