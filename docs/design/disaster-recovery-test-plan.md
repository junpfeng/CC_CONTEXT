# 服务器容灾测试方案

## 1. 测试目标

验证 P1GoServer 分布式游戏服务器在以下场景下的稳定性和数据安全性：

| 测试维度 | 验证目标 |
|---------|---------|
| 压力测试 | 高并发登录/退出，系统资源使用情况 |
| 内存泄漏 | 长时间运行后内存是否持续增长 |
| 进程容灾 | 服务宕机/重启后数据完整性和服务恢复 |
| 场景切换 | 频繁切换小镇/樱花校园等场景的稳定性 |
| 匹配服务容灾 | 匹配过程中服务宕机后，匹配能否正常恢复 |

---

## 2. 测试环境

### 2.1 服务器进程

```
┌─────────────────────────────────────────────────────────────┐
│  核心服务（必须启动）                                         │
├─────────────────────────────────────────────────────────────┤
│  服务名称            │ 语言   │ 说明                         │
├─────────────────────────────────────────────────────────────┤
│  register_server    │ Rust   │ 服务注册发现中心              │
│  db_server          │ Go     │ 数据持久化层（MongoDB+Redis） │
│  gate_server        │ Rust   │ 客户端网关                   │
│  proxy_server       │ Rust   │ 服务间消息路由               │
│  login_server       │ Rust   │ 登录认证                     │
│  logic_server       │ Rust   │ 核心游戏逻辑                 │
│  scene_server       │ Go     │ 游戏场景实例（ECS）          │
│  manager_server     │ Go     │ 场景调度管理                 │
│  match_server       │ Go     │ 玩家匹配服务                 │
└─────────────────────────────────────────────────────────────┘

注：部分服务同时存在 Go 和 Rust 两个版本，上表标注的是当前实际部署使用的版本。
    如有变更请根据实际情况调整。
```

### 2.2 服务器二进制路径

| 语言版本 | 二进制路径 | 日志路径 |
|---------|-----------|---------|
| Go 服务器 | `bin/` | `bin/log/` |
| Rust 服务器 | `../server_old/target/release/` | `../server_old/bin/log/` |

### 2.3 监控工具

```bash
# 内存监控
watch -n 5 'ps aux | grep -E "(scene_server|logic_server)" | awk "{print \$4, \$6, \$11}"'

# goroutine 监控（通过 pprof）
curl http://localhost:6060/debug/pprof/goroutine?debug=1

# 连接数监控
netstat -an | grep ESTABLISHED | wc -l
```

---

## 3. 测试计划配置

### 3.1 反复登录退出测试 (login_logout_stress.json)

```json
{
    "name": "login_logout_stress",
    "description": "反复登录退出压力测试。登录 -> 进入游戏 -> 等待 -> 退出 -> 重新登录",
    "actions": [
        {"action_type": "wait_action", "params": {"duration_ms": 1000}},
        {"action_type": "logout_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "relogin_action", "params": {}}
    ],
    "loop_count": 0
}
```

### 3.2 场景切换测试 - 小镇 (town_scene_stress.json)

```json
{
    "name": "town_scene_stress",
    "description": "小镇场景压力测试。进入小镇 -> 随机移动 -> 退出 -> 重新进入",
    "actions": [
        {"action_type": "enter_town_action", "params": {"town_teleport_id": 1}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 10000}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}}
    ],
    "loop_count": 0
}
```

### 3.3 场景切换测试 - 樱花校园 (sakura_scene_stress.json)

```json
{
    "name": "sakura_scene_stress",
    "description": "樱花校园场景压力测试。进入樱花校园 -> 随机移动 -> 退出 -> 重新进入",
    "actions": [
        {"action_type": "enter_sakura_action", "params": {"sakura_teleport_id": 2}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 10000}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}}
    ],
    "loop_count": 0
}
```

### 3.4 多场景切换测试 (multi_scene_switch_stress.json)

```json
{
    "name": "multi_scene_switch_stress",
    "description": "多场景频繁切换测试。小镇 -> 樱花校园 -> 副本 -> 小镇（循环）",
    "actions": [
        {"action_type": "enter_town_action", "params": {"town_teleport_id": 1}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "enter_sakura_action", "params": {"sakura_teleport_id": 2}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "start_match_action", "params": {"dungeon_cfg_id": 5, "can_add_other": true}},
        {"action_type": "wait_match_enter_ready_action", "params": {"timeout_ms": 30000}},
        {"action_type": "wait_in_scene_and_exit_action", "params": {"scene_cfg_id": 5}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}}
    ],
    "loop_count": 0
}
```

### 3.5 匹配服务压力测试 (match_stress.json)

```json
{
    "name": "match_stress",
    "description": "匹配服务压力测试。发起匹配 -> 等待匹配完成 -> 进入副本场景 -> 退出 -> 重新匹配",
    "actions": [
        {"action_type": "start_match_action", "params": {"dungeon_cfg_id": 5, "can_add_other": true}},
        {"action_type": "wait_match_enter_ready_action", "params": {"timeout_ms": 60000}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}}
    ],
    "loop_count": 0
}
```

### 3.6 匹配过程断线测试 (match_disconnect_stress.json)

```json
{
    "name": "match_disconnect_stress",
    "description": "匹配过程中断线测试。发起匹配 -> 等待中强制断线 -> 重连 -> 验证匹配状态",
    "actions": [
        {"action_type": "start_match_action", "params": {"dungeon_cfg_id": 5, "can_add_other": true}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "force_disconnect_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "reconnect_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "stop_match_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}}
    ],
    "loop_count": 0
}
```

### 3.7 综合容灾测试 (disaster_recovery_stress.json)

```json
{
    "name": "disaster_recovery_stress",
    "description": "综合容灾测试。登录 -> 进入小镇 -> 执行各种操作 -> 模拟异常断线重连",
    "actions": [
        {"action_type": "enter_town_action", "params": {"town_teleport_id": 1}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "gm_action", "params": {"gm_text": "/ke* gm add_money 1 10000.00"}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 5000}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "force_disconnect_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "reconnect_action", "params": {}},
        {"action_type": "verify_data_action", "params": {}}
    ],
    "loop_count": 0
}
```

---

## 4. 需要新增的动作类型

当前机器人框架缺少以下动作，需要实现：

### 4.1 动作实现清单

| 动作类型 | 功能 | 优先级 | 依赖的 RPC |
|---------|------|--------|-----------|
| `logout_action` | 退出登录 | P0 | `Gateway.Logout` |
| `relogin_action` | 重新登录（复用账号） | P0 | `GuestLogin` + `Gateway.Auth` |
| `enter_town_action` | 进入小镇场景 | P0 | `Logic.StartEnterCity` |
| `enter_sakura_action` | 进入樱花校园 | P0 | `Logic.EnterSakura` |
| `exit_scene_action` | 退出当前场景 | P0 | `Logic.ExitScene` |
| `random_move_action` | 在场景内随机移动 | P1 | `Scene.Move` |
| `force_disconnect_action` | 强制断开连接 | P1 | 直接关闭 TCP |
| `reconnect_action` | 断线重连 | P1 | `GuestLogin` + 恢复会话 |
| `verify_data_action` | 验证数据一致性 | P1 | 对比本地缓存和服务器数据 |
| `teleport_action` | 传送到指定位置 | P2 | `Scene.Teleport` |
| `start_match_action` | 发起副本匹配 | P0 | `Logic.StartMatch` |
| `stop_match_action` | 取消/停止匹配 | P1 | `Logic.StopMatch` |
| `wait_match_enter_ready_action` | 等待匹配完成进入准备阶段 | P0 | 监听 `MatchStateNtf` |

### 4.2 实现示例 - logout_action

```go
// test/robot_game/action.go 中添加

type LogoutAction struct {
    ActionBase
}

func (a *LogoutAction) Execute(owner_robot *Robot) uint8 {
    client := owner_robot.getGatewayClient()
    if client == nil {
        log.Error("LogoutAction: gateway client is nil")
        return ActionResult_Failure
    }

    _, err := client.Logout(&proto.LogoutReq{})
    if err != nil {
        log.Errorf("LogoutAction: logout failed, err=%v", err)
        return ActionResult_Failure
    }

    // 关闭连接
    owner_robot.session.Close()
    owner_robot.session = nil

    log.Infof("LogoutAction: robot %d logout success", owner_robot.account_id)
    return ActionResult_Succ
}
```

### 4.3 实现示例 - enter_town_action

```go
type EnterTownAction struct {
    ActionBase
    TownTeleportId int32
    entered        bool
}

func (a *EnterTownAction) Execute(owner_robot *Robot) uint8 {
    if a.entered {
        // 等待场景初始化完成
        if owner_robot.is_init_scene {
            return ActionResult_Succ
        }
        return ActionResult_Wait
    }

    client := owner_robot.getLogicClient()
    if client == nil {
        return ActionResult_Failure
    }

    _, err := client.StartEnterCity(&proto.StartEnterCityReq{
        TeleportId: a.TownTeleportId,
    })
    if err != nil {
        log.Errorf("EnterTownAction: enter town failed, err=%v", err)
        return ActionResult_Failure
    }

    a.entered = true
    owner_robot.is_init_scene = false
    return ActionResult_Wait
}

func (a *EnterTownAction) Reset() {
    a.entered = false
}
```

---

## 5. 测试执行流程

### 5.1 阶段一：基础压测（内存泄漏检测）

**目标**：验证长时间运行下内存是否稳定

```bash
# 1. 启动所有服务器
./start_all_servers.sh

# 2. 记录初始内存
ps aux | grep scene_server | awk '{print $6}' > memory_baseline.txt

# 3. 启动机器人（100个，反复登录退出）
./bin/robot_game -config config.toml -plan login_logout_stress -num 100

# 4. 每 5 分钟记录内存
while true; do
    echo "$(date): $(ps aux | grep scene_server | awk '{print $6}')" >> memory_log.txt
    sleep 300
done

# 5. 运行 2 小时后分析内存增长趋势
```

**预期结果**：
- 内存在初始增长后应趋于稳定
- 不应出现持续增长的趋势
- goroutine 数量应稳定

### 5.2 阶段二：场景切换压测

**目标**：验证频繁场景切换的稳定性

```bash
# 1. 启动机器人（50个小镇，50个樱花校园）
./bin/robot_game -config config.toml -plan town_scene_stress -num 50 &
./bin/robot_game -config config.toml -plan sakura_scene_stress -num 50 &

# 2. 监控场景创建/销毁日志
tail -f bin/log/scene_server.log | grep -E "(NewScene|Scene.Stop)"

# 3. 运行 1 小时
```

**预期结果**：
- 场景正常创建和销毁
- 无死锁或卡死现象
- 玩家数据正确保存

### 5.3 阶段三：进程杀死重启测试

**目标**：验证服务宕机后数据完整性和恢复能力

#### 测试场景 A：杀死 scene_server (Go)

```bash
# 1. 确保有玩家在场景中活动
./bin/robot_game -config config.toml -plan town_scene_stress -num 20

# 2. 等待 30 秒让玩家执行一些操作

# 3. 记录当前玩家数据（通过 GM 命令或数据库查询）

# 4. 强制杀死 scene_server (Go 版本)
pkill -9 scene_server

# 5. 观察其他服务的日志反应（logic_server 是 Rust 版本）
tail -f ../server_old/bin/log/logic_server.log | grep -E "(disconnect|reconnect|error)"

# 6. 重启 scene_server (Go 版本)
./bin/scene_server -config config/scene.toml &

# 7. 等待机器人自动重连（或手动重启机器人）

# 8. 验证玩家数据是否恢复正确
```

**验证点**：
- [ ] 其他服务检测到 scene_server 离线
- [ ] scene_server 重启后正确注册到 register_server
- [ ] 玩家重新进入场景后数据与崩溃前一致
- [ ] 无数据丢失（最多丢失最后 60 秒未保存的数据）

#### 测试场景 B：杀死 db_server (Go)

```bash
# 1. 有玩家在活动状态
./bin/robot_game -config config.toml -plan town_scene_stress -num 20

# 2. 强制杀死 db_server (Go 版本)
pkill -9 db_server

# 3. 观察 scene_server 保存数据时的错误处理
tail -f bin/log/scene_server.log | grep -E "(Save|error|failed)"

# 4. 5 分钟后重启 db_server (Go 版本)
./bin/db_server -config config/db.toml &

# 5. 验证数据保存恢复正常
```

**验证点**：
- [ ] scene_server 保存失败时有正确的错误日志
- [ ] db_server 重启后数据保存恢复正常
- [ ] 无数据损坏

#### 测试场景 C：杀死 logic_server (Rust)

```bash
# 1. 有玩家在活动状态
./bin/robot_game -config config.toml -plan town_scene_stress -num 20

# 2. 强制杀死 logic_server (Rust 版本)
pkill -9 logic

# 3. 观察客户端和其他服务的反应
tail -f ../server_old/bin/log/gateway.log | grep -E "(disconnect|error)"

# 4. 重启 logic_server (Rust 版本)
cd ../server_old && ./target/release/logic -c config/logic.toml &

# 5. 验证玩家登录/操作是否恢复正常
```

**验证点**：
- [ ] 玩家被踢下线或操作失败
- [ ] logic_server 重启后正确注册
- [ ] 玩家能正常重新登录

#### 测试场景 D：杀死 match_server (Go)（匹配过程中）

**背景说明**：
匹配服务器的状态是纯内存的（不持久化），包括：
- 房间状态：`InitState` → `MatchingState` → `ReadyState` → `FinishState` → `DoneState`
- 玩家组信息、阵营信息
- 匹配中的等待场景和目标场景信息

如果 match_server 在匹配过程中崩溃，所有内存中的匹配状态都会丢失。

```bash
# 1. 启动多个机器人发起匹配
./bin/robot_game -config config.toml -plan match_stress -num 50

# 2. 等待 10 秒，确保有正在进行的匹配
sleep 10

# 3. 观察匹配状态日志
tail -f bin/log/match_server.log | grep -E "(AddMatchGroup|RoomState|MatchingState)"

# 4. 在匹配进行中，强制杀死 match_server
pkill -9 match_server

# 5. 观察 logic_server (Rust) 的反应
tail -f ../server_old/bin/log/logic.log | grep -E "(match|disconnect|error)"

# 6. 等待 5 秒后重启 match_server
sleep 5
./bin/match_server -config config/match.toml &

# 7. 观察机器人的行为（预期：匹配失败后客户端需重新发起匹配）
```

**验证点**：
- [ ] match_server 崩溃后，logic_server 能检测到连接断开
- [ ] logic_server 通知客户端匹配失败/取消
- [ ] match_server 重启后正确注册到 register_server
- [ ] 客户端能正常重新发起匹配请求
- [ ] 无匹配状态残留导致的异常（如玩家无法再次匹配）

**预期行为**：

| 阶段 | 匹配服务器重启前 | 匹配服务器重启后 |
|------|----------------|----------------|
| MatchingState（匹配中） | 匹配丢失，客户端收到取消通知 | 客户端可重新发起匹配 |
| ReadyState（准备中） | 准备状态丢失 | 客户端可重新发起匹配 |
| FinishState（完成中） | 场景创建可能失败 | 需要验证场景状态 |

#### 测试场景 E：杀死 match_server (Go)（不同匹配阶段）

针对匹配状态机的不同阶段分别测试：

**E1. MatchingState 阶段崩溃**

```bash
# 配置较长的匹配时间，确保在 MatchingState 阶段杀死
# 需要少于最小人数的机器人，让匹配一直处于等待状态

# 启动少量机器人（不足以满足最小人数要求）
./bin/robot_game -config config.toml -plan match_stress -num 2

# 观察到进入 MatchingState 后杀死
pkill -9 match_server

# 验证点：玩家是否收到匹配取消通知
```

**E2. ReadyState 阶段崩溃**

```bash
# 需要足够的机器人触发匹配成功进入 ReadyState
./bin/robot_game -config config.toml -plan match_stress -num 10

# 观察日志，等待进入 ReadyState
tail -f bin/log/match_server.log | grep "ReadyState"

# 看到 ReadyState 后立即杀死
pkill -9 match_server

# 验证点：
# - 已进入准备场景的玩家状态
# - 准备场景是否会被正确清理
```

**E3. FinishState 阶段崩溃**

```bash
# 需要所有玩家都准备完成，进入 FinishState
# 使用自动准备的测试计划

# 观察日志，等待进入 FinishState
tail -f bin/log/match_server.log | grep "FinishState"

# 看到 FinishState 后杀死
pkill -9 match_server

# 验证点：
# - 目标场景是否已创建
# - 如果场景已创建，玩家能否正常进入
# - 如果场景未创建，玩家是否能重新匹配
```

### 5.4 阶段四：综合容灾测试

**目标**：模拟真实生产环境的异常场景

```bash
# 1. 启动 200 个机器人执行综合测试
./bin/robot_game -config config.toml -plan disaster_recovery_stress -num 200

# 2. 随机杀死 Go 服务（每 10 分钟一次）
# 注意：只随机杀死 Go 服务，避免影响 Rust 核心服务
while true; do
    # Go 服务列表：scene_server, db_server, manager_server, match_server
    SERVICE=$(shuf -e scene_server db_server manager_server match_server -n 1)
    echo "$(date): Killing $SERVICE (Go)"
    pkill -9 $SERVICE
    sleep 10
    echo "$(date): Restarting $SERVICE (Go)"
    ./bin/$SERVICE -config config/${SERVICE%_server}.toml &
    sleep 600
done

# 3. 持续监控（同时监控 Go 和 Rust 服务）
watch -n 10 '
echo "=== Go Services Memory ===" && ps aux | grep -E "(scene_server|db_server|match_server|manager_server)" | grep -v grep | awk "{print \$11, \$6}"
echo "=== Rust Services Memory ===" && ps aux | grep -E "(logic_server|gateway_server|register_server|proxy_server|login_server)" | grep -v grep | awk "{print \$11, \$6}"
echo "=== Connections ===" && netstat -an | grep 8888 | wc -l
'
```

**服务分类说明**：

| 可随机杀死测试 | 语言 | 说明 |
|---------------|------|------|
| scene_server | Go | 场景服务，重启后玩家需重新进入 |
| db_server | Go | 数据服务，重启后需验证数据完整性 |
| manager_server | Go | 场景管理，重启后场景调度恢复 |
| match_server | Go | 匹配服务，重启后匹配状态丢失 |

| 谨慎测试 | 语言 | 说明 |
|---------|------|------|
| logic_server | Rust | 核心逻辑，重启影响所有玩家 |
| gateway_server | Rust | 网关，重启导致所有连接断开 |
| register_server | Rust | 注册中心，重启影响服务发现 |

---

## 6. 监控指标

### 6.1 需要收集的指标

| 指标 | 采集方式 | 告警阈值 |
|------|---------|---------|
| 内存使用 (RSS) | `ps aux` | 持续增长超过 10%/小时 |
| Goroutine 数量 | pprof | 持续增长超过 100/小时 |
| RPC 延迟 | 日志统计 | P99 > 100ms |
| 场景数量 | 日志统计 | 异常增长 |
| 连接数 | netstat | 超过预期 2 倍 |
| 错误率 | 日志统计 | > 1% |

### 6.2 监控脚本

```bash
#!/bin/bash
# monitor.sh - 容灾测试监控脚本

LOG_DIR="test_logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p $LOG_DIR

# 后台收集内存
while true; do
    echo "$(date +%s),$(ps aux | grep scene_server | grep -v grep | awk '{print $6}')" >> $LOG_DIR/memory_scene.csv
    echo "$(date +%s),$(ps aux | grep logic_server | grep -v grep | awk '{print $6}')" >> $LOG_DIR/memory_logic.csv
    sleep 5
done &
MONITOR_PID=$!

# 后台收集 goroutine（需要 pprof 开启）
while true; do
    curl -s http://localhost:6060/debug/pprof/goroutine?debug=1 | head -1 >> $LOG_DIR/goroutine.log
    sleep 30
done &

# 后台收集错误日志
tail -f bin/log/*.log | grep -iE "(error|panic|fatal)" >> $LOG_DIR/errors.log &

echo "Monitoring started. Logs in $LOG_DIR"
echo "Press Ctrl+C to stop"

trap "kill $MONITOR_PID; echo 'Monitoring stopped'" EXIT
wait
```

---

## 7. 测试报告模板

### 7.1 测试概要

| 项目 | 内容 |
|------|------|
| 测试日期 | YYYY-MM-DD |
| 测试时长 | X 小时 |
| 机器人数量 | X 个 |
| 测试场景 | 登录退出 / 场景切换 / 进程杀死 |

### 7.2 内存分析

| 服务 | 初始内存 | 最终内存 | 增长率 | 结论 |
|------|---------|---------|--------|------|
| scene_server | X MB | X MB | X% | 正常/异常 |
| logic_server | X MB | X MB | X% | 正常/异常 |

### 7.3 进程杀死恢复测试

| 被杀进程 | 影响范围 | 恢复时间 | 数据完整性 | 结论 |
|---------|---------|---------|-----------|------|
| scene_server | 场景内玩家 | X 秒 | 完整/丢失 X 秒 | 通过/失败 |
| db_server | 全部玩家 | X 秒 | 完整/丢失 | 通过/失败 |
| match_server | 匹配中玩家 | X 秒 | 需重新匹配 | 通过/失败 |

### 7.4 发现的问题

| 编号 | 问题描述 | 严重程度 | 复现步骤 | 建议修复方案 |
|------|---------|---------|---------|-------------|
| 1 | ... | 高/中/低 | ... | ... |

---

## 8. 自动化测试脚本

### 8.1 脚本文件列表

位置: `test/robot_game/scripts/`

| 脚本 | 功能 | 用法示例 |
|------|------|---------|
| `config.sh` | 配置文件，定义路径和参数 | 修改此文件适配环境 |
| `start_test.sh` | 启动机器人测试 | `./start_test.sh match_stress 50` |
| `monitor.sh` | 服务器监控 | `./monitor.sh /tmp/output 3600` |
| `kill_and_restart.sh` | 杀死并重启服务 | `./kill_and_restart.sh scene_server` |
| `report.sh` | 生成测试报告 | `./report.sh test_results/xxx` |
| `run_disaster_test.sh` | 主控脚本 | `./run_disaster_test.sh phase1` |

### 8.2 快速开始

```bash
# 进入脚本目录
cd test/robot_game/scripts

# 1. 修改配置（根据实际环境）
vim config.sh

# 2. 快速验证（5分钟，5个机器人）
./run_disaster_test.sh quick

# 3. 执行完整测试
./run_disaster_test.sh phase1 --robots 100 --duration 7200
```

### 8.3 测试阶段命令

```bash
# 阶段一：基础压测（内存泄漏检测）
./run_disaster_test.sh phase1 --robots 100 --duration 7200

# 阶段二：场景切换压测
./run_disaster_test.sh phase2 --robots 100 --duration 3600

# 阶段三：进程杀死重启测试
./run_disaster_test.sh phase3 --kill scene_server --robots 20
./run_disaster_test.sh phase3 --kill match_server --robots 20
./run_disaster_test.sh phase3 --kill db_server --robots 20

# 阶段四：综合容灾测试
./run_disaster_test.sh phase4 --robots 200 --duration 7200

# 自定义测试
./run_disaster_test.sh custom --plan match_disconnect_stress --robots 30 --duration 1800
```

### 8.4 单独使用脚本

```bash
# 启动机器人（后台运行）
./start_test.sh login_logout_stress 50 --background

# 启动监控（运行1小时）
./monitor.sh /tmp/monitor_output 3600

# 杀死并重启服务（等待30秒后重启）
./kill_and_restart.sh match_server --wait 30

# 只杀死不重启
./kill_and_restart.sh scene_server --no-restart

# 生成测试报告
./report.sh test_results/phase1_20260210_120000
```

### 8.5 测试结果目录结构

```
test_results/
├── phase1_20260210_120000/
│   ├── test_params.txt      # 测试参数
│   ├── robot.log            # 机器人日志
│   ├── memory_go.csv        # Go 服务内存数据
│   ├── memory_rust.csv      # Rust 服务内存数据
│   ├── connections.log      # 连接数
│   ├── goroutine.log        # Goroutine 数量
│   ├── errors.log           # 错误日志
│   ├── summary.log          # 监控汇总
│   └── report.md            # 测试报告
└── phase3_scene_server_20260210_130000/
    ├── before_kill.txt      # 杀死前服务状态
    ├── after_restart.txt    # 重启后服务状态
    └── ...
```

---

## 9. 附录

### 9.1 关键代码位置

| 功能 | 文件路径 |
|------|----------|
| 机器人主入口 | `test/robot_game/main.go` |
| 机器人核心逻辑 | `test/robot_game/robot.go` |
| 动作定义 | `test/robot_game/action.go` |
| 计划配置 | `test/robot_game/config/plans/*.json` |
| 服务器生命周期 | `common/cmd/app.go` |
| 场景保存系统 | `servers/scene_server/internal/ecs/system/scene_save/` |
| 数据持久化 | `common/db_entry/town.go` |
| 匹配器核心逻辑 | `servers/match_server/internal/domain/matcher.go` |
| 匹配房间状态 | `servers/match_server/internal/domain/room.go` |
| 匹配状态机 | `servers/match_server/internal/domain/state.go` |
| 自动化测试脚本 | `test/robot_game/scripts/` |

### 9.2 匹配服务器架构说明

```
┌─────────────────────────────────────────────────────────────┐
│  Match Server 核心结构                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Matcher (每个副本配置一个)                                   │
│  ├── RoomMgr: map[uint64]*Room       # 房间管理              │
│  ├── GroupMgr: map[uint64]*MatchGroup # 匹配组管理           │
│  ├── AccountGroupMap                  # 玩家-组映射          │
│  └── GroupRoomMap                     # 组-房间映射          │
│                                                             │
│  Room (匹配房间)                                             │
│  ├── RoomState: IRoomState           # 状态机                │
│  ├── CampMgr: map[int]*Camp          # 阵营管理              │
│  └── UserSet: map[uint64]bool        # 玩家集合              │
│                                                             │
│  状态流转:                                                   │
│  InitState → MatchingState → ReadyState → FinishState       │
│           ↓                                      ↓          │
│      FailedState                           DoneState        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**关键点**：
- 所有匹配状态都是纯内存的，不持久化到数据库
- 服务重启后所有匹配状态丢失
- 客户端需要处理 `MatchCancel` 通知并能重新发起匹配

### 9.3 有用的 GM 命令

```bash
# 添加金钱
/ke* gm add_money 1 10000.00

# 添加物品
/ke* gm add_item <item_id> <count>

# 传送
/ke* gm teleport <x> <y> <z>

# 查询玩家状态
/ke* gm player_info
```
