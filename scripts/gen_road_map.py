#!/usr/bin/env python3
"""生成小镇路网可视化HTML - 基于小地图提取的路点数据 + 行人路网"""
import json, os, sys, base64
sys.stdout.reconfigure(encoding='utf-8')

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROAD_PATH = os.path.join(BASE, "freelifeclient/Assets/PackResources/Config/Data/traffic_waypoint/road_traffic_gley.json")
PED_PATH  = os.path.join(BASE, "freelifeclient/RawTables/Json/Server/Waypoints/town_ped_road.json")
MAP_IMG   = os.path.join(BASE, "freelifeclient/Assets/PackResources/UI/Icon/Map/S1Town.png")
OUTPUT    = os.path.join(BASE, "docs/town_road_network.html")

# 地图坐标参数
LOGICAL_SIZE = 2048
MAP_SCALE = 0.2056
OFFSET_X = 200.0
OFFSET_Z = -207.0

# 加载车辆路网
with open(ROAD_PATH, 'r', encoding='utf-8') as f:
    rp_all = json.load(f)
# 精简数据：position, neighbors, junction_id, OtherLanes, 车道类型
rp = []
for p in rp_all:
    jid = p.get("junction_id", 0)
    ol = p.get("OtherLanes", [])
    # 判断车道类型: j=路口, l=左车道(OtherLanes索引比自己大), r=右车道
    if jid > 0:
        t = "j"
    elif len(ol) > 0 and ol[0] > p["listIndex"]:
        t = "l"
    else:
        t = "r"
    rp.append({
        "x": round(p["position"]["x"], 1),
        "z": round(p["position"]["z"], 1),
        "nb": p["neighbors"],
        "t": t
    })
print(f"Vehicle: {len(rp)} waypoints")

# 统计边数
edges = sum(len(p["nb"]) for p in rp) // 2
print(f"  Edges: {edges}")

# 加载行人路网
with open(PED_PATH, 'r', encoding='utf-8') as f:
    ped_data = json.load(f)
pl = ped_data['lists'][0]
pn = [{"id":p["id"],"x":round(p["position"][0],1),"z":round(p["position"][2],1)} for p in pl['points']]
pe = []
for e in pl['edges']:
    for t in e["to"]:
        if t["id"] > e["from"]:
            pe.append([e["from"], t["id"]])
print(f"Ped: {len(pn)} nodes, {len(pe)} edges")

# 加载小地图（缩小后 base64 嵌入）
from PIL import Image
import io
img = Image.open(MAP_IMG)
# 缩小到 1024 以减少 HTML 大小
img_small = img.resize((1024, 1024), Image.LANCZOS)
buf = io.BytesIO()
img_small.save(buf, format='PNG', optimize=True)
map_b64 = base64.b64encode(buf.getvalue()).decode()
print(f"Map image: {len(map_b64)//1024}KB base64")

# 计算图片像素到世界坐标的参数（用于 JS）
actual_w = img.size[0]
pixel_scale = MAP_SCALE * LOGICAL_SIZE / actual_w
# 缩小后的 pixel_scale
small_pixel_scale = MAP_SCALE * LOGICAL_SIZE / 1024

rj = json.dumps(rp, separators=(',',':'))
pnj = json.dumps(pn, separators=(',',':'))
pej = json.dumps(pe, separators=(',',':'))

html = '<!DOCTYPE html>\n<html><head><meta charset="UTF-8"><title>S1Town Roads</title>\n'
html += '<style>\n'
html += '*{margin:0;padding:0}body{background:#1a1a2e;overflow:hidden}\n'
html += 'canvas{display:block;cursor:grab}\n'
html += '#ui{position:fixed;top:10px;left:10px;background:rgba(0,0,0,.85);color:#eee;padding:12px;'
html += 'border-radius:8px;font:12px sans-serif;border:1px solid #444;min-width:220px;z-index:5}\n'
html += '#ui h3{color:#4fc3f7;margin-bottom:6px}\n'
html += 'label{display:block;margin:3px 0;cursor:pointer}\n'
html += 'hr{border-color:#333;margin:6px 0}\n'
html += '.lg{display:flex;align-items:center;gap:6px;font-size:11px;margin:2px 0}\n'
html += '.lb{width:18px;height:5px;border-radius:2px;display:inline-block}\n'
html += '.ld{width:8px;height:8px;border-radius:50%;display:inline-block}\n'
html += '#st{position:fixed;bottom:8px;left:8px;color:#888;font:11px sans-serif;'
html += 'background:rgba(0,0,0,.7);padding:4px 8px;border-radius:4px}\n'
html += '</style></head><body>\n'
html += '<canvas id="cv"></canvas>\n'
html += '<div id="ui">\n'
html += '<h3>S1Town Road Network</h3>\n'
html += f'<label><input type="checkbox" id="cM" checked> Map background</label>\n'
html += f'<label><input type="checkbox" id="cV" checked> Vehicle roads ({len(rp)} pts)</label>\n'
html += f'<label><input type="checkbox" id="cP" checked> Ped network ({len(pn)} pts)</label>\n'
html += f'<label><input type="checkbox" id="cN"> Show nodes</label>\n'
html += '<hr>\n'
html += '<div class="lg"><div class="lb" style="background:#ef5350"></div>Left lane</div>\n'
html += '<div class="lg"><div class="lb" style="background:#42a5f5"></div>Right lane</div>\n'
html += '<div class="lg"><div class="ld" style="background:#ffeb3b"></div>Junction</div>\n'
html += '<div class="lg"><div class="lb" style="background:#ab47bc"></div>Ped path</div>\n'
html += '<div class="lg"><div class="ld" style="background:#ce93d8"></div>Ped waypoint</div>\n'
html += '<div style="margin-top:8px;color:#666;font-size:10px">Scroll=zoom Drag=pan F=fit R=reset</div>\n'
html += '</div>\n<div id="st"></div>\n'

html += '<script>\n'
html += f'var VP={rj};\n'
html += f'var PN={pnj};\n'
html += f'var PE={pej};\n'
html += f'var MAP_OX={OFFSET_X},MAP_OZ={OFFSET_Z},MAP_PS={small_pixel_scale};\n'

js = r"""
var PM={};PN.forEach(function(n,i){PM[n.id]=i;});
var cv=document.getElementById('cv'),c=cv.getContext('2d');
var W,H,cx=50,cz=-50,sc=2.5,dr=false,lx=0,ly=0;
var mapImg=new Image();
mapImg.src='data:image/png;base64,""" + map_b64 + r"""';
mapImg.onload=function(){draw();};

function ts(x,z){return[W/2+(x-cx)*sc,H/2-(z-cz)*sc];}
function tw(sx,sy){return[(sx-W/2)/sc+cx,-(sy-H/2)/sc+cz];}
function $(id){return document.getElementById(id).checked;}

function fit(){
  var a=1e9,b=-1e9,c2=1e9,d=-1e9;
  VP.forEach(function(p){if(p.x<a)a=p.x;if(p.x>b)b=p.x;if(p.z<c2)c2=p.z;if(p.z>d)d=p.z;});
  PN.forEach(function(n){if(n.x<a)a=n.x;if(n.x>b)b=n.x;if(n.z<c2)c2=n.z;if(n.z>d)d=n.z;});
  cx=(a+b)/2;cz=(c2+d)/2;
  sc=Math.min((W-80)/(b-a||1),(H-80)/(d-c2||1));
  draw();
}

function draw(){
  var dp=devicePixelRatio||1;
  c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,cv.width,cv.height);
  c.setTransform(dp,0,0,dp,0,0);

  // map background
  if($('cM')&&mapImg.complete){
    // img(0,0)=world(MAP_OX, MAP_OZ) -> screen right-bottom
    // img(1024,1024)=world(MAP_OX-1024*MAP_PS, MAP_OZ+1024*MAP_PS) -> screen left-top
    // 屏幕上：左=小X，右=大X，上=大Z，下=小Z
    var sRightBottom=ts(MAP_OX, MAP_OZ);           // img(0,0)
    var sLeftTop=ts(MAP_OX-1024*MAP_PS, MAP_OZ+1024*MAP_PS); // img(1024,1024)
    var dstX=sLeftTop[0], dstY=sLeftTop[1];
    var dstW=sRightBottom[0]-sLeftTop[0];
    var dstH=sRightBottom[1]-sLeftTop[1];
    c.globalAlpha=0.5;
    c.save();
    // 图片 X 轴和世界 X 轴反向，Z 轴和屏幕 Y 轴反向，所以需要翻转
    c.translate(dstX+dstW, dstY+dstH);
    c.scale(-dstW/1024, -dstH/1024);
    c.drawImage(mapImg,0,0);
    c.restore();
    c.globalAlpha=1;
  }

  // vehicle roads - edges (colored by lane type)
  if($('cV')){
    var lw=Math.max(1.5,2*Math.min(sc/2,3));
    c.lineCap='round';c.setLineDash([]);
    c.globalAlpha=0.75;
    // draw left lane edges (red)
    VP.forEach(function(p,i){
      if(p.t!=='l')return;
      p.nb.forEach(function(j){
        var a=ts(p.x,p.z),b=ts(VP[j].x,VP[j].z);
        c.strokeStyle='#ef5350';c.lineWidth=lw;
        c.beginPath();c.moveTo(a[0],a[1]);c.lineTo(b[0],b[1]);c.stroke();
      });
    });
    // draw right lane edges (blue)
    VP.forEach(function(p,i){
      if(p.t!=='r')return;
      p.nb.forEach(function(j){
        var a=ts(p.x,p.z),b=ts(VP[j].x,VP[j].z);
        c.strokeStyle='#42a5f5';c.lineWidth=lw;
        c.beginPath();c.moveTo(a[0],a[1]);c.lineTo(b[0],b[1]);c.stroke();
      });
    });
    // draw junction edges (yellow)
    VP.forEach(function(p,i){
      if(p.t!=='j')return;
      p.nb.forEach(function(j){
        var a=ts(p.x,p.z),b=ts(VP[j].x,VP[j].z);
        c.strokeStyle='#ffeb3b';c.lineWidth=lw*0.8;
        c.beginPath();c.moveTo(a[0],a[1]);c.lineTo(b[0],b[1]);c.stroke();
      });
    });
    // nodes
    if($('cN')){
      c.globalAlpha=0.8;
      var r=Math.max(2,3*sc/2.5);
      VP.forEach(function(p){
        var s=ts(p.x,p.z);
        c.fillStyle=p.t==='j'?'#ffeb3b':p.t==='l'?'#ef5350':'#42a5f5';
        c.beginPath();c.arc(s[0],s[1],r,0,6.28);c.fill();
      });
    }
    c.globalAlpha=1;
  }

  // ped network
  if($('cP')){
    c.globalAlpha=0.6;c.strokeStyle='#ab47bc';c.lineWidth=Math.max(1,1.5*Math.min(sc/2,2));
    c.setLineDash([]);
    PE.forEach(function(e){
      var a=PN[PM[e[0]]],b=PN[PM[e[1]]];if(!a||!b)return;
      var s1=ts(a.x,a.z),s2=ts(b.x,b.z);
      c.beginPath();c.moveTo(s1[0],s1[1]);c.lineTo(s2[0],s2[1]);c.stroke();
    });
    if($('cN')){
      c.fillStyle='#ce93d8';c.globalAlpha=0.7;
      PN.forEach(function(n){var s=ts(n.x,n.z);c.beginPath();c.arc(s[0],s[1],2,0,6.28);c.fill();});
    }
    c.globalAlpha=1;
  }

  // axes
  c.strokeStyle='#555';c.lineWidth=1;var ax=W-55,ay=H-35;
  c.beginPath();c.moveTo(ax,ay);c.lineTo(ax+25,ay);c.stroke();
  c.beginPath();c.moveTo(ax,ay);c.lineTo(ax,ay-25);c.stroke();
  c.fillStyle='#e55';c.font='10px sans-serif';c.textAlign='left';c.fillText('X',ax+27,ay+3);
  c.fillStyle='#5e5';c.fillText('Z',ax-3,ay-28);
}

cv.onmousedown=function(e){dr=true;lx=e.clientX;ly=e.clientY;cv.style.cursor='grabbing';};
window.onmouseup=function(){dr=false;cv.style.cursor='grab';};
window.onmousemove=function(e){
  if(dr){cx-=(e.clientX-lx)/sc;cz+=(e.clientY-ly)/sc;lx=e.clientX;ly=e.clientY;draw();}
  var w=tw(e.clientX,e.clientY);
  document.getElementById('st').textContent='X:'+w[0].toFixed(1)+' Z:'+w[1].toFixed(1)+' '+sc.toFixed(1)+'x';
};
cv.onwheel=function(e){
  e.preventDefault();var f=e.deltaY<0?1.15:0.87;
  var w=tw(e.clientX,e.clientY);sc=Math.max(0.1,Math.min(100,sc*f));
  cx=w[0]-(e.clientX-W/2)/sc;cz=w[1]+(e.clientY-H/2)/sc;draw();
};
window.onkeydown=function(e){if(e.key==='f'||e.key==='F')fit();if(e.key==='r'||e.key==='R'){cx=50;cz=-50;sc=2.5;draw();}};
['cM','cV','cP','cN'].forEach(function(id){document.getElementById(id).onchange=draw;});
function resize(){
  var dp=devicePixelRatio||1;W=innerWidth;H=innerHeight;
  cv.width=W*dp;cv.height=H*dp;cv.style.width=W+'px';cv.style.height=H+'px';draw();
}
window.onresize=resize;resize();fit();
"""

html += js + '\n</script></body></html>'

with open(OUTPUT, 'w', encoding='utf-8') as f:
    f.write(html)
print(f"Output: {OUTPUT} ({os.path.getsize(OUTPUT)//1024}KB)")
