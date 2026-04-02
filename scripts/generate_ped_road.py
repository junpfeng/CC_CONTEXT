"""从车辆路网 road_traffic_miami.json 派生行人路网 miami_ped_road.json。

沿车道法线偏移生成 footwalk 路点，按 K-means 聚类划分 5 个 WalkZone，
输出格式与 road_point.json 兼容（lists[].type / points / edges）。
"""
import json
import math
import os
import random
import sys

# ── 常量 ──────────────────────────────────────────
SIDEWALK_OFFSET = 4.0          # 车道法线偏移距离（米）
MIN_EDGE_DISTANCE = 3.0        # 相邻路点最小间距，低于此合并
MAX_EDGE_DISTANCE = 80.0       # 相邻路点最大间距，超过此断开
EDGE_WEIGHT_SCALE = 100        # 边权放大因子
NUM_ZONES = 5                  # WalkZone 分区数
KMEANS_MAX_ITER = 50           # K-means 最大迭代
COORD_CLAMP = 4096.0           # 坐标范围 [-4096, 4096]

# 路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
SOURCE_PATH = os.path.join(
    PROJECT_ROOT,
    "P1GoServer", "bin", "config", "traffic_waypoint",
    "road_traffic_miami.json",
)
OUTPUT_DIR = os.path.join(
    PROJECT_ROOT,
    "freelifeclient", "RawTables", "Json", "Server",
)
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "miami_ped_road.json")
ZONE_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "npc_zone_quota.json")


def load_vehicle_waypoints(path: str) -> list:
    """加载车辆路网 JSON（Gley 格式数组）。"""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def compute_normal_2d(dx: float, dz: float) -> tuple:
    """计算 XZ 平面法线（左侧偏移）。"""
    length = math.sqrt(dx * dx + dz * dz)
    if length < 1e-6:
        return (0.0, 0.0)
    return (-dz / length, dx / length)


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def generate_ped_points(waypoints: list) -> list:
    """沿车道法线偏移生成行人路点。

    对每个车辆路点，计算到其第一个 neighbor 的方向向量，
    沿法线偏移 SIDEWALK_OFFSET 生成行人路点。
    """
    pos_map = {}
    for wp in waypoints:
        idx = wp["listIndex"]
        pos_map[idx] = wp["position"]

    ped_points = []
    seen_positions = set()

    for wp in waypoints:
        idx = wp["listIndex"]
        pos = wp["position"]
        neighbors = wp.get("neighbors", [])

        if not neighbors:
            continue

        # 计算方向：取第一个 neighbor
        nb_pos = pos_map.get(neighbors[0])
        if nb_pos is None:
            continue

        dx = nb_pos["x"] - pos["x"]
        dz = nb_pos["z"] - pos["z"]
        nx, nz = compute_normal_2d(dx, dz)

        if abs(nx) < 1e-6 and abs(nz) < 1e-6:
            continue

        px = clamp(pos["x"] + nx * SIDEWALK_OFFSET, -COORD_CLAMP, COORD_CLAMP)
        py = pos["y"]
        pz = clamp(pos["z"] + nz * SIDEWALK_OFFSET, -COORD_CLAMP, COORD_CLAMP)

        # 量化去重（精度 0.5m）
        key = (round(px * 2) / 2, round(pz * 2) / 2)
        if key in seen_positions:
            continue
        seen_positions.add(key)

        ped_points.append({
            "id": len(ped_points) + 1,
            "position": [round(px, 3), round(py, 3), round(pz, 3)],
            "src_idx": idx,
            "neighbors_src": neighbors,
        })

    return ped_points


def build_edges(ped_points: list) -> list:
    """基于距离构建行人路点之间的边。

    对于源路网中相邻的车辆路点，如果它们派生的行人路点距离合适，
    则建立边连接。
    """
    # 建立 src_idx -> ped_point id 映射
    src_to_ped = {}
    for pp in ped_points:
        src_to_ped[pp["src_idx"]] = pp["id"]

    # 建立 id -> position 映射
    id_to_pos = {}
    for pp in ped_points:
        id_to_pos[pp["id"]] = pp["position"]

    edges_map = {}  # from_id -> set of to_ids

    for pp in ped_points:
        pid = pp["id"]
        pos = pp["position"]

        for nb_src in pp["neighbors_src"]:
            nb_ped = src_to_ped.get(nb_src)
            if nb_ped is None or nb_ped == pid:
                continue

            nb_pos = id_to_pos[nb_ped]
            dx = pos[0] - nb_pos[0]
            dz = pos[2] - nb_pos[2]
            dist = math.sqrt(dx * dx + dz * dz)

            if dist < MIN_EDGE_DISTANCE or dist > MAX_EDGE_DISTANCE:
                continue

            if pid not in edges_map:
                edges_map[pid] = set()
            edges_map[pid].add(nb_ped)

            # 双向
            if nb_ped not in edges_map:
                edges_map[nb_ped] = set()
            edges_map[nb_ped].add(pid)

    edges = []
    for from_id in sorted(edges_map.keys()):
        targets = []
        pos = id_to_pos[from_id]
        for to_id in sorted(edges_map[from_id]):
            to_pos = id_to_pos[to_id]
            dx = pos[0] - to_pos[0]
            dz = pos[2] - to_pos[2]
            dist = math.sqrt(dx * dx + dz * dz)
            weight = int(dist * EDGE_WEIGHT_SCALE)
            targets.append({"id": to_id, "weight": weight})
        edges.append({"from": from_id, "to": targets})

    return edges


def kmeans_cluster(ped_points: list, k: int) -> list:
    """K-means 聚类（XZ 平面），返回每个点的 cluster 标签。"""
    random.seed(42)

    coords = [(pp["position"][0], pp["position"][2]) for pp in ped_points]
    n = len(coords)

    # 初始化：随机选 k 个点作为中心
    indices = random.sample(range(n), k)
    centers = [coords[i] for i in indices]

    labels = [0] * n

    for _ in range(KMEANS_MAX_ITER):
        # 分配
        changed = False
        for i, (x, z) in enumerate(coords):
            best_c = 0
            best_d = float("inf")
            for c, (cx, cz) in enumerate(centers):
                d = (x - cx) ** 2 + (z - cz) ** 2
                if d < best_d:
                    best_d = d
                    best_c = c
            if labels[i] != best_c:
                labels[i] = best_c
                changed = True

        if not changed:
            break

        # 更新中心
        sums = [[0.0, 0.0, 0] for _ in range(k)]
        for i, (x, z) in enumerate(coords):
            c = labels[i]
            sums[c][0] += x
            sums[c][1] += z
            sums[c][2] += 1

        for c in range(k):
            if sums[c][2] > 0:
                centers[c] = (sums[c][0] / sums[c][2], sums[c][1] / sums[c][2])

    return labels


def compute_zone_aabbs(ped_points: list, labels: list, k: int) -> list:
    """计算每个 WalkZone 的 AABB。"""
    zones = []
    for c in range(k):
        cluster_pts = [ped_points[i] for i in range(len(labels)) if labels[i] == c]
        if not cluster_pts:
            continue

        xs = [p["position"][0] for p in cluster_pts]
        zs = [p["position"][2] for p in cluster_pts]
        ys = [p["position"][1] for p in cluster_pts]

        zones.append({
            "zoneId": f"zone_{c}",
            "pointCount": len(cluster_pts),
            "aabb": {
                "minX": round(min(xs), 1),
                "maxX": round(max(xs), 1),
                "minY": round(min(ys), 1),
                "maxY": round(max(ys), 1),
                "minZ": round(min(zs), 1),
                "maxZ": round(max(zs), 1),
            },
        })

    return zones


def check_connectivity(ped_points: list, edges: list, labels: list, k: int) -> dict:
    """检查各分区内路网连通性，返回 {zoneId: num_components}。"""
    # 建立邻接表
    adj = {}
    for e in edges:
        from_id = e["from"]
        for t in e["to"]:
            adj.setdefault(from_id, set()).add(t["id"])
            adj.setdefault(t["id"], set()).add(from_id)

    # 建立 id -> label 映射
    id_to_label = {}
    for i, pp in enumerate(ped_points):
        id_to_label[pp["id"]] = labels[i]

    result = {}
    for c in range(k):
        zone_ids = {pp["id"] for i, pp in enumerate(ped_points) if labels[i] == c}
        if not zone_ids:
            result[f"zone_{c}"] = 0
            continue

        visited = set()
        components = 0
        for start in zone_ids:
            if start in visited:
                continue
            components += 1
            # BFS
            queue = [start]
            visited.add(start)
            while queue:
                node = queue.pop(0)
                for nb in adj.get(node, set()):
                    if nb in zone_ids and nb not in visited:
                        visited.add(nb)
                        queue.append(nb)

        result[f"zone_{c}"] = components

    return result


def main():
    print(f"Loading vehicle waypoints from {SOURCE_PATH} ...")
    waypoints = load_vehicle_waypoints(SOURCE_PATH)
    print(f"  Loaded {len(waypoints)} waypoints")

    print("Generating pedestrian points (sidewalk offset) ...")
    ped_points = generate_ped_points(waypoints)
    print(f"  Generated {len(ped_points)} pedestrian points")

    print("Building edges ...")
    edges = build_edges(ped_points)
    print(f"  Built {len(edges)} edge entries")

    print(f"Running K-means clustering (k={NUM_ZONES}) ...")
    labels = kmeans_cluster(ped_points, NUM_ZONES)

    zone_aabbs = compute_zone_aabbs(ped_points, labels, NUM_ZONES)
    print("  Zone AABBs:")
    for z in zone_aabbs:
        print(f"    {z['zoneId']}: {z['pointCount']} points, AABB={z['aabb']}")

    connectivity = check_connectivity(ped_points, edges, labels, NUM_ZONES)
    print("  Connectivity:")
    for zid, ncomp in connectivity.items():
        print(f"    {zid}: {ncomp} component(s)")

    # 为每个点标注 walkZone
    for i, pp in enumerate(ped_points):
        pp["walkZone"] = f"zone_{labels[i]}"

    # 清理中间字段
    clean_points = []
    for pp in ped_points:
        clean_points.append({
            "id": pp["id"],
            "position": pp["position"],
            "walkZone": pp["walkZone"],
        })

    # 输出 road_point.json 兼容格式
    output = {
        "name": "miami_bigworld",
        "lists": [
            {
                "id": 1,
                "name": "miami_ped_network",
                "type": "footwalk",
                "points": clean_points,
                "edges": edges,
            }
        ],
        "zones": zone_aabbs,
    }

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print(f"\nWrote {OUTPUT_PATH}")
    print(f"  {len(clean_points)} points, {len(edges)} edge entries")

    # 输出 zone 信息供 npc_zone_quota.json 使用
    zone_info_path = os.path.join(OUTPUT_DIR, "_zone_info.json")
    with open(zone_info_path, "w", encoding="utf-8") as f:
        json.dump(zone_aabbs, f, ensure_ascii=False, indent=2)
    print(f"Wrote zone info to {zone_info_path}")

    # 验证
    print("\n=== Validation ===")
    all_footwalk = all(
        lst["type"] == "footwalk" for lst in output["lists"]
    )
    print(f"  All lists type=footwalk: {all_footwalk}")

    all_in_range = all(
        -COORD_CLAMP <= p["position"][0] <= COORD_CLAMP
        and -COORD_CLAMP <= p["position"][2] <= COORD_CLAMP
        for p in clean_points
    )
    print(f"  All coords in [-{COORD_CLAMP}, {COORD_CLAMP}]: {all_in_range}")
    print(f"  Zone count: {len(zone_aabbs)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
