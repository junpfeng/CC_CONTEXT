# 反外挂检测与标记封号系统 — 技术设计

## 1. 需求回顾

基于对"凌宇插件 v1.0"外挂的逆向分析，实现服务端检测 + 标记 + 人工审核封号流程。

**本期范围（P0）：**
- 移动合理性检测（速度超标、瞬移、飞天）
- 射击频率校验（射速超过武器配置上限）
- 异常标记上报（Rust → Redis → Go GM 审核）

**不在本期范围：**
- 行为统计分析（命中率/爆头率）→ P1
- 视野裁剪（AOI 遮挡剔除）→ P2
- 自动封号 → 需人工审核数据校准后再启用

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────┐
│              Rust Scene Server                   │
│                                                  │
│  ActionReq ──→ person_move() ──→ MoveValidator   │
│  ShotData  ──→ handle_shot()──→ FireRateChecker  │
│                                                  │
│  MoveValidator ──┐                               │
│  FireRateChecker─┤──→ CheatReporter ──→ Redis    │
│                  │    (异常累积+上报)              │
└──────────────────┼───────────────────────────────┘
                   │ Redis Key: cheat:report:{account_id}
                   ▼
┌─────────────────────────────────────────────────┐
│              Go GM Server                        │
│                                                  │
│  定时扫描 Redis ──→ 写入 MongoDB ──→ GM 后台展示  │
│  GM 审核 ──→ BanUser() ──→ 踢下线 + 封号         │
└─────────────────────────────────────────────────┘
```

---

## 3. Rust 侧详细设计

### 3.1 新增模块：`anti_cheat/`

在 `servers/scene/src/` 下新增 `anti_cheat/` 模块：

```
servers/scene/src/anti_cheat/
├── mod.rs              // 模块入口
├── move_validator.rs   // 移动合理性检测
├── fire_rate_checker.rs // 射击频率校验
├── cheat_reporter.rs   // 异常累积与 Redis 上报
└── types.rs            // 共享类型定义
```

### 3.2 类型定义 (`types.rs`)

```rust
use mecs::storage::Entity;
use mtime::DateTime;

/// 异常类型枚举
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CheatType {
    SpeedHack,      // 移动速度超标
    Teleport,       // 瞬移
    FlyHack,        // 飞天（持续高空无载具）
    FireRateHack,   // 射速超标
}

/// 单次异常记录
#[derive(Debug, Clone)]
pub struct CheatViolation {
    pub cheat_type: CheatType,
    pub entity: Entity,
    pub account_id: u64,
    pub timestamp: i64,         // 毫秒时间戳
    pub detail: String,         // 可读描述（如 "speed=45.2 max=12.0"）
    pub value: f64,             // 实际值
    pub threshold: f64,         // 阈值
}
```

### 3.3 移动合理性检测 (`move_validator.rs`)

**设计思路：** 在 `person_move()` 中增加校验，记录上一帧位置和时间戳，计算瞬时速度。

#### 新增 ECS Component：`MoveValidateComp`

```rust
use math::Vec3;

/// 移动校验组件，附加到每个玩家 Entity
pub struct MoveValidateComp {
    pub last_position: Vec3,        // 上一次合法位置
    pub last_timestamp_ms: i64,     // 上一次更新时间（毫秒）
    pub airborne_start_ms: i64,     // 持续滞空起始时间（0=不在空中）
    pub speed_violation_count: u32, // 速度异常累积计数
    pub teleport_count: u32,        // 瞬移异常累积计数
    pub fly_violation_count: u32,   // 飞天异常累积计数
}
```

#### 校验逻辑

在 `person_move()` 内，位置更新**之前**插入校验：

```rust
pub fn validate_move(
    cell: &CellWorld,
    entity: Entity,
    new_position: &Vec3,
    current_transform: &Transform,
    validate_comp: &mut MoveValidateComp,
) -> bool {
    let now_ms = DateTime::local_now_stamp_ms() as i64;
    let dt_ms = now_ms - validate_comp.last_timestamp_ms;

    // 防止除零（首帧或时间回拨）
    if dt_ms <= 0 {
        validate_comp.last_timestamp_ms = now_ms;
        validate_comp.last_position = current_transform.location;
        return true;
    }

    let old_pos = validate_comp.last_position;
    let dx = new_position.x - old_pos.x;
    let dy = new_position.y - old_pos.y;  // 垂直
    let dz = new_position.z - old_pos.z;

    // --- 检测1：瞬移 ---
    let horizontal_dist = (dx * dx + dz * dz).sqrt();
    // 阈值：单次移动超过 TELEPORT_THRESHOLD 米（配置值，默认 50m）
    if horizontal_dist > TELEPORT_THRESHOLD {
        // 记录异常，但不阻止移动（避免误判网络延迟）
        report_violation(cell, entity, CheatType::Teleport, horizontal_dist, TELEPORT_THRESHOLD);
        validate_comp.teleport_count += 1;
    }

    // --- 检测2：速度超标 ---
    let dt_sec = dt_ms as f64 / 1000.0;
    let speed = horizontal_dist as f64 / dt_sec;
    // MAX_SPEED: 配置值（m/s），需包含载具最高速度 + 容差
    if speed > MAX_MOVE_SPEED && dt_ms > MIN_CHECK_INTERVAL_MS {
        report_violation(cell, entity, CheatType::SpeedHack, speed, MAX_MOVE_SPEED);
        validate_comp.speed_violation_count += 1;
    }

    // --- 检测3：飞天 ---
    let ground_height = get_ground_height(cell, new_position);  // 从物理/地形获取地面高度
    let height_above_ground = new_position.y - ground_height;
    if height_above_ground > FLY_HEIGHT_THRESHOLD {
        if validate_comp.airborne_start_ms == 0 {
            validate_comp.airborne_start_ms = now_ms;
        } else if now_ms - validate_comp.airborne_start_ms > FLY_DURATION_THRESHOLD_MS {
            // 在无载具状态下持续滞空超过阈值
            if !is_in_vehicle(cell, entity) && !is_parachuting(cell, entity) {
                report_violation(cell, entity, CheatType::FlyHack,
                    height_above_ground as f64, FLY_HEIGHT_THRESHOLD as f64);
                validate_comp.fly_violation_count += 1;
            }
        }
    } else {
        validate_comp.airborne_start_ms = 0;
    }

    // 更新记录
    validate_comp.last_position = *new_position;
    validate_comp.last_timestamp_ms = now_ms;
    true // 本期只记录不阻止
}
```

#### 配置阈值（需策划/运营校准）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MAX_MOVE_SPEED` | 25.0 m/s | 载具最高速度 + 50% 容差 |
| `TELEPORT_THRESHOLD` | 50.0 m | 单帧水平位移阈值 |
| `FLY_HEIGHT_THRESHOLD` | 10.0 m | 离地高度阈值 |
| `FLY_DURATION_THRESHOLD_MS` | 5000 ms | 持续滞空时间阈值 |
| `MIN_CHECK_INTERVAL_MS` | 50 ms | 速度检测最小时间间隔（避免低 dt 误报） |

### 3.4 射击频率校验 (`fire_rate_checker.rs`)

**设计思路：** 在 `CheckManager` 中扩展，记录每个玩家每把武器的最近射击时间，检测间隔是否低于武器配置的 `fire_interval`。

#### 扩展 `CheckManager`

```rust
/// 在 ShotInfoByUser 中新增字段
pub struct ShotInfoByUser {
    pub entity: Entity,
    pub unique_map: HashMap<i64, ShotInfo>,
    // --- 新增 ---
    pub last_fire_time_ms: HashMap<i32, i64>,  // weapon_id → 上次射击时间(ms)
    pub fire_rate_violation_count: u32,
}
```

#### 校验逻辑

在 `add_shot_info()` 中、注册射击**之前**插入校验：

```rust
pub fn check_fire_rate(
    &mut self,
    entity: Entity,
    weapon_id: i32,
) -> Option<CheatViolation> {
    let now_ms = DateTime::local_now_stamp_ms() as i64;

    let user_info = match self.user_map.get_mut(&entity) {
        Some(info) => info,
        None => return None,  // 首次射击，无需校验
    };

    let last_fire_ms = match user_info.last_fire_time_ms.get(&weapon_id) {
        Some(&t) => t,
        None => {
            user_info.last_fire_time_ms.insert(weapon_id, now_ms);
            return None;  // 该武器首次射击
        }
    };

    let interval_ms = now_ms - last_fire_ms;

    // 从武器配置获取最小射击间隔
    let min_interval_ms = match get_weapon_min_fire_interval(weapon_id) {
        Some(interval) => interval,
        None => return None,  // 配置不存在，跳过校验
    };

    // 容差：允许 80% 的最小间隔（网络抖动补偿）
    let threshold_ms = (min_interval_ms as f64 * FIRE_RATE_TOLERANCE) as i64;

    user_info.last_fire_time_ms.insert(weapon_id, now_ms);

    if interval_ms < threshold_ms && interval_ms > 0 {
        user_info.fire_rate_violation_count += 1;
        return Some(CheatViolation {
            cheat_type: CheatType::FireRateHack,
            entity,
            account_id: 0, // 由调用方填充
            timestamp: now_ms,
            detail: format!("weapon={} interval={}ms min={}ms", weapon_id, interval_ms, min_interval_ms),
            value: interval_ms as f64,
            threshold: threshold_ms as f64,
        });
    }
    None
}
```

#### 配置阈值

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `FIRE_RATE_TOLERANCE` | 0.8 | 容差系数（80% 的配置间隔） |
| `FIRE_RATE_REPORT_THRESHOLD` | 5 | 累积超频次数达到此值才上报 |

### 3.5 异常上报 (`cheat_reporter.rs`)

**设计思路：** 异常累积到阈值后批量写入 Redis，避免频繁 IO。

#### 数据结构

```rust
/// 每个玩家的异常汇总
pub struct PlayerCheatSummary {
    pub account_id: u64,
    pub entity_id: u64,
    pub player_name: String,
    pub violations: Vec<CheatViolation>,
    pub first_violation_time: i64,
    pub last_violation_time: i64,
}

/// Scene 级 Resource
pub struct CheatReporter {
    pending_reports: HashMap<u64, PlayerCheatSummary>,  // account_id → summary
    last_flush_time: i64,
}
```

#### 上报策略

```rust
impl CheatReporter {
    /// 添加异常记录
    pub fn add_violation(&mut self, violation: CheatViolation) {
        let summary = self.pending_reports
            .entry(violation.account_id)
            .or_insert_with(|| PlayerCheatSummary::new(violation.account_id));
        summary.add(violation);
    }

    /// 定期刷新（每 10 秒调用一次，由 ECS System 驱动）
    pub fn flush_to_redis(&mut self, redis_client: &MredisClient) {
        let now = DateTime::local_now_stamp_ms() as i64;
        if now - self.last_flush_time < FLUSH_INTERVAL_MS {
            return;
        }
        self.last_flush_time = now;

        for (account_id, summary) in self.pending_reports.drain() {
            if summary.violations.len() < MIN_VIOLATIONS_TO_REPORT {
                continue;  // 异常次数不够，不上报
            }

            let report = CheatReport {
                account_id,
                player_name: summary.player_name,
                scene_id: 0,  // 由调用方填充
                violations: summary.violations.iter().map(|v| ViolationEntry {
                    cheat_type: format!("{:?}", v.cheat_type),
                    detail: v.detail.clone(),
                    value: v.value,
                    threshold: v.threshold,
                    timestamp: v.timestamp,
                }).collect(),
                first_time: summary.first_violation_time,
                last_time: summary.last_violation_time,
                total_count: summary.violations.len() as u32,
            };

            // Redis Key: cheat:reports (List, LPUSH)
            // Value: JSON 序列化的 CheatReport
            let json = serde_json::to_string(&report).unwrap_or_default();
            redis_client.lpush("cheat:reports", &json);

            // 同时设置玩家标记（用于快速查询）
            // Key: cheat:player:{account_id}, Value: 最新报告时间, TTL: 7 天
            let key = format!("cheat:player:{}", account_id);
            redis_client.set_ex(&key, &now.to_string(), 7 * 24 * 3600);
        }
    }
}
```

#### Redis 数据格式

**List Key：** `cheat:reports`

```json
{
  "account_id": 123456,
  "player_name": "Player1",
  "scene_id": 1001,
  "violations": [
    {
      "cheat_type": "SpeedHack",
      "detail": "speed=45.2 max=25.0",
      "value": 45.2,
      "threshold": 25.0,
      "timestamp": 1709000000000
    },
    {
      "cheat_type": "Teleport",
      "detail": "dist=120.5 max=50.0",
      "value": 120.5,
      "threshold": 50.0,
      "timestamp": 1709000001000
    }
  ],
  "first_time": 1709000000000,
  "last_time": 1709000001000,
  "total_count": 2
}
```

**标记 Key：** `cheat:player:{account_id}` → TTL 7 天

### 3.6 接入点修改

#### 3.6.1 `person_status.rs` — 移动校验接入

在 `person_move()` 函数中，位置更新之前插入校验调用：

```rust
// person_status.rs:415-420 之间插入
if !person_status.is_drive && person_interact.check_move() {
    if let Some(pos) = position {
        let new_pos: Vec3 = pos.into();

        // === 新增：移动校验 ===
        if let Ok(mut validate_comp) = cell.get_mut::<MoveValidateComp>(entity) {
            validate_move(cell, entity, &new_pos, &transform, &mut validate_comp);
        }
        // === 校验结束 ===

        if transform.location.distance_squared(new_pos) >= 0.0001 {
            transform.location = pos.into();
        }
    }
    // ... rotation 部分不变
}
```

#### 3.6.2 `damage/shot.rs` — 射速校验接入

在 `handle_shot_data()` 的 `check_manager.add_shot_info()` 之前插入：

```rust
// shot.rs:37-43 之间插入
Some(mut check_manager) => {
    // === 新增：射速校验 ===
    if let Some(violation) = check_manager.check_fire_rate(shooter_entity, weapon_id) {
        if let Ok(player_comp) = world.get::<PlayerComp>(shooter_entity) {
            let mut filled = violation;
            filled.account_id = player_comp.account_id;
            if let Some(mut reporter) = world.get_resource_mut::<CheatReporter>() {
                reporter.add_violation(filled);
            }
        }
    }
    // === 校验结束 ===

    check_manager.add_shot_info(shooter_entity, weapon_id, unique);
}
```

### 3.7 ECS System：定期刷新上报

新增 System，每帧检查是否需要 flush：

```rust
// anti_cheat/mod.rs
pub fn flush_cheat_reports(world: &CellWorld) {
    let mut reporter = match world.get_resource_mut::<CheatReporter>() {
        Some(r) => r,
        None => return,
    };
    let redis = match get_db_manager() {
        Some(db) => db.get_redis_client(),
        None => return,
    };
    reporter.flush_to_redis(&redis);
}
```

在 Scene tick 循环中注册此 System（低频调用，每 10 秒实际执行一次，内部有时间门控）。

---

## 4. Go 侧详细设计

### 4.1 GM Server 扩展：异常报告查询与封号

#### 新增 GM 接口

| 接口 | 方法 | 功能 |
|------|------|------|
| `/api/cheat/list` | GET | 分页查询待审核的异常报告 |
| `/api/cheat/detail/{account_id}` | GET | 查看某玩家的详细异常记录 |
| `/api/cheat/ban` | POST | 审核通过，执行封号 |
| `/api/cheat/dismiss` | POST | 审核不通过，dismiss 记录 |

#### 定时任务：Redis → MongoDB 同步

```go
// 每 30 秒从 Redis 拉取新报告存入 MongoDB
func (h *GmHandler) SyncCheatReports() {
    for {
        // RPOP from Redis list "cheat:reports"
        data, err := h.redis.RPop("cheat:reports")
        if err != nil || data == "" {
            break
        }
        var report CheatReport
        json.Unmarshal([]byte(data), &report)

        // 写入 MongoDB: cheat_reports 集合
        h.mongo.InsertOne("cheat_reports", report)
    }
}
```

#### MongoDB 集合：`cheat_reports`

```json
{
  "_id": ObjectId,
  "account_id": 123456,
  "player_name": "Player1",
  "scene_id": 1001,
  "violations": [...],
  "first_time": 1709000000000,
  "last_time": 1709000001000,
  "total_count": 2,
  "status": "pending",       // pending / banned / dismissed
  "reviewed_by": "",         // GM 审核人
  "reviewed_at": 0,          // 审核时间
  "ban_duration": 0          // 封禁时长（秒），0=未封禁
}
```

#### 封号流程

```go
func (h *GmHandler) BanCheatPlayer(accountId uint64, duration int64, reason string) error {
    // 1. 复用现有 BanUser 逻辑
    unblockTime := time.Now().Unix() + duration
    if duration == 0 { // 永封
        unblockTime = -1
    }
    h.repo.ModifyAccountBlockState(accountId, unblockTime, reason)

    // 2. 踢下线
    h.kickPlayer(accountId)

    // 3. 更新 cheat_reports 状态
    h.mongo.UpdateOne("cheat_reports",
        bson.M{"account_id": accountId, "status": "pending"},
        bson.M{"$set": bson.M{
            "status": "banned",
            "reviewed_by": gmName,
            "reviewed_at": time.Now().Unix(),
            "ban_duration": duration,
        }})
    return nil
}
```

---

## 5. 事务性设计

### 5.1 数据一致性

| 操作 | 一致性保证 |
|------|-----------|
| Rust 写 Redis | 异步，允许少量丢失（检测数据非关键路径） |
| Redis → MongoDB 同步 | RPOP 保证不重复消费；失败重试 |
| MongoDB 封号 | 与现有 BanUser 共用事务，已验证 |
| 踢下线 | 最终一致（下次心跳/请求时生效） |

### 5.2 容错

| 故障场景 | 处理 |
|---------|------|
| Redis 不可用 | Rust 侧 CheatReporter 丢弃本批报告，下次重新累积 |
| Go 同步任务崩溃 | Redis List 数据不丢失，重启后继续消费 |
| 误判 | 人工审核环节兜底，不自动封号 |

---

## 6. 配置表设计

### 新增配置表：`CfgAntiCheat`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| max_move_speed | f32 | 25.0 | 最大移动速度(m/s)，含载具 |
| teleport_threshold | f32 | 50.0 | 单帧瞬移阈值(m) |
| fly_height_threshold | f32 | 10.0 | 离地高度阈值(m) |
| fly_duration_ms | i64 | 5000 | 持续滞空判定时间(ms) |
| fire_rate_tolerance | f32 | 0.8 | 射速容差系数 |
| min_violations_to_report | u32 | 3 | 最低异常次数才上报 |
| flush_interval_ms | i64 | 10000 | 上报刷新间隔(ms) |
| speed_check_min_dt_ms | i64 | 50 | 速度检测最小时间间隔(ms) |

阈值需要上线后根据正常玩家数据持续调整。初始值设置偏宽松，优先避免误封。

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 阈值过严导致误封 | 正常玩家被标记 | 宽松初始值 + 人工审核 + 不自动封号 |
| 网络延迟导致位置跳变 | 速度/瞬移误报 | MIN_CHECK_INTERVAL_MS 过滤低 dt；TELEPORT_THRESHOLD 设较大值 |
| 载具高速移动误报 | 载车玩家被标记 | MAX_MOVE_SPEED 覆盖载具最高速 + 50% 容差 |
| person_move 每帧调用，性能开销 | 帧率下降 | 校验逻辑 O(1)，仅浮点运算+比较，无分配 |
| Rust 遗留代码修改风险 | 引入 bug | 最小侵入式修改，校验与业务逻辑解耦 |
| 外挂更新绕过 | 检测失效 | 分层检测（P0 速度 + P1 统计），持续迭代 |

---

## 8. 修改文件清单

### Rust (`server_old/`)

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `servers/scene/src/anti_cheat/mod.rs` | **新增** | 模块入口 + flush system |
| `servers/scene/src/anti_cheat/types.rs` | **新增** | 共享类型 |
| `servers/scene/src/anti_cheat/move_validator.rs` | **新增** | 移动校验逻辑 |
| `servers/scene/src/anti_cheat/fire_rate_checker.rs` | **新增** | 射速校验逻辑 |
| `servers/scene/src/anti_cheat/cheat_reporter.rs` | **新增** | Redis 上报 |
| `servers/scene/src/person_status.rs` | **修改** | person_move() 中接入校验 |
| `servers/scene/src/damage/check.rs` | **修改** | CheckManager 新增 fire rate 追踪 |
| `servers/scene/src/damage/shot.rs` | **修改** | handle_shot_data() 中接入射速校验 |
| `servers/scene/src/lib.rs` 或 `main.rs` | **修改** | 注册 anti_cheat 模块和 ECS Resource |
| `servers/scene/src/entity_comp/mod.rs` | **修改** | 注册 MoveValidateComp |

### Go (`P1GoServer/`)

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `servers/gm_server/internal/domain/gm_handler.go` | **修改** | 新增 cheat report 接口 |
| `servers/gm_server/internal/domain/cheat_review.go` | **新增** | 异常报告审核逻辑 |

### 配置

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| 配置表（Rust 侧 TOML 或 xlsx） | **新增** | CfgAntiCheat 阈值配置 |
