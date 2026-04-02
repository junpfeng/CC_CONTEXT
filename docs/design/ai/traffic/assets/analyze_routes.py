import json, math

with open(r"E:\workspace\PRJ\P1\docs\new_traffic_routes.json") as f:
    data = json.load(f)

def dist(a, b):
    return math.sqrt((a["x"]-b["x"])**2 + (a["z"]-b["z"])**2)

def angle_between(dx1, dz1, dx2, dz2):
    dot = dx1*dx2 + dz1*dz2
    m1 = math.sqrt(dx1**2+dz1**2)
    m2 = math.sqrt(dx2**2+dz2**2)
    if m1 < 1e-9 or m2 < 1e-9:
        return 0
    cos_a = max(-1, min(1, dot/(m1*m2)))
    return math.degrees(math.acos(cos_a))

routes = data["routes"]
print(f"Total routes: {len(routes)}\n")

for ri, route in enumerate(routes):
    pts = route["world_points"]
    short_segs = []
    sharp_turns = []
    dupes = []

    for i in range(len(pts)-1):
        d = dist(pts[i], pts[i+1])
        if d < 0.1:
            dupes.append((i, i+1, d))
        elif d < 2.0:
            short_segs.append((i, i+1, d))

    for i in range(len(pts)-2):
        dx1 = pts[i+1]["x"] - pts[i]["x"]
        dz1 = pts[i+1]["z"] - pts[i]["z"]
        dx2 = pts[i+2]["x"] - pts[i+1]["x"]
        dz2 = pts[i+2]["z"] - pts[i+1]["z"]
        ang = angle_between(dx1, dz1, dx2, dz2)
        if ang > 150:
            sharp_turns.append((i, i+1, i+2, ang))

    if short_segs or sharp_turns or dupes:
        print(f"=== Route {ri} ({len(pts)} pts) ===")
        if dupes:
            for a,b,d in dupes:
                print(f"  DUPLICATE: pts[{a}]-[{b}] dist={d:.3f}m")
        if short_segs:
            for a,b,d in short_segs:
                print(f"  SHORT: pts[{a}]-[{b}] dist={d:.2f}m")
        if sharp_turns:
            for a,b,c,ang in sharp_turns:
                print(f"  SHARP TURN: pts[{a}]-[{b}]-[{c}] angle={ang:.1f}°")
        print()

print("=== Done ===")
