"""从 S1Town.png 小地图提取道路中心线，生成车辆路网"""
import json
import numpy as np
from PIL import Image
from skimage.morphology import skeletonize, dilation, disk
from scipy import ndimage

# === 参数 ===
MAP_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/UI/Icon/Map/S1Town.png"
OUT_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json"
RAW_OUT = "E:/workspace/PRJ/P1/freelifeclient/RawTables/Json/Global/traffic_waypoint/road_traffic_gley.json"
TOWN_OUT = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/town_vehicle_road.json"

# 地图配置 (MapUI[22])
MAP_W, MAP_H = 2048, 2048
SCALE = 0.2056  # 1px = 0.2056 world units
OFFSET_X = 200.0  # 左上角世界 X
OFFSET_Z = -207.0  # 左上角世界 Z

# 路点采样间距 (像素)
SAMPLE_SPACING = 15  # ~3m in world

def pixel_to_world(px, py):
    """地图像素坐标 -> 世界 XZ 坐标"""
    wx = OFFSET_X - px * SCALE
    wz = OFFSET_Z + py * SCALE
    return wx, wz

def world_to_pixel(wx, wz):
    """世界 XZ -> 地图像素"""
    px = (OFFSET_X - wx) / SCALE
    py = (wz - OFFSET_Z) / SCALE
    return px, py

# === 1. 加载小地图并提取道路掩码 ===
print("Loading map...")
img = Image.open(MAP_PATH).convert('L')  # 灰度
arr = np.array(img)
print(f"Map size: {arr.shape}")

# 道路是亮灰色 (约 140-200)，建筑是深灰 (60-120)，水/边界是黑/最暗
# 阈值分离道路
road_mask = (arr > 130) & (arr < 220)  # 道路像素

# 去除边缘小噪点
road_mask = ndimage.binary_opening(road_mask, structure=np.ones((3,3)))
road_mask = ndimage.binary_closing(road_mask, structure=np.ones((5,5)))

road_pixels = np.sum(road_mask)
print(f"Road pixels: {road_pixels} ({100*road_pixels/arr.size:.1f}%)")

# === 2. 骨架化提取中心线 ===
print("Skeletonizing...")
skeleton = skeletonize(road_mask)
skel_pixels = np.sum(skeleton)
print(f"Skeleton pixels: {skel_pixels}")

# === 3. 从骨架采样路点 ===
print("Sampling waypoints...")
skel_coords = np.argwhere(skeleton)  # (row, col) = (y, x)

# 用均匀降采样 - 每 SAMPLE_SPACING 像素取一个点
# 先建立采样网格
sampled = []
used = np.zeros(skeleton.shape, dtype=bool)

for row, col in skel_coords:
    if used[row, col]:
        continue
    sampled.append((col, row))  # (x, y) in pixel coords
    # 标记附近区域为已用
    r = SAMPLE_SPACING // 2
    rmin = max(0, row - r)
    rmax = min(skeleton.shape[0], row + r + 1)
    cmin = max(0, col - r)
    cmax = min(skeleton.shape[1], col + r + 1)
    used[rmin:rmax, cmin:cmax] = True

print(f"Sampled waypoints: {len(sampled)}")

# === 4. 建立邻接关系 ===
print("Building connections...")
from scipy.spatial import KDTree

pts_array = np.array(sampled, dtype=float)
tree = KDTree(pts_array)

# 邻居搜索半径 (像素) - 路点间最大连接距离
CONNECT_RADIUS = SAMPLE_SPACING * 2.5

neighbors = [[] for _ in range(len(sampled))]
prevs = [[] for _ in range(len(sampled))]

for i, pt in enumerate(sampled):
    nearby = tree.query_ball_point(pt, CONNECT_RADIUS)
    for j in nearby:
        if j == i:
            continue
        # 检查两点之间的骨架连通性（简化：检查中点是否在道路上）
        mx = int((sampled[i][0] + sampled[j][0]) / 2)
        my = int((sampled[i][1] + sampled[j][1]) / 2)
        if 0 <= my < road_mask.shape[0] and 0 <= mx < road_mask.shape[1]:
            if road_mask[my, mx]:
                if j not in neighbors[i]:
                    neighbors[i].append(j)
                if i not in prevs[j]:
                    prevs[j].append(i)

connected = sum(1 for n in neighbors if len(n) > 0)
print(f"Connected waypoints: {connected}/{len(sampled)}")

# === 5. 转换为世界坐标并输出 GleyNav 格式 ===
print("Generating RoadPoint JSON...")
road_points = []
for idx, (px, py) in enumerate(sampled):
    wx, wz = pixel_to_world(px, py)
    rp = {
        "OtherLanes": [],
        "junction_id": 0,
        "road_name": "",
        "cycle": 0,
        "road_type": 1,
        "streetId": 0,
        "neighbors": neighbors[idx],
        "prev": prevs[idx],
        "position": {"x": round(wx, 2), "y": 513.0, "z": round(wz, 2)},
        "name": f"Gley{idx}",
        "listIndex": idx
    }
    road_points.append(rp)

print(f"Total RoadPoints: {len(road_points)}")

# 写入
for path in [OUT_PATH, RAW_OUT, TOWN_OUT]:
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(road_points, f, ensure_ascii=False, separators=(',', ':'))
    print(f"Written: {path}")

# === 6. 可视化验证 ===
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

fig, axes = plt.subplots(1, 3, figsize=(24, 8))

axes[0].imshow(arr, cmap='gray')
axes[0].set_title(f'Original ({arr.shape[0]}x{arr.shape[1]})')

axes[1].imshow(road_mask, cmap='gray')
axes[1].set_title(f'Road mask ({road_pixels} px)')

# 骨架 + 路点
axes[2].imshow(arr, cmap='gray', alpha=0.5)
skel_display = np.zeros((*skeleton.shape, 3))
skel_display[skeleton] = [0, 1, 1]  # cyan skeleton
axes[2].imshow(skel_display, alpha=0.7)
# 画路点和连接
for i, (px, py) in enumerate(sampled):
    axes[2].plot(px, py, 'y.', markersize=2)
    for j in neighbors[i]:
        axes[2].plot([px, sampled[j][0]], [py, sampled[j][1]], 'g-', lw=0.3, alpha=0.5)
axes[2].set_title(f'Waypoints ({len(sampled)}) + connections')

plt.tight_layout()
plt.savefig("E:/workspace/PRJ/P1/scripts/road_extraction_result.png", dpi=100)
print("Visualization saved")
print("Done!")
