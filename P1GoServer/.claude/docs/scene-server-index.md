# Go Scene Server 索引

路径：`servers/scene_server/`

## 目录结构

```
servers/scene_server/
├── cmd/                    # 入口和初始化
├── internal/
│   ├── ecs/                # ECS 框架核心
│   │   ├── com/            # 组件（29个）
│   │   ├── system/         # 系统（25个）
│   │   ├── res/            # 资源管理器（13个）
│   │   ├── entity/         # 实体和工厂
│   │   └── scene/          # 场景管理
│   ├── net_func/           # 网络处理函数（客户端请求）
│   ├── service/            # RPC 服务层
│   ├── backend/            # 后端（与 Logic 通讯）
│   ├── frontend/           # 前端（预留）
│   └── common/             # 公共工具（AI/配置/任务）
└── ECS.md                  # ECS 架构说明
```

## 功能→文件映射

### 小镇核心

| 功能 | 核心路径（省略 `internal/`） | 说明 |
|------|---------------------------|------|
| 交易 | `ecs/res/trade/`、`ecs/system/trade/`、`net_func/town/trade.go` | 订单/面对面/样品三种模式 |
| 经销商 | `ecs/res/dealer/`、`net_func/town/dealer.go` | 代替玩家交易 |
| NPC联系人 | `ecs/res/town_contact/`、`net_func/town/contact.go` | 好感度/解锁状态 |
| 产品管理 | `ecs/res/town_product/`、`net_func/town/product.go` | 产品定价/上架 |
| 垃圾系统 | `ecs/res/town_garbage/`、`net_func/object/garbage_pick.go` | 垃圾刷新/拾取 |
| 小镇管理 | `ecs/res/town/`、`ecs/system/town/` | 等级/ATM/经验/每日重置 |
| 时间系统 | `ecs/res/time_mgr/`、`ecs/system/town_time_update/` | 时间流逝/跨天/睡眠 |
| 容器/道具 | `net_func/town/container.go`、`net_func/town/inventory.go` | 物品操作 |
| 任务 | `ecs/com/cquest/`、`ecs/system/task/`、`net_func/town/task.go` | 小镇任务 |
| 商店 | `ecs/com/cshop/`、`ecs/system/shop/`、`net_func/town/shop.go` | 商品/刷新 |
| 家具 | `ecs/com/cfurniture/`、`net_func/town/furniture.go` | 小镇装饰 |

### 物体与交互

| 功能 | 核心路径 | 说明 |
|------|---------|------|
| 物体功能 | `ecs/com/cobject/` | 8种功能：种植/混合/拾取/架子/持有/睡眠/水龙头/背包 |
| 物体交互 | `ecs/com/cinteraction/`、`net_func/object/interact.go` | 交互点/锁定机制 |
| 种植 | `ecs/com/cobject/obj_func_plant.go`、`net_func/object/town_planting.go` | 土壤/种子/浇水/生长 |
| 混合台 | `ecs/com/cobject/obj_mix.go`、`net_func/object/town_mix.go` | 3格混合/计时 |
| 存储架 | `ecs/com/cobject/obj_func_rack.go`、`net_func/object/town_storageRack.go` | 物品存放 |
| 打包 | `net_func/object/town_packaging.go` | 产品打包 |

### 玩家系统

| 功能 | 核心路径 | 说明 |
|------|---------|------|
| 玩家基础 | `ecs/com/cplayer/player_base.go` | 角色信息/传送缓存 |
| 背包 | `ecs/com/cbackpack/` | 主背包/衣服/装备三容器 |
| 载具 | `ecs/com/cplayer/player_vehicle.go` | 载具列表/部件/损坏 |
| 统计 | `ecs/com/cplayer/statistics.go` | 财富/等级/收集/成就 |
| 通缉 | `ecs/com/cplayer/being_wanted.go`、`ecs/system/police/` | 被通缉状态机 |
| 进出场景 | `net_func/player/enter.go`、`net_func/player/teleport.go` | 进入/传送/重生 |
| 红点 | `ecs/system/reddot/`、`net_func/player/reddot.go` | 红点通知 |

### AI/NPC

| 功能 | 核心路径 | 说明 |
|------|---------|------|
| AI决策 | `common/ai/decision/`、`ecs/system/decision/` | GSS/NDU/GOAP 三种决策脑 |
| 行为树 | `common/ai/bt/`、`ecs/system/ai_bt/` | 细粒度行为执行 |
| NPC组件 | `ecs/com/cnpc/` | 基础/小镇/樱花/日程/移动/交易代理 |
| NPC更新 | `ecs/system/npc/` | 日程驱动/移动系统 |
| 值系统 | `common/ai/value/` | NPC动态属性（int/float/bool/vector） |
| 传感器 | `common/ai/decision/gss_brain/sensor/` | 感知外部事件 |

### 场景基础

| 功能 | 核心路径 | 说明 |
|------|---------|------|
| 场景管理 | `ecs/scene/scene_mgr.go` | 场景创建/销毁/查找 |
| AOI | `ecs/system/aoi/`、`ecs/com/cvision/` | 视野管理（O(n^2)广播） |
| 保存 | `ecs/system/scene_save/`、`ecs/system/role_info_save/` | 场景/角色持久化 |
| 场景停止 | `ecs/system/scene_stop/` | 无玩家10秒后停止 |
| 导航 | `ecs/res/navmesh/`、`ecs/res/road_network/` | 寻路 |
| 生成点 | `ecs/res/spawn_point/` | NPC/物体生成位置 |

### 樱花校园

| 功能 | 核心路径 | 说明 |
|------|---------|------|
| 樱花系统 | `ecs/com/csakura/`、`ecs/system/sakura/`、`ecs/res/sakura/` | 樱花场景特有 |
| 衣服/放置/工坊 | `net_func/sakura/` | 樱花场景玩法 |

### 其他

| 功能 | 核心路径 | 说明 |
|------|---------|------|
| GM命令 | `net_func/gm/` | 调试命令（时间/小镇） |
| UI | `ecs/com/cui/`、`net_func/ui/` | 轮盘/表情/重生/关系 |
| 物理 | `ecs/com/cphysics/` | 物理组件 |
| 可移动门 | `ecs/com/cmovabledoor/`、`ecs/system/movable_door/` | 门控制 |
| GAS能力 | `ecs/com/cgas/` | 能力系统 |
| 社交 | `ecs/com/csocial/` | 社交组件 |

## ECS 框架要点

| 层 | 位置 | 说明 |
|---|------|------|
| Entity | `ecs/entity/` | 实体 = ID + 组件列表，工厂创建 |
| Component | `ecs/com/` | 纯数据，通过 ComponentMap O(1) 查找 |
| System | `ecs/system/` | 逻辑处理，33ms tick，按 SystemType 顺序执行 |
| Resource | `ecs/res/` | 场景级全局组件（管理器），生命周期与场景同步 |

## 开发规则

- 新组件 → `ecs/com/c<name>/`，实现 `Component` 接口
- 新系统 → `ecs/system/<name>/`，实现 `System` 接口
- 新资源 → `ecs/res/<name>/`，实现 `Resource` 接口
- 新请求处理 → `net_func/<domain>/<handler>.go`
- 数据同步 → 修改后调用 `SetSync()`（客户端）或 `SetSave()`（数据库）
- NetUpdate 系统最后执行，确保所有脏标记已就绪

## 自动生成文件（勿手动编辑）

- `internal/service/scene_service.go` - 外部RPC路由
- `internal/net_func/server_func.go` - 场景消息分发
- `internal/net_func/server_intrnal_func.go` - 内部消息分发

## 关联知识库

- ECS框架详解 → `.claude/docs/go-knowledge.md`
- 网络层详解 → `.claude/docs/go-knowledge.md`
- AI系统详解 → `.claude/docs/go-knowledge.md`
- 物体功能系统 → `.claude/docs/go-knowledge.md`
- 交易系统 → `.claude/docs/小镇交易系统.md`
- 道具系统 → `.claude/docs/小镇道具系统.md`
