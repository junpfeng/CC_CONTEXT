"""将 road_traffic_fl.json (nodes+links) 转换为 GleyNav RoadPoint 格式"""
import json
from collections import defaultdict

fl_path = "E:/workspace/PRJ/P1/freelifeclient/Assets/DesignConfig/GleyData/MapInfo/road_traffic_fl.json"
out_path = "E:/workspace/PRJ/P1/freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json"
raw_out = "E:/workspace/PRJ/P1/freelifeclient/RawTables/Json/Global/traffic_waypoint/road_traffic_gley.json"

with open(fl_path, 'r', encoding='utf-8') as f:
    fl_data = json.load(f)

nodes = fl_data['nodes']
links = fl_data['links']

print(f"Input: {len(nodes)} nodes, {len(links)} links")

# 构建 neighbors 和 prev
neighbors = defaultdict(list)
prevs = defaultdict(list)
for link in links:
    s, e = link['start_node'], link['end_node']
    if e not in neighbors[s]:
        neighbors[s].append(e)
    if s not in prevs[e]:
        prevs[e].append(s)

# 确保 node id 是连续的 0..N-1
node_ids = sorted(n['id'] for n in nodes)
max_id = max(node_ids) if node_ids else 0
print(f"Node ID range: [0, {max_id}], count={len(node_ids)}")

# 如果 id 不连续，需要建映射
id_set = set(node_ids)
need_remap = len(node_ids) != max_id + 1
if need_remap:
    print(f"WARNING: Node IDs not contiguous, need remap")
    # 建立 old_id -> new_id 映射
    old_to_new = {old: new for new, old in enumerate(node_ids)}
else:
    old_to_new = {i: i for i in node_ids}

# 构建 node_id -> node 映射
node_map = {n['id']: n for n in nodes}

# 转换为 RoadPoint 格式
road_points = []
for new_idx, old_id in enumerate(node_ids):
    node = node_map[old_id]
    
    # 映射 neighbors/prev 到新索引
    nb_new = [old_to_new[n] for n in neighbors.get(old_id, []) if n in old_to_new]
    prev_new = [old_to_new[p] for p in prevs.get(old_id, []) if p in old_to_new]
    
    rp = {
        "OtherLanes": [],
        "junction_id": node.get('junction_id', 0),
        "road_name": "",
        "cycle": 0,
        "road_type": node.get('road_id', 1) if node.get('road_id', 0) > 0 else 1,
        "streetId": node.get('street_id', 0),
        "neighbors": nb_new,
        "prev": prev_new,
        "position": node['position'],
        "name": f"Gley{new_idx}",
        "listIndex": new_idx
    }
    road_points.append(rp)

print(f"Output: {len(road_points)} RoadPoints")

# 统计
has_nb = sum(1 for rp in road_points if rp['neighbors'])
has_prev = sum(1 for rp in road_points if rp['prev'])
has_junction = sum(1 for rp in road_points if rp['junction_id'] != 0)
print(f"With neighbors: {has_nb}, with prev: {has_prev}, junctions: {has_junction}")

# 写入
for path in [out_path, raw_out]:
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(road_points, f, ensure_ascii=False, separators=(',', ':'))
    print(f"Written: {path}")

# 也更新 town_vehicle_road.json (之前是 gley 的副本)
town_path = out_path.replace('road_traffic_gley.json', 'town_vehicle_road.json')
with open(town_path, 'w', encoding='utf-8') as f:
    json.dump(road_points, f, ensure_ascii=False, separators=(',', ':'))
print(f"Written: {town_path}")

print("Done!")
