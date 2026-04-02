#!/usr/bin/env python3
"""从小镇路网生成25条巡航路线，覆盖整个小镇
v3: 25条路线 + 折返消除 + 路径平滑后处理"""
import json, math, heapq, random
from collections import defaultdict

random.seed(42)

ROAD_NET = 'E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json'
OUTPUT_PACK = 'E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/traffic_routes.json'
OUTPUT_RAW = 'E:/workspace/PRJ/P1/freelifeclient/RawTables/Json/Global/traffic_waypoint/traffic_routes.json'
OUTPUT_DEBUG = 'E:/workspace/PRJ/P1/docs/new_traffic_routes.json'

with open(ROAD_NET, 'r') as f:
    raw_nodes = json.load(f)

pos = {}
for n in raw_nodes:
    pos[n['listIndex']] = (n['position']['x'], n['position']['z'])

# ==================== 图构建 ====================

# 有向图（原始）
dir_graph = defaultdict(list)
for n in raw_nodes:
    idx = n['listIndex']
    for nb in n['neighbors']:
        dir_graph[idx].append(nb)

# 无向图用于连通性桥接
graph_ud = defaultdict(set)
for n in raw_nodes:
    idx = n['listIndex']
    for nb in n['neighbors']:
        graph_ud[idx].add(nb)
        graph_ud[nb].add(idx)
    for ol in n.get('OtherLanes', []):
        graph_ud[idx].add(ol)
        graph_ud[ol].add(idx)

# 找连通分量
visited = set()
components = []
for start in range(len(raw_nodes)):
    if start in visited or start not in pos:
        continue
    queue = [start]
    visited.add(start)
    comp = []
    while queue:
        cur = queue.pop(0)
        comp.append(cur)
        for nb in graph_ud[cur]:
            if nb not in visited:
                visited.add(nb)
                queue.append(nb)
    components.append(comp)
components.sort(key=len, reverse=True)

# 构建巡航用图：无向边（neighbors + OtherLanes）+ 组件间桥接
cruise_graph = defaultdict(list)
for idx in pos:
    for nb in graph_ud[idx]:
        cruise_graph[idx].append(nb)

# 组件间桥接（近距离，双向）
for i in range(len(components)):
    for j in range(i+1, len(components)):
        best_dist = float('inf')
        best_pair = None
        for ni in components[i]:
            for nj in components[j]:
                d = math.sqrt((pos[ni][0]-pos[nj][0])**2 + (pos[ni][1]-pos[nj][1])**2)
                if d < best_dist:
                    best_dist = d
                    best_pair = (ni, nj)
        if best_pair and best_dist < 60:
            cruise_graph[best_pair[0]].append(best_pair[1])
            cruise_graph[best_pair[1]].append(best_pair[0])

# 全局可达性验证
visited2 = set()
queue = [0]
visited2.add(0)
while queue:
    cur = queue.pop(0)
    for nb in cruise_graph[cur]:
        if nb not in visited2:
            visited2.add(nb)
            queue.append(nb)
print(f"Global reachability: {len(visited2)}/{len(pos)} nodes")

# ==================== 寻路 ====================

def shortest_path(start, end):
    """Dijkstra 最短路径（有向图+桥接）"""
    dist = {start: 0}
    prev = {start: None}
    vis = set()
    heap = [(0, start)]
    while heap:
        d, cur = heapq.heappop(heap)
        if cur in vis:
            continue
        vis.add(cur)
        if cur == end:
            break
        for nb in cruise_graph[cur]:
            x1, z1 = pos[cur]
            x2, z2 = pos[nb]
            edge_len = math.sqrt((x2-x1)**2 + (z2-z1)**2)
            new_d = d + edge_len
            if nb not in dist or new_d < dist[nb]:
                dist[nb] = new_d
                prev[nb] = cur
                heapq.heappush(heap, (new_d, nb))
    if end not in prev:
        return None
    path = []
    cur = end
    while cur is not None:
        path.append(cur)
        cur = prev[cur]
    path.reverse()
    return path

# ==================== 后处理：消除折返和短段 ====================

def dist_xz(p1, p2):
    return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

def angle_between(a, b, c):
    """计算 a->b->c 的转向角度（0=直行，180=掉头）"""
    d1x, d1z = b[0]-a[0], b[1]-a[1]
    d2x, d2z = c[0]-b[0], c[1]-b[1]
    len1 = math.sqrt(d1x*d1x + d1z*d1z)
    len2 = math.sqrt(d2x*d2x + d2z*d2z)
    if len1 < 0.01 or len2 < 0.01:
        return 0
    cos_a = (d1x*d2x + d1z*d2z) / (len1 * len2)
    cos_a = max(-1, min(1, cos_a))
    return math.degrees(math.acos(cos_a))

def postprocess_route(node_path):
    """后处理路径，消除折返、重复点和极短段
    整体迭代直到收敛，确保所有类型的问题都被清除"""
    if not node_path or len(node_path) < 4:
        return node_path

    pts = [pos[n] for n in node_path]

    # 主循环：反复执行全部清理步骤直到收敛
    for iteration in range(50):
        prev_count = len(pts)

        # Step 1: 移除重复点和极近点（<1m）
        filtered = [pts[0]]
        for i in range(1, len(pts)):
            if dist_xz(pts[i], filtered[-1]) >= 1.0:
                filtered.append(pts[i])
        pts = filtered

        # Step 2: 移除锯齿（点[i-1]和点[i+1]距离 < 点[i-1]和点[i]距离*0.5）
        new_pts = [pts[0]]
        i = 1
        while i < len(pts) - 1:
            d_skip = dist_xz(pts[i-1], pts[i+1])
            d_cur = dist_xz(pts[i-1], pts[i])
            if d_skip < d_cur * 0.6 and d_skip < 10.0:
                i += 1
                continue
            new_pts.append(pts[i])
            i += 1
        if i == len(pts) - 1:
            new_pts.append(pts[-1])
        pts = new_pts

        # Step 3: 移除折返（角度 > 120°）
        # 120° 保留正常直角弯（90°），只删真正的折返/U-turn
        if len(pts) >= 3:
            new_pts = [pts[0]]
            i = 1
            while i < len(pts) - 1:
                angle = angle_between(pts[i-1], pts[i], pts[i+1])
                if angle > 120:
                    i += 1
                    continue
                new_pts.append(pts[i])
                i += 1
            if i == len(pts) - 1:
                new_pts.append(pts[-1])
            pts = new_pts

        # Step 4: 移除短段（<3m）
        filtered = [pts[0]]
        for i in range(1, len(pts) - 1):
            if dist_xz(pts[i], filtered[-1]) >= 3.0:
                filtered.append(pts[i])
        filtered.append(pts[-1])  # 保留终点
        pts = filtered

        if len(pts) < 4:
            break
        if len(pts) == prev_count:
            break  # 收敛

    return pts

# ==================== 路线规划 ====================

def nearest_node(tx, tz):
    best = None
    best_d = float('inf')
    for n in visited2:
        x, z = pos[n]
        d = (x-tx)**2 + (z-tz)**2
        if d < best_d:
            best_d = d
            best = n
    return best

# 关键区域
kp = {
    'NW':      nearest_node(-130, -48),
    'W_top':   nearest_node(-94, -10),
    'W_mid':   nearest_node(-94, 35),
    'W_bot':   nearest_node(-94, 105),
    'C_top':   nearest_node(-50, -48),
    'C_mid':   nearest_node(-50, -8),
    'C_low':   nearest_node(-30, -8),
    'E_hor':   nearest_node(20, -48),
    'E_rect':  nearest_node(40, -105),
    'E_mid':   nearest_node(85, -65),
    'FE_up':   nearest_node(150, -105),
    'N_tip':   nearest_node(35, -160),
    'S_mid':   nearest_node(20, 50),
    'SW':      nearest_node(-40, -65),
    'SE_rect': nearest_node(60, -95),
}

# 25 条巡航路线（v4：覆盖更多路段，确保过滤后仍有足够长度）
plans = [
    # === 原有 15 条 ===
    # 大环顺时针
    ['W_bot','W_mid','W_top','C_mid','C_low','E_hor','E_rect','SE_rect','E_mid','FE_up','E_mid','E_rect','E_hor','C_top','NW','W_top'],
    # 大环逆时针
    ['NW','C_top','E_hor','E_rect','E_mid','FE_up','E_mid','SE_rect','E_rect','E_hor','C_low','C_mid','W_top','W_mid','W_bot','W_mid'],
    # 西侧纵贯 + 东延
    ['W_bot','W_mid','W_top','NW','C_top','C_mid','C_low','E_hor','E_rect','SE_rect','E_rect','E_hor','C_top','NW','W_top','W_mid'],
    # 东侧巡航 + 北延
    ['N_tip','E_rect','SE_rect','E_mid','FE_up','E_mid','SE_rect','E_rect','E_hor','C_low','C_mid','C_top','E_hor'],
    # 中部穿梭
    ['C_mid','C_top','NW','W_top','W_mid','W_bot','W_mid','W_top','C_mid','C_low','E_hor','S_mid','E_hor','C_top'],
    # 全镇对角
    ['N_tip','E_rect','E_hor','C_low','C_mid','W_top','W_mid','W_bot','W_mid','W_top','NW','C_top','E_hor','E_rect'],
    # 西区+中部环路
    ['NW','C_top','C_mid','C_low','E_hor','C_top','NW','W_top','W_mid','W_bot','W_mid','W_top','NW'],
    # 极东→西侧
    ['FE_up','E_mid','SE_rect','E_rect','E_hor','C_low','C_mid','C_top','NW','W_top','W_mid','W_bot','W_mid','W_top','C_mid'],
    # 南北纵贯
    ['N_tip','E_rect','E_hor','C_low','C_mid','W_top','W_mid','W_bot','W_mid','W_top','C_mid','S_mid','E_hor','E_rect'],
    # 东区环路
    ['E_hor','E_rect','SE_rect','E_mid','FE_up','E_mid','E_rect','E_hor','C_low','C_mid','C_top','E_hor'],
    # 西北环路
    ['W_top','NW','C_top','C_mid','C_low','E_hor','C_top','NW','W_top','W_mid','W_bot','W_mid','W_top'],
    # 对角线A
    ['NW','C_top','E_hor','E_rect','SE_rect','E_mid','FE_up','E_mid','E_rect','E_hor','C_top','NW'],
    # 西→东长线
    ['W_bot','W_mid','W_top','NW','C_top','E_hor','E_rect','SE_rect','E_mid','E_rect','E_hor','C_low','C_mid','W_top'],
    # 外环
    ['NW','W_top','W_mid','W_bot','W_mid','C_mid','S_mid','E_hor','E_rect','E_mid','FE_up','E_mid','E_rect','E_hor','C_top','NW'],
    # 内环
    ['C_mid','C_low','E_hor','C_top','NW','W_top','W_mid','W_top','C_mid','C_low','E_hor','E_rect','E_hor','C_top','C_mid'],
    # === 新增 10 条，覆盖更多路段组合 ===
    # 西侧短环
    ['W_bot','W_mid','W_top','NW','C_top','C_mid','W_top','W_mid','W_bot'],
    # 东区短环
    ['E_hor','E_rect','E_mid','FE_up','E_mid','E_rect','E_hor'],
    # 中部纵贯短线
    ['C_top','C_mid','C_low','E_hor','S_mid','E_hor','C_low','C_mid','C_top'],
    # 北部横穿
    ['NW','C_top','E_hor','E_rect','N_tip','E_rect','E_hor','C_top','NW'],
    # 南部横穿
    ['W_bot','W_mid','C_mid','S_mid','E_hor','C_low','C_mid','W_mid','W_bot'],
    # 西→极东直达
    ['W_top','NW','C_top','E_hor','E_rect','SE_rect','E_mid','FE_up','E_mid','SE_rect','E_rect','E_hor','C_top','NW','W_top'],
    # 东南环路
    ['SE_rect','E_mid','FE_up','E_mid','E_rect','E_hor','C_low','C_mid','C_top','E_hor','E_rect','SE_rect'],
    # 全镇 Z 字形
    ['W_bot','W_mid','W_top','C_mid','S_mid','E_hor','E_rect','E_mid','E_rect','E_hor','C_top','NW','W_top'],
    # 逆向中部穿梭
    ['E_hor','C_low','C_mid','C_top','NW','W_top','W_mid','W_bot','W_mid','W_top','C_mid','C_low','E_hor'],
    # SW 区域巡航
    ['SW','C_mid','C_low','E_hor','C_top','C_mid','SW'],
]

generated = []
for ri, plan in enumerate(plans):
    waypoints = [kp[name] for name in plan if kp.get(name) is not None]
    waypoints.append(waypoints[0])  # 闭合

    full_path = []
    ok = True
    for i in range(len(waypoints)-1):
        if waypoints[i] == waypoints[i+1]:
            continue
        seg = shortest_path(waypoints[i], waypoints[i+1])
        if seg is None:
            print(f"Route {ri}: FAILED {waypoints[i]} -> {waypoints[i+1]}")
            ok = False
            break
        if full_path:
            seg = seg[1:]
        full_path.extend(seg)

    if not ok:
        generated.append(None)
        continue

    # 后处理：消除折返
    smoothed = postprocess_route(full_path)
    world_pts = [{"x": round(p[0], 2), "z": round(p[1], 2)} for p in smoothed]
    generated.append(world_pts)

    # 统计
    xs = [p['x'] for p in world_pts]
    zs = [p['z'] for p in world_pts]
    span = math.sqrt((max(xs)-min(xs))**2 + (max(zs)-min(zs))**2)

    # 验证：还有多少尖锐转弯
    sharp_count = 0
    for i in range(1, len(smoothed)-1):
        a = angle_between(smoothed[i-1], smoothed[i], smoothed[i+1])
        if a > 140:
            sharp_count += 1
    print(f"Route {ri}: {len(world_pts)} pts, span={span:.0f}m, sharp_turns={sharp_count}")

valid = [r for r in generated if r]
print(f"\n{len(valid)}/{len(generated)} routes generated")

output = {"routes": [{"world_points": r} for r in valid]}
for path in [OUTPUT_PACK, OUTPUT_RAW, OUTPUT_DEBUG]:
    with open(path, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"Updated: {path}")
