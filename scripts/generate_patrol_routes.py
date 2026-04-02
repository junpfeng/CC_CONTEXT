"""从行人路网 miami_ped_road.json 自动生成环形巡逻路线。

输出 15-25 条路线 JSON 到 ai_patrol/bigworld/ 目录，
每条路线 8-15 个节点，30% 节点带 duration + behaviorType。
格式与 PatrolRoute JSON 兼容（routeId/name/routeType/desiredNpcCount/nodes）。
"""
import json
import math
import os
import random
import sys
from collections import deque

# ── 常量 ──────────────────────────────────────────
MIN_ROUTES = 15
MAX_ROUTES = 25
MIN_NODES_PER_ROUTE = 8
MAX_NODES_PER_ROUTE = 15
BEHAVIOR_NODE_RATIO = 0.3      # 30% 节点带 duration + behaviorType
DESIRED_NPC_PER_ROUTE = 2      # 每条路线期望 NPC 数
ROUTE_TYPE_PERMANENT = 0

# 行为类型枚举（动画 ID）
BEHAVIOR_TYPES = [1, 2, 3, 4, 5]  # idle_look, sit, lean, phone, wave
BEHAVIOR_DURATIONS = [2000, 3000, 4000, 5000, 8000]  # ms

# 路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
INPUT_PATH = os.path.join(
    PROJECT_ROOT,
    "freelifeclient", "RawTables", "Json", "Server",
    "miami_ped_road.json",
)
OUTPUT_DIR = os.path.join(
    PROJECT_ROOT,
    "freelifeclient", "RawTables", "Json", "Server",
    "ai_patrol", "bigworld",
)


def load_ped_road(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_adjacency(road_data: dict) -> tuple:
    """构建邻接表和点位字典。返回 (adj, points_by_id, zone_points)。"""
    adj = {}
    points_by_id = {}
    zone_points = {}  # walkZone -> list of point ids

    for lst in road_data["lists"]:
        for p in lst["points"]:
            pid = p["id"]
            points_by_id[pid] = p
            zone = p.get("walkZone", "zone_0")
            zone_points.setdefault(zone, []).append(pid)

        for edge in lst["edges"]:
            from_id = edge["from"]
            for t in edge["to"]:
                adj.setdefault(from_id, set()).add(t["id"])
                adj.setdefault(t["id"], set()).add(from_id)

    return adj, points_by_id, zone_points


def find_loop_route(
    adj: dict,
    points_by_id: dict,
    start_id: int,
    target_length: int,
    used_ids: set,
) -> list:
    """从 start_id 出发，用 DFS + 回溯寻找一条近似环形路线。

    返回点 ID 列表（首尾可连通），长度在 [target_length-2, target_length+2] 范围内。
    优先选择未被其他路线使用的点。
    """
    path = [start_id]
    visited = {start_id}

    for _ in range(target_length * 3):
        current = path[-1]
        neighbors = list(adj.get(current, set()))
        if not neighbors:
            break

        # 优先选未访问、未被使用的邻居
        unvisited = [n for n in neighbors if n not in visited]
        if not unvisited:
            # 如果路径够长，尝试闭环
            if len(path) >= target_length - 2:
                # 检查是否能回到起点附近
                for n in neighbors:
                    if n == start_id or n in adj.get(start_id, set()):
                        return path
                return path
            break

        # 排序：优先选未被使用的
        unused = [n for n in unvisited if n not in used_ids]
        candidates = unused if unused else unvisited

        # 随机选一个（带权重偏向距离适中的）
        next_id = random.choice(candidates)
        path.append(next_id)
        visited.add(next_id)

        if len(path) >= target_length:
            # 尝试闭环
            last_neighbors = adj.get(next_id, set())
            if start_id in last_neighbors or any(
                n in adj.get(start_id, set()) for n in last_neighbors
            ):
                return path
            # 路径够长就返回
            return path

    return path if len(path) >= MIN_NODES_PER_ROUTE else []


def compute_heading_deg(from_pos: list, to_pos: list) -> float:
    """计算从 from_pos 到 to_pos 的朝向（度数）。"""
    dx = to_pos[0] - from_pos[0]
    dz = to_pos[2] - from_pos[2]
    # atan2 返回弧度，转度数，Unity Y轴旋转
    heading_rad = math.atan2(dx, dz)
    heading_deg = math.degrees(heading_rad)
    if heading_deg < 0:
        heading_deg += 360
    return round(heading_deg, 1)


def create_patrol_route(
    route_id: int,
    name: str,
    walk_zone: str,
    path_ids: list,
    points_by_id: dict,
) -> dict:
    """将路径点 ID 列表转换为 PatrolRoute JSON 格式。"""
    nodes = []
    num_nodes = len(path_ids)
    behavior_count = max(1, int(num_nodes * BEHAVIOR_NODE_RATIO))
    behavior_indices = set(random.sample(range(num_nodes), behavior_count))

    for i, pid in enumerate(path_ids):
        pt = points_by_id[pid]
        pos = pt["position"]

        # 计算朝向：指向下一个节点
        if i < num_nodes - 1:
            next_pt = points_by_id[path_ids[i + 1]]
            heading = compute_heading_deg(pos, next_pt["position"])
        else:
            # 最后一个节点指向第一个（环形）
            first_pt = points_by_id[path_ids[0]]
            heading = compute_heading_deg(pos, first_pt["position"])

        # 链接：指向下一个节点（环形：最后指向第一个）
        next_node_id = i + 2 if i < num_nodes - 1 else 1
        links = [next_node_id]

        duration = 0
        behavior_type = 0
        if i in behavior_indices:
            duration = random.choice(BEHAVIOR_DURATIONS)
            behavior_type = random.choice(BEHAVIOR_TYPES)

        nodes.append({
            "nodeId": i + 1,
            "position": {"x": pos[0], "y": pos[1], "z": pos[2]},
            "heading": heading,
            "duration": duration,
            "behaviorType": behavior_type,
            "links": links,
        })

    return {
        "routeId": route_id,
        "name": name,
        "routeType": ROUTE_TYPE_PERMANENT,
        "desiredNpcCount": DESIRED_NPC_PER_ROUTE,
        "walkZone": walk_zone,
        "nodes": nodes,
    }


def generate_routes(
    adj: dict,
    points_by_id: dict,
    zone_points: dict,
    target_count: int,
) -> list:
    """为各 WalkZone 生成巡逻路线，总数在 [MIN_ROUTES, MAX_ROUTES] 范围。"""
    random.seed(42)

    zones = sorted(zone_points.keys())
    num_zones = len(zones)
    if num_zones == 0:
        print("ERROR: no zones found")
        return []

    # 按点数加权分配每个 zone 的路线数
    total_pts = sum(len(zone_points[z]) for z in zones)
    routes_per_zone = {}
    allocated = 0
    for z in zones:
        count = max(1, round(target_count * len(zone_points[z]) / total_pts))
        routes_per_zone[z] = count
        allocated += count

    # 调整总数
    while allocated > target_count:
        for z in zones:
            if routes_per_zone[z] > 1 and allocated > target_count:
                routes_per_zone[z] -= 1
                allocated -= 1
    while allocated < target_count:
        for z in zones:
            if allocated < target_count:
                routes_per_zone[z] += 1
                allocated += 1

    routes = []
    route_id = 1
    used_ids = set()

    for zone in zones:
        zone_pts = zone_points[zone]
        num_routes = routes_per_zone[zone]

        for r in range(num_routes):
            target_length = random.randint(MIN_NODES_PER_ROUTE, MAX_NODES_PER_ROUTE)

            # 选起点：优先未使用的点
            unused_starts = [p for p in zone_pts if p not in used_ids]
            if not unused_starts:
                unused_starts = zone_pts

            start = random.choice(unused_starts)
            path = find_loop_route(adj, points_by_id, start, target_length, used_ids)

            if len(path) < MIN_NODES_PER_ROUTE:
                # 尝试另一个起点
                for _ in range(5):
                    start = random.choice(zone_pts)
                    path = find_loop_route(
                        adj, points_by_id, start, target_length, used_ids
                    )
                    if len(path) >= MIN_NODES_PER_ROUTE:
                        break

            if len(path) < MIN_NODES_PER_ROUTE:
                print(f"  WARNING: zone {zone} route {r} only {len(path)} nodes, skipping")
                continue

            # 截断到 MAX_NODES_PER_ROUTE
            if len(path) > MAX_NODES_PER_ROUTE:
                path = path[:MAX_NODES_PER_ROUTE]

            used_ids.update(path)

            route = create_patrol_route(
                route_id,
                f"bigworld_patrol_{route_id:03d}",
                zone,
                path,
                points_by_id,
            )
            routes.append(route)
            route_id += 1

    return routes


def main():
    print(f"Loading pedestrian road from {INPUT_PATH} ...")
    road_data = load_ped_road(INPUT_PATH)

    adj, points_by_id, zone_points = build_adjacency(road_data)
    print(f"  {len(points_by_id)} points, {len(zone_points)} zones")
    for z in sorted(zone_points.keys()):
        print(f"    {z}: {len(zone_points[z])} points")

    target_count = random.randint(MIN_ROUTES, MAX_ROUTES)
    # 固定种子后重新计算
    random.seed(42)
    target_count = 20  # 中间值，确保在 15-25 范围内

    print(f"\nGenerating {target_count} patrol routes ...")
    routes = generate_routes(adj, points_by_id, zone_points, target_count)

    print(f"\nGenerated {len(routes)} routes:")
    for route in routes:
        behavior_nodes = sum(1 for n in route["nodes"] if n["duration"] > 0)
        print(
            f"  {route['name']}: {len(route['nodes'])} nodes, "
            f"{behavior_nodes} behavior, zone={route['walkZone']}"
        )

    # 输出每条路线到单独文件
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for route in routes:
        filename = f"{route['name']}.json"
        filepath = os.path.join(OUTPUT_DIR, filename)
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(route, f, ensure_ascii=False, indent=2)

    print(f"\nWrote {len(routes)} route files to {OUTPUT_DIR}")

    # 验证
    print("\n=== Validation ===")
    print(f"  Route count: {len(routes)} (target: {MIN_ROUTES}-{MAX_ROUTES})")
    all_have_zone = all("walkZone" in r for r in routes)
    print(f"  All routes have walkZone: {all_have_zone}")
    node_counts = [len(r["nodes"]) for r in routes]
    print(f"  Node counts: min={min(node_counts)}, max={max(node_counts)}")

    total_behavior = sum(
        sum(1 for n in r["nodes"] if n["duration"] > 0)
        for r in routes
    )
    total_nodes = sum(len(r["nodes"]) for r in routes)
    ratio = total_behavior / total_nodes if total_nodes > 0 else 0
    print(f"  Behavior node ratio: {ratio:.1%} (target: ~30%)")

    if len(routes) < MIN_ROUTES:
        print(f"  WARNING: only {len(routes)} routes, below minimum {MIN_ROUTES}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
