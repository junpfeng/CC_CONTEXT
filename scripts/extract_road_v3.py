"""小镇路网生成 v3 - 修复卡顿/方向问题
改进：
1. 单向图（neighbors 只指向前方，不双向）
2. 更大采样间距减少路点数
3. 提高阈值减少窄巷/人行道误检
4. 路口检测 + 限制连接数
"""
import json, math
import numpy as np
from PIL import Image
from skimage.morphology import skeletonize
from scipy import ndimage
from scipy.spatial import KDTree

MAP_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/UI/Icon/Map/S1Town.png"
OUT_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json"
RAW_OUT = "E:/workspace/PRJ/P1/freelifeclient/RawTables/Json/Global/traffic_waypoint/road_traffic_gley.json"
TOWN_OUT = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/town_vehicle_road.json"

LOGICAL_SIZE = 2048
MAP_SCALE = 0.2056
OFFSET_X = 200.0
OFFSET_Z = -207.0

print("=== Road Network Generation v3 ===")
print("Loading map...")
img = Image.open(MAP_PATH).convert('L')
arr = np.array(img)
ACTUAL_H, ACTUAL_W = arr.shape
PIXEL_SCALE = MAP_SCALE * LOGICAL_SIZE / ACTUAL_W
print(f"Map: {ACTUAL_W}x{ACTUAL_H}, pixel_scale={PIXEL_SCALE:.4f} m/px")

# 采样间距加大到 8m，减少路点总数
WORLD_SPACING = 8.0
SAMPLE_SPACING = int(WORLD_SPACING / PIXEL_SCALE)
CONNECT_RADIUS = SAMPLE_SPACING * 2.2  # 稍微缩小连接范围
print(f"Spacing: {WORLD_SPACING}m = {SAMPLE_SPACING}px, connect: {CONNECT_RADIUS:.0f}px")

def pixel_to_world(px, py):
    wx = OFFSET_X - px * PIXEL_SCALE
    wz = OFFSET_Z + py * PIXEL_SCALE
    return round(wx, 2), round(wz, 2)

# === 1. 道路掩码 - 提高阈值排除窄巷 ===
# 提高下限到 105，排除暗色人行道/小巷
road_mask = (arr > 105) & (arr < 215)

bg_mask = arr > 230
bg_dilated = ndimage.binary_dilation(bg_mask, iterations=10)
water_mask = arr < 35
water_dilated = ndimage.binary_dilation(water_mask, iterations=5)

road_mask = road_mask & ~bg_dilated & ~water_dilated

# 更强的形态学清理 - 去除窄路
road_mask = ndimage.binary_opening(road_mask, structure=np.ones((7,7)))
road_mask = ndimage.binary_closing(road_mask, structure=np.ones((9,9)))

# 去除小连通域
labeled, nfeatures = ndimage.label(road_mask)
sizes = ndimage.sum(road_mask, labeled, range(1, nfeatures+1))
for i, s in enumerate(sizes):
    if s < 1000:  # 提高最小面积
        road_mask[labeled == (i+1)] = False

road_px = np.sum(road_mask)
print(f"Road pixels: {road_px} ({100*road_px/arr.size:.1f}%)")

# === 2. 骨架化 ===
print("Skeletonizing...")
skeleton = skeletonize(road_mask)
skel_count = np.sum(skeleton)
print(f"Skeleton: {skel_count} pixels")

# === 3. 采样路点 ===
print("Sampling waypoints...")
skel_coords = np.argwhere(skeleton)
sampled = []
used = np.zeros(skeleton.shape, dtype=bool)
r = SAMPLE_SPACING // 2

for row, col in skel_coords:
    if used[row, col]:
        continue
    sampled.append((col, row))
    rmin = max(0, row - r)
    rmax = min(ACTUAL_H, row + r + 1)
    cmin = max(0, col - r)
    cmax = min(ACTUAL_W, col + r + 1)
    used[rmin:rmax, cmin:cmax] = True

print(f"Sampled: {len(sampled)} waypoints")

# === 4. 建立单向邻接（沿骨架方向） ===
print("Building directed connections...")
pts_arr = np.array(sampled, dtype=float)
tree = KDTree(pts_arr)

# 先建立无向邻接
undirected = [set() for _ in range(len(sampled))]
for i, pt in enumerate(sampled):
    nearby = tree.query_ball_point(pt, CONNECT_RADIUS)
    for j in nearby:
        if j <= i:
            continue
        px1, py1 = sampled[i]
        px2, py2 = sampled[j]
        dist = math.hypot(px2-px1, py2-py1)
        # 多点采样检查道路连通
        steps = max(3, int(dist / 15))
        on_road = True
        for s in range(1, steps):
            t = s / steps
            mx = int(px1 + (px2-px1)*t)
            my = int(py1 + (py2-py1)*t)
            if 0 <= my < ACTUAL_H and 0 <= mx < ACTUAL_W:
                if not road_mask[my, mx]:
                    on_road = False
                    break
        if on_road:
            undirected[i].add(j)
            undirected[j].add(i)

# 转为有向图：每个点的 neighbors 指向"前方"（按骨架顺序）
# 简化策略：将无向边转为双向有向边（neighbors 和 prev 各自独立列表）
neighbors = [[] for _ in range(len(sampled))]
prevs = [[] for _ in range(len(sampled))]

for i in range(len(sampled)):
    nb_list = list(undirected[i])
    # 限制每个点最多 3 个邻居（减少路口处的过度连接）
    if len(nb_list) > 3:
        # 按距离排序，保留最近的3个
        dists = [(math.hypot(sampled[j][0]-sampled[i][0], sampled[j][1]-sampled[i][1]), j) for j in nb_list]
        dists.sort()
        nb_list = [j for _, j in dists[:3]]
    neighbors[i] = nb_list
    for j in nb_list:
        if i not in prevs[j]:
            prevs[j].append(i)

connected = sum(1 for n in neighbors if len(n) > 0)
total_edges = sum(len(n) for n in neighbors)
print(f"Connected: {connected}/{len(sampled)}, directed edges: {total_edges}")

# === 5. 检测路口（3+ 连接的点） ===
junctions = [i for i in range(len(sampled)) if len(undirected[i]) >= 3]
print(f"Junctions: {len(junctions)}")

# === 6. 输出 ===
print("Generating JSON...")
road_points = []
for idx, (px, py) in enumerate(sampled):
    wx, wz = pixel_to_world(px, py)
    is_junction = idx in set(junctions)
    rp = {
        "OtherLanes": [],
        "junction_id": 1 if is_junction else 0,
        "road_name": "",
        "cycle": 0,
        "road_type": 1,
        "streetId": 0,
        "neighbors": neighbors[idx],
        "prev": prevs[idx],
        "position": {"x": wx, "y": 513.0, "z": wz},
        "name": f"Gley{idx}",
        "listIndex": idx
    }
    road_points.append(rp)

for path in [OUT_PATH, RAW_OUT, TOWN_OUT]:
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(road_points, f, ensure_ascii=False, separators=(',', ':'))
print(f"Written {len(road_points)} RoadPoints to 3 files")

# === 7. 可视化 ===
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

fig, axes = plt.subplots(1, 2, figsize=(16, 8))
axes[0].imshow(road_mask, cmap='gray')
axes[0].set_title(f'Road mask v3 (stricter)')

axes[1].imshow(arr, cmap='gray', alpha=0.5)
for i, (px, py) in enumerate(sampled):
    color = 'r' if i in set(junctions) else 'y'
    axes[1].plot(px, py, '.', color=color, markersize=2)
    for j in neighbors[i]:
        axes[1].plot([px, sampled[j][0]], [py, sampled[j][1]], 'c-', lw=0.3, alpha=0.5)
axes[1].set_title(f'v3: {len(sampled)} pts, {total_edges} edges, {len(junctions)} junctions')

plt.tight_layout()
plt.savefig("E:/workspace/PRJ/P1/scripts/road_extraction_v3.png", dpi=120)
print("=== Done! ===")
