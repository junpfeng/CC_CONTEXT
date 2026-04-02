"""生成大世界路网交互式 HTML（Plotly WebGL）"""
import json, os

PED_FILE = r"E:\workspace\PRJ\P1\freelifeclient\RawTables\Json\Server\miami_ped_road.json"
VEH_FILE = r"E:\workspace\PRJ\P1\freelifeclient\RawTables\Json\Global\traffic_waypoint\road_traffic_miami.json"
OUT_FILE = r"E:\workspace\PRJ\P1\docs\roadnet_compare.html"

print("Loading pedestrian road network...")
with open(PED_FILE, encoding='utf-8') as f:
    ped_data = json.load(f)

ped_points = []
for network in ped_data.get("lists", []):
    net_name = network.get("name", "")
    for pt in network.get("points", []):
        pos = pt["position"]
        ped_points.append({
            "id": pt["id"],
            "x": pos[0], "y": pos[1], "z": pos[2],
            "zone": pt.get("walkZone", ""),
            "net": net_name,
        })
print(f"  Pedestrian points: {len(ped_points)}")

print("Loading vehicle road network...")
with open(VEH_FILE, encoding='utf-8') as f:
    veh_data = json.load(f)

veh_points = []
for pt in veh_data:
    pos = pt["position"]
    veh_points.append({
        "idx": pt.get("listIndex", 0),
        "x": pos["x"], "y": pos["y"], "z": pos["z"],
        "name": pt.get("name", ""),
        "junc": pt.get("junction_id", 0),
        "type": pt.get("road_type", 0),
        "neighbors": pt.get("neighbors", []),
    })
print(f"  Vehicle points: {len(veh_points)}")

# ── 序列化为 JS 数组（只取需要的字段）──────────────────
def to_js_array(points, fields):
    rows = []
    for p in points:
        rows.append([p[f] for f in fields])
    return json.dumps(rows, separators=(',', ':'))

ped_js  = to_js_array(ped_points,  ["x","z","y","id","zone","net"])
veh_js  = to_js_array(veh_points,  ["x","z","y","idx","name","junc","type"])

HTML = f"""<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>大世界路网对比</title>
<script src="https://cdn.plot.ly/plotly-2.32.0.min.js"></script>
<style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ background:#0d0d1a; color:#ccc; font-family:'Segoe UI',sans-serif; }}
  #header {{ padding:12px 20px; background:#111128; border-bottom:1px solid #2a2a4a;
             display:flex; align-items:center; gap:20px; }}
  #header h1 {{ font-size:16px; color:#fff; }}
  .legend-dot {{ display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:5px; }}
  .stat {{ font-size:12px; color:#888; }}
  .stat b {{ color:#ccc; }}
  #controls {{ padding:8px 20px; background:#111128; display:flex; gap:12px; align-items:center;
               border-bottom:1px solid #1a1a3a; flex-wrap:wrap; }}
  .ctrl-btn {{ padding:5px 14px; border-radius:4px; border:1px solid #3a3a6a; background:#1a1a3a;
               color:#ccc; cursor:pointer; font-size:12px; transition:all .15s; }}
  .ctrl-btn.active {{ background:#2a2a7a; border-color:#6060cc; color:#fff; }}
  .ctrl-btn:hover {{ background:#252550; }}
  label {{ font-size:12px; color:#888; }}
  input[type=range] {{ width:100px; accent-color:#6060cc; }}
  #plot {{ width:100vw; height:calc(100vh - 90px); }}
  #info-panel {{ position:fixed; bottom:20px; right:20px; background:#111128ee;
                 border:1px solid #2a2a5a; border-radius:8px; padding:12px 16px;
                 min-width:220px; font-size:12px; display:none; z-index:999; }}
  #info-panel h3 {{ color:#fff; margin-bottom:8px; font-size:13px; }}
  #info-panel .row {{ display:flex; justify-content:space-between; gap:20px; margin:3px 0; }}
  #info-panel .key {{ color:#888; }}
  #info-panel .val {{ color:#ccc; font-weight:500; }}
</style>
</head>
<body>

<div id="header">
  <h1>大世界路网对比 (miami)</h1>
  <span><span class="legend-dot" style="background:#00d4ff"></span>
        行人路网 <span class="stat">(<b>{len(ped_points):,}</b> pts)</span></span>
  <span><span class="legend-dot" style="background:#ff6b35"></span>
        车辆路网 <span class="stat">(<b>{len(veh_points):,}</b> pts)</span></span>
  <span class="stat">覆盖 X: 行人[-4096,1531] 车辆[-7899,1531] &nbsp;|&nbsp; 滚轮缩放 · 拖动平移 · 悬停查看点信息</span>
</div>

<div id="controls">
  <span style="color:#888;font-size:12px">显示图层：</span>
  <button class="ctrl-btn active" id="btn-ped"  onclick="toggleLayer('ped')">行人路网</button>
  <button class="ctrl-btn active" id="btn-veh"  onclick="toggleLayer('veh')">车辆路网</button>
  <button class="ctrl-btn active" id="btn-conn" onclick="toggleLayer('conn')">车辆连线</button>
  <span style="color:#888;font-size:12px;margin-left:12px">点大小：</span>
  <input type="range" id="dot-size" min="1" max="8" value="2" oninput="updateDotSize(this.value)">
  <button class="ctrl-btn" onclick="resetView()">重置视图</button>
</div>

<div id="plot"></div>

<div id="info-panel" id="info">
  <h3 id="info-title">点信息</h3>
  <div id="info-body"></div>
</div>

<script>
// ── 数据 ───────────────────────────────────────────────
const PED = {ped_js};   // [x,z,y,id,zone,net]
const VEH = {veh_js};   // [x,z,y,idx,name,junc,type]

// 预计算车辆连线（邻居 → 线段 x0,x1 / z0,z1）
const VEH_MAP = {{}};
VEH.forEach(p => VEH_MAP[p[3]] = p);

// ── 构建 traces ────────────────────────────────────────
function makeTrace(pts, colorStr, name, customFields) {{
  return {{
    type: 'scattergl',
    mode: 'markers',
    name,
    x: pts.map(p=>p[0]),
    y: pts.map(p=>p[1]),
    customdata: pts.map(p => customFields(p)),
    marker: {{ color: colorStr, size: 2, opacity: 0.7, line:{{width:0}} }},
    hovertemplate: '%{{customdata}}',
    showlegend: true,
  }};
}}

const tracePed = makeTrace(
  PED, '#00d4ff', '行人路网',
  p => `id:${{p[3]}} | zone:${{p[4]||"-"}} | x:${{p[0].toFixed(1)}} z:${{p[1].toFixed(1)}} y:${{p[2].toFixed(1)}}<extra></extra>`
);

const traceVeh = makeTrace(
  VEH, '#ff6b35', '车辆路网',
  p => `idx:${{p[3]}} | junc:${{p[5]}} | type:${{p[6]}} | x:${{p[0].toFixed(1)}} z:${{p[1].toFixed(1)}} y:${{p[2].toFixed(1)}}<extra></extra>`
);

// 车辆连线（edges）— 只采样 1/3 避免过密
const ex=[], ez=[];
VEH.forEach((p,i) => {{
  if (i % 3 !== 0) return;
  // neighbors 存在 raw 数据里，这里只画相邻点连线（按 listIndex 顺序 +1）
  const next = VEH_MAP[p[3]+1];
  if (!next) return;
  ex.push(p[0], next[0], null);
  ez.push(p[1], next[1], null);
}});
const traceConn = {{
  type: 'scattergl', mode: 'lines', name: '车辆连线',
  x: ex, y: ez,
  line: {{ color: 'rgba(255,107,53,0.25)', width: 0.5 }},
  hoverinfo: 'skip', showlegend: true,
}};

const layout = {{
  paper_bgcolor: '#0d0d1a',
  plot_bgcolor: '#0d0d1a',
  xaxis: {{ title: 'X (东西)', color:'#666', gridcolor:'#1a1a3a', zerolinecolor:'#2a2a5a' }},
  yaxis: {{ title: 'Z (南北)', color:'#666', gridcolor:'#1a1a3a', zerolinecolor:'#2a2a5a',
             scaleanchor:'x', scaleratio:1 }},
  legend: {{ bgcolor:'#111128', bordercolor:'#2a2a5a', borderwidth:1, font:{{color:'#ccc'}} }},
  margin: {{ t:10, b:50, l:60, r:20 }},
  hovermode: 'closest',
  dragmode: 'pan',
}};

const config = {{
  scrollZoom: true,
  displayModeBar: true,
  modeBarButtonsToRemove: ['select2d','lasso2d'],
  displaylogo: false,
}};

Plotly.newPlot('plot', [traceConn, tracePed, traceVeh], layout, config);

// ── 图层控制 ───────────────────────────────────────────
const LAYER = {{ ped: true, veh: true, conn: true }};
const TRACE = {{ ped: 1, veh: 2, conn: 0 }};  // trace index

function toggleLayer(name) {{
  LAYER[name] = !LAYER[name];
  document.getElementById('btn-'+name).classList.toggle('active', LAYER[name]);
  Plotly.restyle('plot', {{visible: LAYER[name] ? true : 'legendonly'}}, [TRACE[name]]);
}}

function updateDotSize(v) {{
  Plotly.restyle('plot', {{'marker.size': +v}}, [1, 2]);
}}

function resetView() {{
  Plotly.relayout('plot', {{ 'xaxis.autorange': true, 'yaxis.autorange': true }});
}}
</script>
</body>
</html>"""

os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
with open(OUT_FILE, 'w', encoding='utf-8') as f:
    f.write(HTML)
print(f"Saved -> {OUT_FILE}  ({os.path.getsize(OUT_FILE)//1024} KB)")
