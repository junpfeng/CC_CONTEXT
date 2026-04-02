# Donna（旅馆经理）V2 日程示例

> templateId=1014，12 段日程，24 小时闭环

## 一天行程

| 时段 | BehaviorType | 地点 | 路网路点 | 备注 |
|------|-------------|------|---------|------|
| 20:30→9:15 | 6(EnterBuilding) | 旅馆房间 | buildingId=1 | 从地图消失，睡觉 |
| 9:15→9:45 | 1(MoveTo) | 旅馆→街道 | 27→8 | 路网寻路，30 分钟 |
| 9:45→10:40 | 2(Work) | 街边 | — | 可见，站着闲逛 55 分钟 |
| 10:40→11:40 | 1(MoveTo) | 街道→理发店 | 8→36 | 路网寻路，1 小时 |
| 11:40→12:00 | 2(Work) | 理发店门口 | — | 可见，逗留 20 分钟 |
| 12:00→12:40 | 1(MoveTo) | 理发店→旅馆 | 36→27 | 路网寻路，40 分钟 |
| 12:40→16:30 | 6(EnterBuilding) | 旅馆办公室 | buildingId=1 | 从地图消失，办公 |
| 16:30→17:00 | 1(MoveTo) | 旅馆→路边 | 27→40 | 路网寻路，30 分钟 |
| 17:00→18:00 | 2(Work) | 路边 | — | 可见，休息 1 小时 |
| 18:00→19:00 | 1(MoveTo) | 路边→桥 | 40→33 | 路网寻路，1 小时 |
| 19:00→20:00 | 2(Work) | 桥上 | — | 可见，发呆 1 小时 |
| 20:00→20:30 | 1(MoveTo) | 桥→旅馆 | 33→27 | 路网寻路，30 分钟 |

## 统计

| 类型 | 段数 | 总时长 |
|------|------|--------|
| MoveTo（路网移动） | 6 | ~4.5 小时 |
| Work（定点活动，可见） | 4 | ~3.75 小时 |
| EnterBuilding（建筑内，消失） | 2 | ~15.75 小时 |

## V2 JSON 数据

文件：`V2TownNpcSchedule/Donna_Schedule.json`

```json
{
  "templateId": 1014,
  "name": "Donna_Schedule",
  "entries": [
    {"behaviorType":6,"startTime":73800,"endTime":33300,"buildingId":1,"doorId":1,
     "targetPos":{"x":62.353,"y":0.818,"z":-73.878},"probability":1.0,"priority":0},
    {"behaviorType":1,"startTime":33300,"endTime":35100,"startPointId":27,"endPointId":8,
     "targetPos":{"x":119.93,"y":-3.86,"z":-78.47},"probability":1.0,"priority":0},
    {"behaviorType":2,"startTime":35100,"endTime":38400,"duration":3300.0,
     "targetPos":{"x":119.93,"y":-3.86,"z":-78.47},"probability":1.0,"priority":0},
    {"behaviorType":1,"startTime":38400,"endTime":42000,"startPointId":8,"endPointId":36,
     "targetPos":{"x":22.58,"y":0.14,"z":-33.71},"probability":1.0,"priority":0},
    {"behaviorType":2,"startTime":42000,"endTime":43200,"duration":1200.0,
     "targetPos":{"x":22.58,"y":0.14,"z":-33.71},"probability":1.0,"priority":0},
    {"behaviorType":1,"startTime":43200,"endTime":45600,"startPointId":36,"endPointId":27,
     "targetPos":{"x":58.7,"y":0.8,"z":-76.28},"probability":1.0,"priority":0},
    {"behaviorType":6,"startTime":45600,"endTime":59400,"buildingId":1,"doorId":1,
     "targetPos":{"x":62.353,"y":0.818,"z":-73.878},"probability":1.0,"priority":0},
    {"behaviorType":1,"startTime":59400,"endTime":61200,"startPointId":27,"endPointId":40,
     "targetPos":{"x":47.5,"y":0.14,"z":-86.96},"probability":1.0,"priority":0},
    {"behaviorType":2,"startTime":61200,"endTime":64800,"duration":3600.0,
     "targetPos":{"x":47.5,"y":0.14,"z":-86.96},"probability":1.0,"priority":0},
    {"behaviorType":1,"startTime":64800,"endTime":68400,"startPointId":40,"endPointId":33,
     "targetPos":{"x":81.33,"y":-0.11,"z":-63.99},"probability":1.0,"priority":0},
    {"behaviorType":2,"startTime":68400,"endTime":72000,"duration":3600.0,
     "targetPos":{"x":81.33,"y":-0.11,"z":-63.99},"probability":1.0,"priority":0},
    {"behaviorType":1,"startTime":72000,"endTime":73800,"startPointId":33,"endPointId":27,
     "targetPos":{"x":58.7,"y":0.8,"z":-76.28},"probability":1.0,"priority":0}
  ]
}
```
