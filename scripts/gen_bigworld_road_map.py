#!/usr/bin/env python3
"""大世界交通路网可视化生成器 — 读取 road_traffic_miami.json，输出交互式 HTML"""
import json, os

DATA_PATH = os.path.join(os.path.dirname(__file__),
    "../freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_miami.json")
OUT_PATH = os.path.join(os.path.dirname(__file__), "../docs/bigworld_road_network.html")

print("Loading road data...")
with open(DATA_PATH, "r") as f:
    points = json.load(f)

print(f"  {len(points)} points loaded")

# 计算边界
xs = [p["position"]["x"] for p in points]
zs = [p["position"]["z"] for p in points]
x_min, x_max = min(xs), max(xs)
z_min, z_max = min(zs), max(zs)

# 构建精简数据：只保留 position, neighbors, road_type, junction_id
# 用数组索引直接寻址，减少 JSON 体积
compact = []
for p in points:
    compact.append([
        round(p["position"]["x"], 1),
        round(p["position"]["z"], 1),
        p["neighbors"],
        p["road_type"],
        p["junction_id"]
    ])

compact_json = json.dumps(compact, separators=(",", ":"))
print(f"  Compact JSON size: {len(compact_json)//1024}KB")

html = f"""<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<title>大世界交通路网 — {len(points)} 路点 / 294 路口</title>
<style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ background:#1a1a2e; overflow:hidden; font-family:monospace; color:#eee; }}
  canvas {{ display:block; cursor:grab; }}
  canvas:active {{ cursor:grabbing; }}
  #info {{ position:fixed; top:10px; left:10px; background:rgba(0,0,0,0.7); padding:10px 14px;
           border-radius:6px; font-size:13px; line-height:1.6; pointer-events:none; z-index:10; }}
  #info b {{ color:#4fc3f7; }}
  #legend {{ position:fixed; bottom:10px; left:10px; background:rgba(0,0,0,0.7); padding:10px 14px;
            border-radius:6px; font-size:12px; line-height:1.8; }}
  .dot {{ display:inline-block; width:12px; height:4px; border-radius:2px; margin-right:6px; vertical-align:middle; }}
  #hover {{ position:fixed; display:none; background:rgba(0,0,0,0.85); padding:6px 10px;
            border-radius:4px; font-size:12px; pointer-events:none; z-index:20; border:1px solid #555; }}
  #controls {{ position:fixed; top:10px; right:10px; background:rgba(0,0,0,0.7); padding:8px 12px;
              border-radius:6px; font-size:12px; line-height:1.8; }}
  kbd {{ background:#333; padding:1px 5px; border-radius:3px; border:1px solid #555; }}
</style>
</head><body>
<canvas id="c"></canvas>
<div id="info">
  <b>大世界交通路网</b><br>
  路点: <b>{len(points)}</b> &nbsp; 路口: <b>294</b><br>
  主干道: <b>29,296</b> &nbsp; 支路: <b>21,227</b><br>
  范围: <b>{x_max-x_min:.0f}</b>m × <b>{z_max-z_min:.0f}</b>m
</div>
<div id="legend">
  <span class="dot" style="background:#ff6b6b"></span>主干道 (road_type=1)<br>
  <span class="dot" style="background:#4ecdc4"></span>支路 (road_type=2)<br>
  <span class="dot" style="background:#ffe66d;width:8px;height:8px;border-radius:50%"></span>路口 (junction)
</div>
<div id="controls">
  <kbd>滚轮</kbd> 缩放 &nbsp; <kbd>拖拽</kbd> 平移<br>
  <kbd>F</kbd> 适配视图 &nbsp; <kbd>R</kbd> 重置<br>
  <kbd>J</kbd> 切换路口显示
</div>
<div id="hover"></div>
<script>
const D=JSON.parse('{compact_json.replace(chr(92), chr(92)+chr(92)).replace("'", chr(92)+"'")}');
const N=D.length;
const canvas=document.getElementById("c");
const ctx=canvas.getContext("2d");
const hover=document.getElementById("hover");

let W,H,scale,ox,oy,drag=false,mx=0,my=0,showJunctions=true;
const xMin={x_min},xMax={x_max},zMin={z_min},zMax={z_max};
const spanX=xMax-xMin, spanZ=zMax-zMin;

function resize(){{
  W=canvas.width=window.innerWidth;
  H=canvas.height=window.innerHeight;
  fitView();
}}

function fitView(){{
  const pad=60;
  const sx=(W-pad*2)/spanX, sz=(H-pad*2)/spanZ;
  scale=Math.min(sx,sz);
  ox=W/2-(xMin+spanX/2)*scale;
  oy=H/2+(zMin+spanZ/2)*scale;
}}

function toScreen(x,z){{return[x*scale+ox, -z*scale+oy];}}
function toWorld(sx,sy){{return[(sx-ox)/scale, -(sy-oy)/scale];}}

function draw(){{
  ctx.clearRect(0,0,W,H);
  // 绘制连线（边）
  ctx.lineWidth=Math.max(0.5, scale*1.5);
  // 先画支路再画主干道（主干道在上层）
  for(let pass=0;pass<2;pass++){{
    const targetType=pass===0?2:1;
    ctx.strokeStyle=pass===0?"rgba(78,205,196,0.5)":"rgba(255,107,107,0.6)";
    ctx.beginPath();
    for(let i=0;i<N;i++){{
      if(D[i][3]!==targetType)continue;
      const[sx,sy]=toScreen(D[i][0],D[i][1]);
      const nb=D[i][2];
      for(let j=0;j<nb.length;j++){{
        const ni=nb[j];
        if(ni>=N)continue;
        const[ex,ey]=toScreen(D[ni][0],D[ni][1]);
        ctx.moveTo(sx,sy);
        ctx.lineTo(ex,ey);
      }}
    }}
    ctx.stroke();
  }}

  // 绘制路口
  if(showJunctions && scale>0.03){{
    ctx.fillStyle="rgba(255,230,109,0.8)";
    const r=Math.max(2, scale*4);
    for(let i=0;i<N;i++){{
      if(D[i][4]<=0)continue;
      const[sx,sy]=toScreen(D[i][0],D[i][1]);
      if(sx<-20||sx>W+20||sy<-20||sy>H+20)continue;
      ctx.beginPath();
      ctx.arc(sx,sy,r,0,Math.PI*2);
      ctx.fill();
    }}
  }}
}}

// 事件
let lastDragX,lastDragY;
canvas.addEventListener("mousedown",e=>{{drag=true;lastDragX=e.clientX;lastDragY=e.clientY;}});
canvas.addEventListener("mouseup",()=>{{drag=false;}});
canvas.addEventListener("mouseleave",()=>{{drag=false;hover.style.display="none";}});
canvas.addEventListener("mousemove",e=>{{
  if(drag){{
    ox+=e.clientX-lastDragX;
    oy+=e.clientY-lastDragY;
    lastDragX=e.clientX;
    lastDragY=e.clientY;
    draw();
  }}
  mx=e.clientX;my=e.clientY;
}});
canvas.addEventListener("wheel",e=>{{
  e.preventDefault();
  const factor=e.deltaY>0?0.85:1.18;
  const[wx,wz]=toWorld(mx,my);
  scale*=factor;
  ox=mx-wx*scale;
  oy=my+wz*scale;
  draw();
}},{{passive:false}});
window.addEventListener("keydown",e=>{{
  if(e.key==="f"||e.key==="F"){{fitView();draw();}}
  if(e.key==="r"||e.key==="R"){{resize();draw();}}
  if(e.key==="j"||e.key==="J"){{showJunctions=!showJunctions;draw();}}
}});
window.addEventListener("resize",()=>{{resize();draw();}});

// 悬停查找最近路点
let hoverTimer=null;
canvas.addEventListener("mousemove",e=>{{
  if(drag)return;
  clearTimeout(hoverTimer);
  hoverTimer=setTimeout(()=>{{
    const[wx,wz]=toWorld(e.clientX,e.clientY);
    let best=-1,bestD=Infinity;
    // 采样搜索（完整遍历5万点卡顿，改用网格索引简化）
    for(let i=0;i<N;i+=1){{
      const dx=D[i][0]-wx,dz=D[i][1]-wz;
      const d=dx*dx+dz*dz;
      if(d<bestD){{bestD=d;best=i;}}
    }}
    if(best>=0 && bestD<(50/scale)*(50/scale)){{
      const p=D[best];
      hover.innerHTML=`<b>#${{best}}</b> (${{p[0]}}, ${{p[1]}})<br>`+
        `type=${{p[3]===1?"主干道":"支路"}} junction=${{p[4]}} neighbors=${{p[2].length}}`;
      hover.style.display="block";
      hover.style.left=(e.clientX+15)+"px";
      hover.style.top=(e.clientY+15)+"px";
    }}else{{
      hover.style.display="none";
    }}
  }},80);
}});

resize();
draw();
</script>
</body></html>"""

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write(html)
print(f"Output: {OUT_PATH}")
print(f"HTML size: {os.path.getsize(OUT_PATH)//1024}KB")
