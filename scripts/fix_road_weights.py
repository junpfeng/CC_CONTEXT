"""
将行人路网 JSON 中的边权重改为 XZ 平面欧氏距离（取整）。
用途：使 A* 寻路按真实地理距离寻路，替代原来的均一权重 100。
"""
import json
import math

INPUT = 'freelifeclient/RawTables/Json/Server/Waypoints/town_ped_road.json'

with open(INPUT, encoding='utf-8') as f:
    data = json.load(f)

total_edges = 0
for net in data['lists']:
    # 建立 id → position 映射
    pos_map = {p['id']: p['position'] for p in net['points']}
    for edge in net['edges']:
        fx, _, fz = pos_map[edge['from']]
        for dst in edge['to']:
            tx, _, tz = pos_map[dst['id']]
            dist = math.sqrt((tx - fx) ** 2 + (tz - fz) ** 2)
            dst['weight'] = max(1, round(dist))  # 取整，最小为 1（避免随机漫步除零）
            total_edges += 1

with open(INPUT, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))

# 验证权重分布
all_weights = [d['weight'] for net in data['lists'] for e in net['edges'] for d in e['to']]
print(f'done. {total_edges} edges updated.')
print(f'weight range: {min(all_weights)} ~ {max(all_weights)}')
print(f'unique weights: {len(set(all_weights))}')
