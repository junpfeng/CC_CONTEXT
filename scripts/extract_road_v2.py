"""从 S1Town.png 小地图提取双车道交通路网 v3"""
import json, math, os
import numpy as np
from PIL import Image
from skimage.morphology import skeletonize
from scipy import ndimage
from scipy.spatial import KDTree
from scipy.interpolate import splprep, splev

MAP_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/UI/Icon/Map/S1Town.png"
OUT_PATH = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json"
RAW_OUT  = "E:/workspace/PRJ/P1/freelifeclient/RawTables/Json/Global/traffic_waypoint/road_traffic_gley.json"
TOWN_OUT = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/town_vehicle_road.json"

LOGICAL_SIZE = 2048
MAP_SCALE = 0.2056
OFFSET_X = 200.0
OFFSET_Z = -207.0

LANE_OFFSET = 2.5    # 车道偏移 (米)
SAMPLE_DIST = 5.0    # 采样间距 (米)

print("Loading map...")
img = Image.open(MAP_PATH).convert('L')
arr = np.array(img)
H, W = arr.shape
PS = MAP_SCALE * LOGICAL_SIZE / W
LANE_PX = LANE_OFFSET / PS
SAMPLE_PX = SAMPLE_DIST / PS
print(f"Map {W}x{H}, PS={PS:.4f} m/px, lane={LANE_PX:.0f}px, sample={SAMPLE_PX:.0f}px")

def px2world(col, row):
    return round(OFFSET_X - col * PS, 2), round(OFFSET_Z + row * PS, 2)

# ========== Step 1: 道路掩码 ==========
print("Step 1: Road mask...")
road_mask = (arr > 95) & (arr < 215)
bg_dilated = ndimage.binary_dilation(arr > 230, iterations=10)
water_dilated = ndimage.binary_dilation(arr < 35, iterations=3)
road_mask = road_mask & ~bg_dilated & ~water_dilated
road_mask = ndimage.binary_opening(road_mask, structure=np.ones((5,5)))
road_mask = ndimage.binary_closing(road_mask, structure=np.ones((7,7)))
labeled, nf = ndimage.label(road_mask)
sizes = ndimage.sum(road_mask, labeled, range(1, nf+1))
for i, s in enumerate(sizes):
    if s < 500:
        road_mask[labeled == (i+1)] = False
print(f"  Road pixels: {np.sum(road_mask)}")

# ========== Step 2: 骨架 + 路口检测 ==========
print("Step 2: Skeleton + junctions...")
skel = skeletonize(road_mask)

# 检测分叉点 (3x3邻居>=3)
kern = np.ones((3,3), dtype=int); kern[1,1] = 0
nb_count = ndimage.convolve(skel.astype(int), kern, mode='constant', cval=0)
branch_mask = skel & (nb_count >= 3)
# 膨胀分叉区域（仅膨胀4像素，避免切碎道路段）
junc_dilated = ndimage.binary_dilation(branch_mask, iterations=4)
# 从骨架中移除路口区域，得到独立道路段
skel_no_junc = skel & ~junc_dilated
# 标记路口区域质心
jlabeled, n_junc = ndimage.label(junc_dilated & skel)
junc_centroids = []
if n_junc > 0:
    junc_centroids = ndimage.center_of_mass(junc_dilated & skel, jlabeled, range(1, n_junc+1))
    junc_centroids = [(c[1], c[0]) for c in junc_centroids]  # (col, row)
print(f"  Junctions: {n_junc}, skeleton segments after removal...")

# ========== Step 3: 追踪道路段 ==========
seg_labeled, n_seg = ndimage.label(skel_no_junc)
print(f"  Raw segments: {n_seg}")

def trace_segment(mask):
    """追踪一个连通域的骨架像素，返回有序的(col,row)列表"""
    coords = np.argwhere(mask)  # (row, col)
    if len(coords) < 2:
        return []
    # 建立像素集合便于查找
    px_set = set(map(tuple, coords))
    # 找端点（只有1个骨架邻居的像素）
    def count_nb(r, c):
        cnt = 0
        for dr in [-1, 0, 1]:
            for dc in [-1, 0, 1]:
                if dr == 0 and dc == 0: continue
                if (r+dr, c+dc) in px_set: cnt += 1
        return cnt
    endpoints = [(r,c) for r,c in coords if count_nb(r,c) == 1]
    start = endpoints[0] if endpoints else tuple(coords[0])

    # 顺序追踪（每步只走一个未访问邻居）
    visited = {start}
    path = [(start[1], start[0])]  # (col, row)
    cur = start
    while True:
        found = False
        for dr in [-1, 0, 1]:
            for dc in [-1, 0, 1]:
                if dr == 0 and dc == 0: continue
                nr, nc = cur[0]+dr, cur[1]+dc
                if (nr, nc) in px_set and (nr, nc) not in visited:
                    visited.add((nr, nc))
                    path.append((nc, nr))
                    cur = (nr, nc)
                    found = True
                    break
            if found: break
        if not found: break
    return path

segments = []
seg_sizes = ndimage.sum(skel_no_junc, seg_labeled, range(1, n_seg+1))
valid_ids = [i+1 for i, s in enumerate(seg_sizes) if s >= 50]
print(f"  Segments >= 50px: {len(valid_ids)} / {n_seg}")
for i, si in enumerate(valid_ids):
    if i % 20 == 0:
        print(f"    Tracing {i}/{len(valid_ids)}...")
    seg_mask = seg_labeled == si
    path = trace_segment(seg_mask)
    if len(path) >= 5:
        segments.append(path)
print(f"  Valid segments: {len(segments)}")

# ========== Step 4: 平滑 + 采样 + 双车道 ==========
print("Step 4: Smooth + dual lanes...")

all_points = []     # (col, row, junction_id, lane_type, other_lane_idx)
all_neighbors = []  # [[neighbor indices]]
all_prevs = []

def add_pt(col, row, jid=0, ltype='right', other=-1):
    idx = len(all_points)
    all_points.append((float(col), float(row), jid, ltype, other))
    all_neighbors.append([])
    all_prevs.append([])
    return idx

def add_edge(a, b):
    if b not in all_neighbors[a]:
        all_neighbors[a].append(b)
    if a not in all_prevs[b]:
        all_prevs[b].append(a)

def smooth_and_sample(path_px):
    """平滑路径并等距采样，返回采样点和切线方向"""
    cols = np.array([p[0] for p in path_px], dtype=float)
    rows = np.array([p[1] for p in path_px], dtype=float)

    # 计算路径总长
    diffs = np.sqrt(np.diff(cols)**2 + np.diff(rows)**2)
    total_len = np.sum(diffs)
    if total_len < SAMPLE_PX * 2:
        return [], []

    # 样条拟合平滑
    try:
        # 去重（splprep不允许重复点）
        mask = np.ones(len(cols), dtype=bool)
        for i in range(1, len(cols)):
            if abs(cols[i]-cols[i-1]) < 0.5 and abs(rows[i]-rows[i-1]) < 0.5:
                mask[i] = False
        cols, rows = cols[mask], rows[mask]
        if len(cols) < 4:
            return [], []

        # 平滑因子根据长度调整
        s = len(cols) * 2
        k = min(3, len(cols)-1)
        tck, u = splprep([cols, rows], s=s, k=k)

        # 等距采样
        n_samples = max(2, int(total_len / SAMPLE_PX))
        u_new = np.linspace(0, 1, n_samples)
        smooth_cols, smooth_rows = splev(u_new, tck)

        # 计算切线方向
        dc, dr = splev(u_new, tck, der=1)
        tangents = list(zip(dc, dr))

        points = list(zip(smooth_cols, smooth_rows))
        return points, tangents
    except Exception:
        return [], []

seg_endpoints = []  # 每段的端点信息

for seg_path in segments:
    pts, tangents = smooth_and_sample(seg_path)
    if len(pts) < 2:
        continue

    right_indices = []  # 正向车道 (右侧通行)
    left_indices = []   # 反向车道

    for i, ((col, row), (tc, tr)) in enumerate(zip(pts, tangents)):
        # 归一化切线
        tlen = math.hypot(tc, tr)
        if tlen < 1e-6:
            tc, tr = 1.0, 0.0
        else:
            tc, tr = tc/tlen, tr/tlen

        # 法线：右侧 = (tr, -tc)，左侧 = (-tr, tc)
        # 右车道点（正向行驶方向的右侧）
        rc = col + tr * LANE_PX
        rr = row - tc * LANE_PX
        # 检查是否在道路上，不在则回退
        ri, rj = int(round(rr)), int(round(rc))
        if not (0 <= ri < H and 0 <= rj < W and road_mask[ri, rj]):
            rc, rr = col, row

        # 左车道点（反向行驶方向）
        lc = col - tr * LANE_PX
        lr = row + tc * LANE_PX
        li, lj = int(round(lr)), int(round(lc))
        if not (0 <= li < H and 0 <= lj < W and road_mask[li, lj]):
            lc, lr = col, row

        r_idx = add_pt(rc, rr, ltype='right')
        l_idx = add_pt(lc, lr, ltype='left')

        # 设置 OtherLanes 互相引用
        all_points[r_idx] = (*all_points[r_idx][:4], l_idx)
        all_points[l_idx] = (*all_points[l_idx][:4], r_idx)

        right_indices.append(r_idx)
        left_indices.append(l_idx)

    # 右车道：正向链 (0→1→2→...→N)
    for i in range(len(right_indices) - 1):
        add_edge(right_indices[i], right_indices[i+1])

    # 左车道：反向链 (N→N-1→...→1→0)
    for i in range(len(left_indices) - 1, 0, -1):
        add_edge(left_indices[i], left_indices[i-1])

    # 记录端点
    seg_endpoints.append({
        'r_start': right_indices[0],   'r_end': right_indices[-1],
        'l_start': left_indices[0],    'l_end': left_indices[-1],
        'start_px': pts[0],            'end_px': pts[-1]
    })

print(f"  Lane points: {len(all_points)}, segments: {len(seg_endpoints)}")

# ========== Step 5: 路口连接 ==========
print("Step 5: Junction connections...")

# 收集所有道路段端点位置
endpoint_data = []  # (col, row, seg_idx, is_start)
for si, se in enumerate(seg_endpoints):
    endpoint_data.append((se['start_px'][0], se['start_px'][1], si, True))
    endpoint_data.append((se['end_px'][0], se['end_px'][1], si, False))

if junc_centroids and endpoint_data:
    ep_arr = np.array([(e[0], e[1]) for e in endpoint_data])
    ep_tree = KDTree(ep_arr)
    junc_snap = SAMPLE_PX * 3  # 路口snap距离

    for ji, (jc, jr) in enumerate(junc_centroids):
        # 找路口附近的端点
        nearby = ep_tree.query_ball_point([jc, jr], junc_snap)
        if len(nearby) < 2:
            continue

        # 创建路口中心点
        jc_idx = add_pt(jc, jr, jid=ji+1, ltype='junction')

        # 收集到达和出发的车道端点
        for ei in nearby:
            _, _, si, is_start = endpoint_data[ei]
            se = seg_endpoints[si]

            if is_start:
                # 段起点在路口旁：正向车道从此出发，反向车道到此结束
                add_edge(jc_idx, se['r_start'])   # 路口→正向出发
                add_edge(se['l_start'], jc_idx)    # 反向到达→路口
            else:
                # 段终点在路口旁：正向车道到此结束，反向车道从此出发
                add_edge(se['r_end'], jc_idx)      # 正向到达→路口
                add_edge(jc_idx, se['l_end'])       # 路口→反向出发

junc_count = sum(1 for p in all_points if p[2] > 0)
print(f"  Total: {len(all_points)} points, {junc_count} junctions")

# ========== Step 6: 输出 JSON ==========
print("Step 6: Writing JSON...")
road_points = []
for idx, (col, row, jid, ltype, other) in enumerate(all_points):
    wx, wz = px2world(col, row)
    rp = {
        "OtherLanes": [other] if other >= 0 else [],
        "junction_id": jid,
        "road_name": "",
        "cycle": 0,
        "road_type": 1,
        "streetId": 0,
        "neighbors": all_neighbors[idx],
        "prev": all_prevs[idx],
        "position": {"x": wx, "y": 513.0, "z": wz},
        "name": f"Gley{idx}",
        "listIndex": idx
    }
    road_points.append(rp)

for path in [OUT_PATH, RAW_OUT, TOWN_OUT]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(road_points, f, ensure_ascii=False, separators=(',', ':'))
print(f"  Written {len(road_points)} RoadPoints")

# ========== Step 7: 可视化 ==========
print("Step 7: Visualization...")
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

fig, axes = plt.subplots(1, 2, figsize=(20, 10))

# 左图：道路掩码+骨架段
axes[0].imshow(road_mask, cmap='gray')
colors = plt.cm.Set1(np.linspace(0, 1, max(len(segments), 1)))
for si, seg in enumerate(segments):
    sc = [p[0] for p in seg]
    sr = [p[1] for p in seg]
    axes[0].plot(sc, sr, color=colors[si % len(colors)], lw=0.5, alpha=0.8)
axes[0].set_title(f'Road mask + {len(segments)} segments')

# 右图：双车道叠加地图（批量收集线段，一次性画，避免逐条plot卡死）
axes[1].imshow(arr, cmap='gray', alpha=0.4)
from matplotlib.collections import LineCollection
r_segs, b_segs, y_segs = [], [], []
for idx, (col, row, jid, ltype, other) in enumerate(all_points):
    for ni in all_neighbors[idx]:
        nc, nr = all_points[ni][0], all_points[ni][1]
        seg = [(col, row), (nc, nr)]
        if ltype == 'right':
            r_segs.append(seg)
        elif ltype == 'left':
            b_segs.append(seg)
        else:
            y_segs.append(seg)
if r_segs:
    axes[1].add_collection(LineCollection(r_segs, colors='red', linewidths=0.6, alpha=0.7))
if b_segs:
    axes[1].add_collection(LineCollection(b_segs, colors='blue', linewidths=0.6, alpha=0.7))
if y_segs:
    axes[1].add_collection(LineCollection(y_segs, colors='yellow', linewidths=0.8, alpha=0.8))
# 路口点
jx = [p[0] for p in all_points if p[2] > 0]
jy = [p[1] for p in all_points if p[2] > 0]
if jx:
    axes[1].plot(jx, jy, 'y*', markersize=4)
axes[1].set_xlim(0, W); axes[1].set_ylim(H, 0)
r_cnt = sum(1 for p in all_points if p[3] == 'right')
l_cnt = sum(1 for p in all_points if p[3] == 'left')
axes[1].set_title(f'Dual lanes: R={r_cnt} B={l_cnt} J={junc_count}')

plt.tight_layout()
plt.savefig("E:/workspace/PRJ/P1/scripts/road_extraction_v2.png", dpi=150)
print("Done!")
