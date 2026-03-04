# 测试指南

本文档整理 dev-workflow 中所有测试相关的规范和流程。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 测试类型与规范（Section 1-8） | Phase 4 实现后测试 |
| 压测机器人（Section 9-11） | 上线前压测 |
| 容灾测试（Section 10） | 上线前容灾验证 |
| 自动化脚本（Section 12） | 完整测试流程 |
| 玩家登录场景数据验证（Section 14） | 新/老玩家数据一致性验证 |
| 物理系统测试（Section 15） | 物理引擎功能验证 |

### 相关文档

| 文档 | 用途 |
|------|------|
| `DB.md` | Migration 测试、数据持久化验证 |
| `PROTO.md` | 协议兼容性测试 |
| `REVIEW.md` | 测试覆盖评估（Phase 6 审查） |
| `SKILL.md` | Phase 7 经验沉淀（测试相关经验沉淀到本文档） |

---

## 1. 测试类型

### 1.1 单元测试

针对单个函数或模块的测试，验证核心逻辑的正确性。

**适用场景**：
- Service 层业务逻辑
- Manager 层状态管理
- 工具函数
- 数据转换逻辑

**命名规范**：
- 测试文件：`xxx_test.go`
- 测试函数：`TestXxxFunction(t *testing.T)`

**执行命令**：
```bash
# 运行指定包测试
go test -v ./servers/scene_server/internal/...

# 运行指定测试函数
go test -v -run TestXxxFunction ./path/to/package

# 运行全部测试
make test
```

### 1.2 集成测试

验证多个模块之间的交互是否正确。

**适用场景**：
- 跨模块调用
- RPC 通信
- 数据库读写流程
- 工程间协作（协议工程 ↔ 业务工程）

**注意事项**：
- 需要准备测试环境或 mock
- 可能需要启动依赖服务
- 测试数据需要隔离

### 1.3 回归测试

确保新功能不破坏现有功能。

**适用场景**：
- 扩展现有系统（如为新场景复用现有系统）
- 重构代码
- 修复 Bug 后验证

**检查清单**：
- [ ] 原有场景的功能是否保持不变
- [ ] 数据兼容性是否满足
- [ ] 协议兼容性是否满足

### 1.4 Migration 测试

数据库变更脚本的本地测试。

**测试步骤**：
1. 在本地数据库执行 Migration 脚本
2. 验证表结构变更正确
3. 验证数据迁移正确（如有存量数据）
4. 测试回滚脚本

---

## 2. 测试时机

### 2.1 Phase 4：实现阶段

实现完成后，按以下顺序测试：

```
协议生成 → 配置生成 → DB Migration → 单元测试 → 集成测试
```

**任务示例**：
```markdown
### 业务工程任务
- [ ] [TASK-003] 单元测试 TestXxService

### 数据库任务
- [ ] [TASK-302] 本地测试 Migration
```

**任务依赖**：
```
TASK-001 → TASK-002 → TASK-003 → 集成测试
TASK-301 → 本地集成测试
```

### 2.2 Phase 6：产出审查阶段

使用 **dev-workflow-test-designer** Agent 评估测试覆盖是否充分。

**评估内容**：
- 核心逻辑是否有单元测试覆盖
- 关键路径是否有集成测试
- 边界条件是否测试
- 错误处理是否测试

---

## 3. 测试 Agent

### dev-workflow-test-designer

**职责**：测试设计专家，评估测试策略的完整性并设计测试方案。

**可用工具**：Read, Grep, Glob, Bash

**使用时机**：Phase 6 产出审查阶段，与其他审查 Agent 并行启动。

**评估要点**：
| 检查项 | 说明 |
|--------|------|
| 覆盖率 | 核心逻辑是否有测试覆盖 |
| 边界条件 | 极限值、空值、异常输入 |
| 错误路径 | 错误处理逻辑是否测试 |
| 并发场景 | 多协程场景是否测试 |
| 数据一致性 | 事务回滚后数据是否正确 |

---

## 4. 测试编写规范

### 4.1 表驱动测试

```go
func TestCalculate(t *testing.T) {
    tests := []struct {
        name     string
        input    int
        expected int
    }{
        {"positive", 5, 10},
        {"zero", 0, 0},
        {"negative", -3, -6},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := Calculate(tt.input)
            if result != tt.expected {
                t.Errorf("Calculate(%d) = %d, want %d", tt.input, result, tt.expected)
            }
        })
    }
}
```

### 4.2 Mock 使用

```go
// 定义接口
type DataStore interface {
    Get(key string) (string, error)
    Set(key string, value string) error
}

// Mock 实现
type MockDataStore struct {
    data map[string]string
}

func (m *MockDataStore) Get(key string) (string, error) {
    if v, ok := m.data[key]; ok {
        return v, nil
    }
    return "", errors.New("not found")
}
```

### 4.3 测试隔离

```go
func TestWithTempDB(t *testing.T) {
    // Setup: 创建临时数据
    testData := setupTestData()
    defer cleanupTestData(testData)  // Teardown

    // Test
    result := doSomething(testData)

    // Assert
    assert.Equal(t, expected, result)
}
```

---

## 5. 验证清单

### 5.1 实现前验证

**Phase 1 需求解析时**：
- [ ] 确认验收标准明确
- [ ] 确认测试环境或本地 mock 可用
- [ ] 确认依赖路径存在（协议工程、配置工程）

### 5.2 实现后验证

**Phase 4 实现完成后**：
- [ ] 协议生成代码验证
- [ ] 配置生成代码验证
- [ ] Migration 脚本本地测试通过
- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 构建通过 (`make build`)

### 5.3 构建与测试验证

**Phase 5 构建与测试时**：
- [ ] 所有目标服务器构建成功
- [ ] 编译警告已处理（如有）
- [ ] 单元测试全部通过
- [ ] 集成测试全部通过
- [ ] 测试覆盖率符合要求（如有覆盖率要求）
- [ ] 无 race condition（`go test -race` 通过）

### 5.4 审查时验证

**Phase 6 产出审查时**：
- [ ] 运行构建和测试确认通过
- [ ] 功能完整性核对（对照验收标准）
- [ ] 测试覆盖情况评估
- [ ] 回归测试通过（如扩展现有系统）

---

## 6. 常用测试命令

```bash
# 运行所有测试
make test

# 生成覆盖率报告
make test-coverage
# 报告位置: build/coverage.html

# 运行指定包测试
go test -v ./common/db/...
go test -v ./servers/scene_server/internal/...

# 运行指定测试函数
go test -v -run TestFunctionName ./path/to/package

# 运行测试并显示覆盖率
go test -v -cover ./...

# 运行测试（带 race 检测）
go test -v -race ./...

# 运行基准测试
go test -bench=. ./path/to/package
```

---

## 7. 测试环境

### 7.1 本地环境

**依赖服务**：
- MongoDB（测试数据库）
- Redis（测试缓存）

**配置**：
- 使用独立的测试数据库名（避免污染开发数据）
- 测试完成后清理测试数据

### 7.2 CI 环境

**流程**：
```
代码提交 → 构建 → 单元测试 → 集成测试 → 报告
```

**失败处理**：
- 测试失败时阻止合并
- 查看失败日志定位问题
- 修复后重新触发 CI

---

## 8. 事务性代码测试要点

针对涉及事务的代码，需要特别测试以下场景：

| 测试场景 | 验证内容 |
|----------|----------|
| 正常流程 | 事务提交后数据正确 |
| 验证失败 | 前置检查失败时不修改任何状态 |
| 执行中失败 | 回滚逻辑正确，数据恢复到初始状态 |
| 并发执行 | 多协程同时执行时数据一致 |
| 幂等性 | 相同请求多次执行结果一致 |
| 超时处理 | 超时后正确处理（回滚或补偿） |

**测试示例**：
```go
func TestTransaction_Rollback(t *testing.T) {
    // Setup
    entity := createTestEntity()
    snapshot := entity.Snapshot()

    // 模拟执行中失败
    err := doTransactionWithError(entity)

    // Assert: 数据应该回滚
    assert.Error(t, err)
    assert.Equal(t, snapshot, entity.Snapshot())
}
```

---

## 9. 压测机器人

项目提供了 `robot_game` 压测工具，用于模拟大量玩家并发操作，验证服务器性能和稳定性。

### 9.1 目录结构

```
test/robot_game/
├── main.go              # 入口
├── robot_mgr.go         # 机器人管理器
├── robot.go             # 机器人实现
├── plan_mgr.go          # 测试计划管理
├── plan.go              # 测试计划定义
├── action.go            # 动作实现
├── base/
│   ├── config.go        # 配置结构
│   └── robot.go         # 机器人接口
├── config/
│   ├── config.toml      # 机器人配置文件
│   └── plans/           # 测试计划 JSON 文件
│       ├── match_stress.json
│       ├── disaster_recovery_stress.json
│       └── ...
└── scripts/             # 自动化测试脚本（见第 12 章）
    ├── run_disaster_test.sh
    ├── start_test.sh
    └── ...
```

### 9.2 构建和运行

```bash
# 构建压测机器人
make robot_game

# 运行压测（使用默认配置）
make run-robot

# 指定配置文件运行
./bin/robot_game -config path/to/config.toml
```

### 9.3 配置文件

**config.toml 示例**（位于 `test/robot_game/config/config.toml`）：
```toml
[global]
log_dir = "log"
log_level = "info"
register_addr = "127.0.0.1:9000"  # 注册中心地址

[robot]
log_base = "robot"
login_url = "http://127.0.0.1:3888/guest_login"  # 登录服务器地址
robot_num = 100           # 机器人数量
plan_name = "match_stress" # 测试计划名称
start_delay = 50          # 启动间隔（毫秒）
```

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `robot_num` | 并发机器人数量 | 100 |
| `plan_name` | 执行的测试计划名称 | match_stress |
| `start_delay` | 机器人启动间隔（ms） | 50 |

### 9.4 测试计划

测试计划定义在 `plans/` 目录下的 JSON 文件中。

**计划结构**：
```json
{
    "name": "plan_name",
    "description": "计划描述",
    "actions": [
        {"action_type": "action_name", "params": {...}}
    ],
    "loop_count": 0    // 0 表示无限循环
}
```

**可用动作类型**：

| 动作类型 | 说明 | 参数 |
|----------|------|------|
| **基础动作** | | |
| `gm_action` | 执行 GM 命令 | `gm_text`: GM 命令文本 |
| `wait_action` | 等待指定时间 | `duration_ms`: 等待毫秒数 |
| **场景动作** | | |
| `enter_town_action` | 进入小镇场景 | `teleport_id`: 传送点 ID（可选） |
| `enter_sakura_action` | 进入樱花校园 | - |
| `exit_scene_action` | 退出当前场景 | - |
| `random_move_action` | 随机移动 | `duration_ms`: 移动时长 |
| **匹配动作** | | |
| `start_match_action` | 开始匹配 | `dungeon_cfg_id`, `can_add_other` |
| `stop_match_action` | 停止匹配 | - |
| `wait_match_enter_ready_action` | 等待匹配确认 | `timeout_ms`: 超时时间 |
| `wait_in_scene_and_exit_action` | 等待进入场景后退出 | `scene_cfg_id`: 场景配置 ID |
| **邮件动作** | | |
| `get_all_mails_action` | 获取所有邮件 | - |
| `read_mails_action` | 读取邮件 | - |
| `delete_mails_action` | 删除邮件 | - |
| `collect_mail_rewards_action` | 领取邮件奖励 | - |
| **容灾动作** | | |
| `logout_action` | 登出 | - |
| `relogin_action` | 重新登录 | - |
| `force_disconnect_action` | 强制断开连接 | - |
| `reconnect_action` | 重连 | - |
| `verify_data_action` | 验证数据一致性 | - |

### 9.5 已有测试计划

| 计划名称 | 文件 | 用途 |
|----------|------|------|
| `match_stress` | `match_stress.json` | 匹配系统压力测试 |
| `mail_stress_test` | `mail_stress_test.json` | 邮件系统压力测试 |
| `town_scene_stress` | `town_scene_stress.json` | 小镇场景压力测试 |
| `sakura_scene_stress` | `sakura_scene_stress.json` | 樱花校园压力测试 |
| `multi_scene_switch_stress` | `multi_scene_switch_stress.json` | 多场景切换压力测试 |
| `login_logout_stress` | `login_logout_stress.json` | 登录登出压力测试 |
| `match_disconnect_stress` | `match_disconnect_stress.json` | 匹配中断线压力测试 |
| `disaster_recovery_stress` | `disaster_recovery_stress.json` | 容灾综合测试 |
| `new_player_scene_test` | `new_player_scene_test.json` | 新玩家全场景登录测试 |
| `old_player_data_verify` | `old_player_data_verify.json` | 老玩家数据一致性验证 |
| `physics_stress` | `physics_stress.json` | 物理系统压力测试 |

### 9.6 自定义测试计划

1. 在 `test/robot_game/config/plans/` 目录下创建新的 JSON 文件
2. 定义计划名称、描述和动作序列
3. 修改 config.toml 中的 `plan_name` 指向新计划
4. 运行 `make run-robot`

**示例：创建新计划**：
```json
{
    "name": "my_custom_test",
    "description": "自定义测试：进入小镇 -> 执行操作 -> 退出",
    "actions": [
        {"action_type": "enter_town_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "gm_action", "params": {"gm_text": "/ke* gm add_money 1 1000"}},
        {"action_type": "random_move_action", "params": {"duration_ms": 5000}},
        {"action_type": "exit_scene_action", "params": {}}
    ],
    "loop_count": 10
}
```

---

## 10. 容灾测试

容灾测试验证服务器在异常情况下的数据一致性和恢复能力。

### 10.1 测试场景

| 场景 | 描述 | 验证内容 |
|------|------|----------|
| **断线重连** | 客户端突然断开连接后重连 | 玩家状态恢复、数据不丢失 |
| **服务器重启** | 服务器进程重启 | 内存数据持久化、玩家可重连 |
| **网络抖动** | 网络延迟或短暂中断 | 请求重试、数据最终一致 |
| **并发冲突** | 多个请求同时修改同一数据 | 数据一致性、无脏写 |
| **场景切换** | 切换场景时断线 | 场景状态正确、位置正确 |

### 10.2 容灾测试计划

使用 `disaster_recovery_stress` 计划进行综合容灾测试：

```json
{
    "name": "disaster_recovery_stress",
    "description": "综合容灾测试。登录 -> 进入小镇 -> 执行操作 -> 强制断线 -> 重连 -> 验证数据",
    "actions": [
        {"action_type": "enter_town_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "gm_action", "params": {"gm_text": "/ke* gm add_money 1 10000.00"}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 5000}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "force_disconnect_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "reconnect_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "verify_data_action", "params": {}}
    ],
    "loop_count": 0
}
```

**测试流程**：
1. 进入小镇场景
2. 执行 GM 命令修改数据（如加钱）
3. 执行随机移动
4. 强制断开连接
5. 等待一段时间后重连
6. 验证数据是否正确（金钱数量、位置等）

### 10.3 运行容灾测试

**方式一：简单运行（make run-robot）**

```bash
# 修改配置使用容灾测试计划
# config.toml:
# [robot]
# plan_name = "disaster_recovery_stress"
# robot_num = 50

# 运行测试
make run-robot

# 查看日志
tail -f log/robot*.log
```

**方式二：使用自动化脚本（推荐，见第 12 章）**

```bash
cd P1GoServer/test/robot_game/scripts
./run_disaster_test.sh phase4 --robots 50 --duration 3600
```

自动化脚本提供监控、报告生成、服务重启等完整功能。

### 10.4 容灾测试检查清单

**断线重连测试**：
- [ ] 断线后玩家状态正确保存
- [ ] 重连后玩家数据完整恢复
- [ ] 重连后位置正确
- [ ] 重连后背包物品不丢失
- [ ] 重连后进行中的任务状态正确

**服务器重启测试**：
- [ ] 重启前内存数据已持久化到 DB
- [ ] 重启后玩家可正常重连
- [ ] 重启后 NPC 状态正确恢复
- [ ] 重启后定时任务正确恢复

**并发冲突测试**：
- [ ] 同一玩家多端登录处理正确
- [ ] 同一物品并发操作数据一致
- [ ] 交易并发场景金额正确

### 10.5 容灾相关代码位置

| 功能 | 代码位置 |
|------|----------|
| 断线检测 | `common/rpc/session.go` |
| 登录/重连处理 | `servers/login_server/internal/domain/login_handler.go` |
| 网关用户管理 | `servers/gate_server/internal/domain/user_mgr.go` |
| 玩家进入场景 | `servers/scene_server/internal/net_func/player/enter.go` |
| 数据持久化 | `servers/db_server/internal/data/row_mgr.go` |
| 场景状态保存 | `servers/scene_server/internal/ecs/scene/save.go` |

### 10.6 添加新的容灾动作

如需添加新的容灾测试动作：

1. **在 action.go 中定义新动作**：
```go
type MyDisasterAction struct {
    // 参数字段
}

func (a *MyDisasterAction) GetName() string {
    return "my_disaster_action"
}

func (a *MyDisasterAction) Execute(robot *Robot) ActionResult {
    // 实现动作逻辑
    return ActionResult_Success
}

func (a *MyDisasterAction) Reset() {
    // 重置状态
}
```

2. **在 plan.go 的 newActionFromConfig 中注册**：
```go
case "my_disaster_action":
    return &MyDisasterAction{}
```

3. **在测试计划 JSON 中使用**：
```json
{"action_type": "my_disaster_action", "params": {...}}
```

---

## 11. 压测结果分析

### 11.1 关键指标

| 指标 | 说明 | 参考值 |
|------|------|--------|
| **QPS** | 每秒请求数 | 根据业务场景 |
| **响应时间** | 请求处理时间 | P99 < 100ms |
| **成功率** | 请求成功比例 | > 99.9% |
| **内存使用** | 服务器内存占用 | 平稳，无泄漏 |
| **CPU 使用** | 服务器 CPU 占用 | < 80% |
| **连接数** | 并发连接数量 | 根据配置 |

### 11.2 日志分析

```bash
# 查看机器人日志
tail -f log/robot*.log

# 统计错误数量
grep -c "ERROR" log/robot*.log

# 查看服务器日志
tail -f bin/log/scene_server.log

# 监控服务器资源
top -p $(pgrep scene_server)
```

### 11.3 常见问题排查

| 问题 | 可能原因 | 排查方法 |
|------|----------|----------|
| 连接失败 | 服务器未启动/端口错误 | 检查服务器状态和配置 |
| 大量超时 | 服务器负载过高 | 减少机器人数量，检查服务器性能 |
| 数据不一致 | 并发冲突/持久化失败 | 检查 db_server 日志 |
| 内存增长 | 资源泄漏 | pprof 分析内存 |

---

## 12. 自动化测试脚本

项目提供了一套自动化测试脚本，位于 `test/robot_game/scripts/` 目录。

### make run-robot vs 自动化脚本

| 特性 | `make run-robot` | `scripts/run_disaster_test.sh` |
|------|------------------|-------------------------------|
| **定位** | 快速启动，开发调试 | 完整测试框架，正式压测 |
| **配置方式** | 固定读取 config.toml | 支持命令行参数覆盖 |
| **资源监控** | 无 | 自动监控内存/CPU/连接数 |
| **测试报告** | 无 | 自动生成 Markdown 报告 |
| **服务重启测试** | 不支持 | 支持杀死/重启服务 |
| **多阶段测试** | 不支持 | 支持 phase1-4 递进测试 |
| **结果保存** | 仅日志 | 完整保存到 test_results/ |
| **dry-run** | 不支持 | 支持预览命令 |

**选择建议**：
- 开发调试、快速验证 → `make run-robot`
- 正式压测、容灾测试、需要报告 → 使用脚本

### 12.1 脚本目录结构

```
test/robot_game/scripts/
├── README.md              # 使用说明
├── config.sh              # 配置文件（路径、参数、辅助函数）
├── run_disaster_test.sh   # 主控脚本（支持多阶段测试）
├── start_test.sh          # 启动机器人测试
├── monitor.sh             # 监控服务器资源
├── kill_and_restart.sh    # 杀死并重启服务
└── report.sh              # 生成测试报告
```

### 12.2 使用前提

**1. 构建机器人**：
```bash
make robot_game
```

**2. 启动服务器**：
确保以下服务已启动：
- login_server（默认端口 3888）
- scene_server
- db_server
- 其他依赖服务

**3. 检查配置**：
```bash
# 查看/修改配置
vim test/robot_game/scripts/config.sh
vim test/robot_game/config/config.toml
```

### 12.3 主控脚本 (run_disaster_test.sh)

支持多阶段测试，从快速验证到完整容灾测试。

**查看帮助**：
```bash
cd P1GoServer/test/robot_game/scripts
./run_disaster_test.sh --help
```

**测试阶段**：

| 阶段 | 命令 | 说明 |
|------|------|------|
| `quick` | `./run_disaster_test.sh quick` | 快速验证（5分钟，5个机器人）|
| `phase1` | `./run_disaster_test.sh phase1` | 基础压测（内存泄漏检测）|
| `phase2` | `./run_disaster_test.sh phase2` | 场景切换压测 |
| `phase3` | `./run_disaster_test.sh phase3` | 进程杀死重启测试 |
| `phase4` | `./run_disaster_test.sh phase4` | 综合容灾测试 |
| `custom` | `./run_disaster_test.sh custom` | 自定义测试 |

**常用参数**：

| 参数 | 说明 | 示例 |
|------|------|------|
| `--robots <num>` | 机器人数量 | `--robots 100` |
| `--duration <sec>` | 测试时长（秒）| `--duration 3600` |
| `--plan <name>` | 测试计划名称 | `--plan match_stress` |
| `--kill <service>` | 要杀死的服务 | `--kill scene_server` |
| `--dry-run` | 只显示命令不执行 | `--dry-run` |

**使用示例**：

```bash
# 快速验证（推荐首次使用）
./run_disaster_test.sh quick

# Dry-run 模式查看将执行的命令
./run_disaster_test.sh phase1 --robots 50 --dry-run

# 阶段一：内存泄漏检测（2小时）
./run_disaster_test.sh phase1 --robots 100 --duration 7200

# 阶段二：场景切换压测
./run_disaster_test.sh phase2 --robots 100 --duration 3600

# 阶段三：杀死指定服务测试
./run_disaster_test.sh phase3 --kill scene_server
./run_disaster_test.sh phase3 --kill match_server

# 阶段四：综合容灾（每10分钟随机杀死一个服务）
./run_disaster_test.sh phase4 --robots 200 --duration 7200

# 自定义测试
./run_disaster_test.sh custom --plan disaster_recovery_stress --robots 50 --duration 1800
```

### 12.4 启动测试脚本 (start_test.sh)

单独启动机器人执行指定测试计划。

```bash
# 查看帮助和可用计划
./start_test.sh --help

# 前台运行（可看实时输出）
./start_test.sh login_logout_stress 20

# 后台运行
./start_test.sh match_stress 50 --background

# 停止后台机器人
pkill -f robot_game
```

### 12.5 监控脚本 (monitor.sh)

监控服务器资源使用情况。

```bash
# 监控 300 秒，输出到指定目录
./monitor.sh /path/to/output 300
```

**监控内容**：
- 服务进程内存使用（KB）
- CPU 使用率
- 连接数统计
- 输出 CSV 格式便于分析

### 12.6 服务重启脚本 (kill_and_restart.sh)

用于容灾测试中杀死并重启服务。

```bash
# 杀死 scene_server 并等待 10 秒后重启
./kill_and_restart.sh scene_server --wait 10

# 仅杀死不重启
./kill_and_restart.sh scene_server --no-restart
```

### 12.7 报告生成脚本 (report.sh)

生成测试结果报告。

```bash
./report.sh /path/to/test_output
```

**报告内容**：
- 测试参数摘要
- 内存使用趋势（CSV）
- 错误统计
- 连接数统计
- Markdown 格式报告

### 12.8 配置文件说明

**config.sh 关键配置**：

```bash
# 路径配置
export GO_SERVER_ROOT="/home/miaoriofeng/workspace/server/P1GoServer"
export RUST_SERVER_ROOT="/home/miaoriofeng/workspace/server/server_old"

# 机器人配置
export ROBOT_BIN="${GO_BIN_DIR}/robot_game"
export ROBOT_CONFIG="${GO_SERVER_ROOT}/test/robot_game/config/config.toml"
export ROBOT_PLANS_DIR="${GO_SERVER_ROOT}/test/robot_game/config/plans"

# 测试参数
export DEFAULT_ROBOT_NUM=10
export DEFAULT_TEST_DURATION=3600
export MONITOR_INTERVAL=5
export RESTART_WAIT_TIME=10
```

**config.toml 关键配置**：

```toml
[global]
log_dir = "log"
log_level = "info"
register_addr = "127.0.0.1:9000"

[robot]
login_url = "http://127.0.0.1:3888/guest_login"
robot_num = 10
plan_name = "login_logout_stress"
start_delay = 100
```

### 12.9 测试结果目录

测试结果保存在 `test_results/` 目录：

```
test_results/
├── phase1_20240210_143022/
│   ├── test_params.txt      # 测试参数
│   ├── memory_usage.csv     # 内存数据
│   ├── robot.log            # 机器人日志
│   ├── error.log            # 错误日志
│   └── report.md            # Markdown 报告
├── phase3_scene_server_20240210_150000/
│   ├── before_kill.txt      # 杀死前状态
│   ├── after_restart.txt    # 重启后状态
│   └── ...
└── quick_20240210_160000/
    └── ...
```

### 12.10 完整测试流程示例

```bash
cd P1GoServer/test/robot_game/scripts

# 1. 首次使用：快速验证环境
./run_disaster_test.sh quick

# 2. 基础压测：检测内存泄漏
./run_disaster_test.sh phase1 --robots 50 --duration 3600

# 3. 场景压测：验证场景切换
./run_disaster_test.sh phase2 --robots 100 --duration 1800

# 4. 容灾测试：杀死关键服务
./run_disaster_test.sh phase3 --kill scene_server
./run_disaster_test.sh phase3 --kill db_server

# 5. 综合测试：长时间稳定性
./run_disaster_test.sh phase4 --robots 200 --duration 7200

# 6. 查看测试结果
ls -la ../../test_results/
cat ../../test_results/*/report.md
```

---

## 13. 测试文件管理

### 13.1 Go internal 包限制

Go 语言的 `internal` 包机制限制了外部代码对 `internal/` 目录下包的访问。只有与 `internal` 目录同级或其子目录下的代码才能导入 `internal` 包。

**问题**：如果测试文件放在独立目录（如 `P1GoServer/.claude/tests/`），无法访问 `internal/` 下的业务代码。

**解决方案**：采用混合管理策略

| 测试类型 | 存放位置 | 原因 |
|----------|----------|------|
| **单元测试**（组件级） | `servers/**/internal/**/*_test.go` | Go 要求，必须与被测代码同目录 |
| **集成测试**（跨模块） | `P1GoServer/.claude/tests/` | 通过公开接口测试，不受限制 |
| **测试源文件**（备份） | `P1GoServer/.claude/tests/` | 方便管理和复用 |

### 13.2 .gitignore 配置

为避免测试文件污染代码仓库，在 `.gitignore` 中添加通配符排除：

```gitignore
# Claude Code 生成的测试文件（放在 internal 目录以绕过 Go 的包访问限制）
servers/**/internal/**/*_test.go
```

**效果**：
- 测试文件可以正常运行（位于正确目录）
- 不会被提交到代码仓库
- `P1GoServer/.claude/tests/` 保留测试源文件作为备份

### 13.3 测试文件创建流程

```
1. 在 P1GoServer/.claude/tests/ 创建测试源文件
2. 复制到对应的 internal/ 目录
3. 修改包名（从 xxx_test 改为与业务包一致）
4. 移除不必要的包前缀引用
5. 运行测试验证
```

---

## 14. 玩家登录场景数据验证测试

验证新玩家和老玩家登录各场景后数据是否正确。

### 14.1 测试场景类型

根据 `SceneTypeEnumProto` 定义，游戏支持以下场景类型：

| 场景类型 | 枚举值 | 说明 | 测试优先级 |
|----------|--------|------|------------|
| City | 1 | 大世界/主场景 | 高 |
| Town | 7 | 小镇（玩家私人） | 高 |
| Sakura | 8 | 樱花校园 | 高 |
| Dungeon | 2 | 副本 | 中 |
| Match | 6 | 匹配场景 | 中 |
| Possession | 3 | 资产（家园等） | 中 |
| Test | 0 | 测试场景 | 低 |

### 14.2 玩家核心数据验证项

登录后需要验证的关键数据（来自 `UserRes` 和 `DBSaveRoleInfo`）：

| 数据类别 | 验证字段 | 验证内容 |
|----------|----------|----------|
| **基础信息** | `RoleId`, `AccountId` | ID 正确且匹配 |
| | `RoleName` | 名称不为空，长度合规 |
| | `Gender`, `Title` | 数值在有效范围内 |
| | `CreateStamp` | 时间戳合理 |
| **成长数据** | `RoleLevel`, `RoleExp` | 等级经验非负，等级<=上限 |
| | `GrowthAttributeList` | 属性列表完整 |
| **资产数据** | `RoleWallet` | 金币/钻石数量非负 |
| | `RoleBackpack` | 背包物品数据完整 |
| | `ClothingBackpack` | 服装数据完整 |
| | `HouseList`, `VehicleList` | 房屋车辆列表可空但不为nil |
| **形象数据** | `PartList`, `AvatarList` | 形象部件完整 |
| | `SakuraPartList` | 樱花形象列表（可空） |
| **小镇数据** | `TownInventoryComp` | 小镇库存数据 |
| | `TownPlayerStatus` | 小镇玩家状态 |
| **樱花数据** | `SakuraWorkshopCompInfo` | 樱花工坊数据 |
| **特殊玩法** | `Achievement` | 成就数据 |
| | `WelcomeDungeonInfo` | 新手副本信息 |

### 14.3 新玩家 vs 老玩家差异

| 验证项 | 新玩家预期 | 老玩家预期 |
|--------|------------|------------|
| `RoleLevel` | 1 | >= 1 |
| `RoleExp` | 0 或初始值 | 根据等级累积 |
| `RoleWallet` | 初始金额（配置） | >= 0 |
| `Achievement` | 无或初始成就 | 有进度 |
| `TownInventoryComp` | 空或初始 | 有存货 |
| `HouseList` | 空或初始房屋 | 可能有多个 |
| `LastOnlineTime` | 0 或首次登录时间 | 历史登录时间 |
| `LastOfflineTime` | 0 | 上次离线时间 |

### 14.4 测试动作

**已实现动作**（可直接使用）：

| 动作类型 | 说明 | 参数 |
|----------|------|------|
| `verify_data_action` | 验证角色基础数据 | 无 |
| `enter_town_action` | 进入小镇场景 | `teleport_id`(可选) |
| `enter_sakura_action` | 进入樱花校园 | 无 |
| `enter_city_action` | 进入大世界 | `teleport_id`(可选) |
| `exit_scene_action` | 退出当前场景 | 无 |
| `random_move_action` | 随机移动 | `duration_ms` |
| `logout_action` | 登出 | 无 |
| `relogin_action` | 重新登录 | 无 |
| `gm_action` | 执行GM命令 | `gm_text` |
| `wait_action` | 等待指定时间 | `duration_ms` |

**待实现动作**（需要扩展 action.go）：

| 动作类型 | 说明 | 参数 |
|----------|------|------|
| `verify_player_data_action` | 验证玩家详细数据 | `check_items`: 验证项列表 |
| `verify_scene_data_action` | 验证场景相关数据 | `scene_type`: 场景类型 |
| `compare_before_after_action` | 对比操作前后数据 | `snapshot_key`: 快照键名 |

### 14.5 测试计划示例

**新玩家全场景登录测试** (`new_player_scene_test.json`)：

```json
{
    "name": "new_player_scene_test",
    "description": "新玩家登录各场景数据验证。依次进入小镇、樱花校园、大世界，每个场景停留后验证数据",
    "actions": [
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "enter_town_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 3000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "enter_sakura_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 3000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "enter_city_action", "params": {"teleport_id": 0}},
        {"action_type": "wait_action", "params": {"duration_ms": 5000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 3000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}}
    ],
    "loop_count": 1
}
```

**老玩家数据一致性测试** (`old_player_data_verify.json`)：

```json
{
    "name": "old_player_data_verify",
    "description": "老玩家数据一致性验证。登录 -> 进入小镇 -> 执行GM加钱 -> 登出 -> 重登 -> 验证数据",
    "actions": [
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "enter_town_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "gm_action", "params": {"gm_text": "/ke* gm add_money 1 1000"}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 5000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "logout_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "relogin_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "enter_town_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "verify_data_action", "params": {}}
    ],
    "loop_count": 10
}
```

### 14.6 验证检查清单

**新玩家登录验证**：
- [ ] 基础信息（ID、名称、性别）正确初始化
- [ ] 等级和经验为初始值
- [ ] 钱包金额为配置的初始值
- [ ] 背包为空或只有初始物品
- [ ] 形象数据完整
- [ ] 进入小镇数据正确
- [ ] 进入樱花校园数据正确
- [ ] 进入副本数据正确

**老玩家登录验证**：
- [ ] 基础信息与数据库一致
- [ ] 等级经验与存档一致
- [ ] 钱包金额与存档一致
- [ ] 背包物品完整无丢失
- [ ] 成就进度正确恢复
- [ ] 小镇数据正确恢复
- [ ] 重登后数据无变化

**场景切换数据验证**：
- [ ] 切换场景后角色位置正确
- [ ] 切换场景后背包数据不变
- [ ] 切换场景后钱包数据不变
- [ ] 切换场景后状态正确更新

### 14.7 相关代码位置

| 功能 | 代码位置 |
|------|----------|
| 场景类型定义 | `common/proto/base_pb.go:81-90` |
| 玩家状态结构 | `orm/mongo/player_state.go` |
| 完整角色数据 | `common/proto/db_pb.go:10055-10079` |
| 登录返回数据 | `common/proto/logic_pb.go:7191-7201` |
| 玩家进入场景 | `servers/scene_server/internal/net_func/player/enter.go` |
| 数据持久化 | `servers/db_server/internal/data/row_mgr.go` |

---

## 15. 物理系统测试

验证游戏物理系统的正确性，包括 PhysX 物理引擎和体素物理系统。

### 15.1 物理系统架构

项目包含两套物理系统：

| 系统 | 目录 | 用途 |
|------|------|------|
| **PhysX 物理引擎** | `pkg/physics/`, `common/physics/` | 角色控制、刚体模拟、触发器 |
| **体素物理系统** | `common/voxel/physics/` | 建筑/地形碰撞、体素射线检测 |

### 15.2 PhysX 物理功能

#### 核心类型

| 类型 | 说明 |
|------|------|
| `SourcePhysx` | 物理场景容器 |
| `Vec3f` | 三维浮点向量 |
| `Actor` | 普通刚体（球体、立方体、胶囊体） |
| `Trigger` | 触发器（进入/离开事件） |
| `CharacterController` | 角色控制器 |
| `RaycastResult` | 射线检测结果 |

#### 测试功能点

| 功能模块 | 测试内容 |
|----------|----------|
| **场景管理** | 场景创建/销毁、模拟步进 |
| **刚体创建** | 球体/立方体/胶囊体创建和销毁 |
| **角色控制** | 创建、移动、获取位置、销毁 |
| **触发器** | 创建、回调设置、进入/离开事件 |
| **射线检测** | Raycast 命中检测、距离计算 |
| **调试工具** | PVD 连接（可选） |

### 15.3 体素物理功能

#### 核心类型

| 类型 | 说明 |
|------|------|
| `Ray` | 射线（整数坐标，单位：厘米） |
| `RaycastHit` | 射线命中结果 |
| `CollisionInfo` | 碰撞信息 |

#### 测试功能点

| 功能模块 | 测试内容 |
|----------|----------|
| **碰撞检测** | 点与体素碰撞、AABB 碰撞 |
| **碰撞解决** | 推出体素、穿透深度计算 |
| **射线检测** | DDA 算法射线检测、多体素穿透 |
| **精度验证** | 整数运算精度、距离计算 |

### 15.4 单元测试用例

#### PhysX 物理测试

```go
// 文件: common/physics/physx_test.go

func TestPhysXScene(t *testing.T) {
    tests := []struct {
        name string
        test func(t *testing.T)
    }{
        {"CreateAndDestroyScene", testCreateDestroyScene},
        {"SimulationStep", testSimulationStep},
    }
    for _, tt := range tests {
        t.Run(tt.name, tt.test)
    }
}

func TestCharacterController(t *testing.T) {
    tests := []struct {
        name string
        test func(t *testing.T)
    }{
        {"CreateController", testCreateController},
        {"MoveController", testMoveController},
        {"GetPosition", testGetPosition},
        {"DestroyController", testDestroyController},
    }
    for _, tt := range tests {
        t.Run(tt.name, tt.test)
    }
}

func TestTrigger(t *testing.T) {
    tests := []struct {
        name string
        test func(t *testing.T)
    }{
        {"CreateTrigger", testCreateTrigger},
        {"TriggerEnterCallback", testTriggerEnter},
        {"TriggerExitCallback", testTriggerExit},
    }
    for _, tt := range tests {
        t.Run(tt.name, tt.test)
    }
}

func TestRaycast(t *testing.T) {
    tests := []struct {
        name     string
        origin   Vec3f
        dir      Vec3f
        maxDist  float32
        expected bool // 是否命中
    }{
        {"HitGround", Vec3f{0, 10, 0}, Vec3f{0, -1, 0}, 100, true},
        {"MissEmpty", Vec3f{0, 10, 0}, Vec3f{0, 1, 0}, 100, false},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := scene.Raycast(tt.origin, tt.dir, tt.maxDist)
            if result.Hit != tt.expected {
                t.Errorf("Raycast hit=%v, want %v", result.Hit, tt.expected)
            }
        })
    }
}
```

#### 体素物理测试

```go
// 文件: common/voxel/physics/collision_test.go

func TestVoxelCollision(t *testing.T) {
    tests := []struct {
        name     string
        point    common.Vec3I
        expected bool
    }{
        {"InsideSolid", common.Vec3I{100, 100, 100}, true},
        {"InsideEmpty", common.Vec3I{0, 1000, 0}, false},
        {"AtBoundary", common.Vec3I{0, 0, 0}, true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            info := CheckCollision(world, tt.point)
            if info.Collided != tt.expected {
                t.Errorf("Collision=%v, want %v", info.Collided, tt.expected)
            }
        })
    }
}

func TestVoxelRaycast(t *testing.T) {
    tests := []struct {
        name        string
        ray         Ray
        expectHit   bool
        expectDist  int32 // 厘米
    }{
        {
            "DownwardRay",
            Ray{Origin: common.Vec3I{0, 10000, 0}, Direction: common.Vec3I{0, -1, 0}, MaxDistance: 20000},
            true,
            10000,
        },
        {
            "HorizontalMiss",
            Ray{Origin: common.Vec3I{0, 50000, 0}, Direction: common.Vec3I{1, 0, 0}, MaxDistance: 10000},
            false,
            0,
        },
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            hit := Raycast(world, tt.ray)
            if hit.Hit != tt.expectHit {
                t.Errorf("Hit=%v, want %v", hit.Hit, tt.expectHit)
            }
            if hit.Hit && hit.Distance != tt.expectDist {
                t.Errorf("Distance=%d, want %d", hit.Distance, tt.expectDist)
            }
        })
    }
}

func TestCollisionResolution(t *testing.T) {
    tests := []struct {
        name        string
        point       common.Vec3I
        expectPush  bool
    }{
        {"PushOutOfSolid", common.Vec3I{50, 50, 50}, true},
        {"NoNeedPush", common.Vec3I{0, 1000, 0}, false},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            resolved := ResolveCollision(world, tt.point)
            pushed := resolved != tt.point
            if pushed != tt.expectPush {
                t.Errorf("Pushed=%v, want %v", pushed, tt.expectPush)
            }
        })
    }
}
```

### 15.5 集成测试场景

| 测试场景 | 验证内容 |
|----------|----------|
| **角色移动碰撞** | 角色控制器移动时正确触发碰撞 |
| **触发器区域** | 进入/离开触发区域事件正确触发 |
| **射线拾取** | 点击地面/物体射线检测正确 |
| **角色站立** | 角色站在地面上不穿透 |
| **斜坡行走** | 角色在斜坡上正常移动 |
| **跳跃落地** | 跳跃后正确落地，不穿透地面 |

### 15.6 压测动作

**已实现动作**（通过移动间接测试物理系统）：

| 动作类型 | 说明 | 参数 |
|----------|------|------|
| `random_move_action` | 随机移动（触发物理碰撞） | `duration_ms` |
| `enter_town_action` | 进入小镇（加载物理场景） | `teleport_id`(可选) |
| `enter_sakura_action` | 进入樱花校园 | 无 |
| `enter_city_action` | 进入大世界 | `teleport_id`(可选) |

**待实现动作**（需要扩展 action.go）：

| 动作类型 | 说明 | 参数 |
|----------|------|------|
| `physics_move_stress_action` | 物理移动压测 | `duration_ms`, `move_speed` |
| `trigger_stress_action` | 触发器压测 | `trigger_count`, `enter_exit_cycles` |
| `raycast_stress_action` | 射线检测压测 | `ray_count`, `max_distance` |

### 15.7 物理测试计划示例

**物理系统压测** (`physics_stress.json`)：

```json
{
    "name": "physics_stress",
    "description": "物理系统压力测试。在各场景中持续移动，触发物理碰撞检测",
    "actions": [
        {"action_type": "enter_town_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 30000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "enter_sakura_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 30000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}},
        {"action_type": "enter_city_action", "params": {"teleport_id": 0}},
        {"action_type": "wait_action", "params": {"duration_ms": 3000}},
        {"action_type": "random_move_action", "params": {"duration_ms": 30000}},
        {"action_type": "verify_data_action", "params": {}},
        {"action_type": "exit_scene_action", "params": {}},
        {"action_type": "wait_action", "params": {"duration_ms": 2000}}
    ],
    "loop_count": 10
}
```

### 15.8 验证检查清单

**PhysX 物理验证**：
- [ ] 场景创建销毁无内存泄漏
- [ ] 刚体创建销毁正确
- [ ] 角色控制器移动正确
- [ ] 触发器回调正确触发
- [ ] 射线检测结果正确
- [ ] 多线程访问安全

**体素物理验证**：
- [ ] 碰撞检测准确
- [ ] 碰撞解决推出方向正确
- [ ] 射线检测 DDA 算法正确
- [ ] 整数运算无溢出
- [ ] 距离计算精度正确
- [ ] 分级体素结构正确遍历

**集成验证**：
- [ ] 角色不穿透地面
- [ ] 角色不穿透墙壁
- [ ] 跳跃落地物理正确
- [ ] 触发器事件与逻辑同步
- [ ] 大量物理对象不卡顿

### 15.9 相关代码位置

| 功能 | 代码位置 |
|------|----------|
| PhysX 封装 | `common/physics/physx.go` |
| PhysX 类型定义 | `pkg/physics/type.go` |
| 体素碰撞检测 | `common/voxel/physics/collision.go` |
| 体素射线检测 | `common/voxel/physics/raycast.go` |
| 物理工具函数 | `common/voxel/physics/utils.go` |
| 场景物理管理 | `servers/scene_server/internal/ecs/system/physics/` |

---

## 16. 并行测试执行

### 16.1 并行性分析

运行测试前，先分析测试文件的独立性：

| 依赖关系 | 可否并行 | 说明 |
|----------|----------|------|
| 无共享状态 | **可以** | 完全独立，可同时运行 |
| 共享只读资源 | **可以** | 如读取同一配置 |
| 共享可写状态 | **不可以** | 需串行或隔离 |
| 有依赖顺序 | **不可以** | 需按顺序执行 |

### 16.2 使用 subagent 并行测试

当测试文件互相独立时，使用多个 subagent 并行执行：

```
分析测试并行性 → 启动 N 个 Bash subagent → 并行执行测试 → 汇总结果
```

**示例**：3 个独立组件测试
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Bash Agent 1   │     │  Bash Agent 2   │     │  Bash Agent 3   │
│  TradeProxy测试  │     │  Schedule测试    │     │  TownNpc测试    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                          汇总测试结果
```

**优点**：
- 减少总测试时间
- 充分利用多核 CPU
- 失败定位更精确

### 16.3 go test 内置并行

Go 测试框架本身支持并行：

```bash
# 使用 -p 参数指定并行数
go test -p 4 ./...

# 在测试函数中标记可并行
func TestXxx(t *testing.T) {
    t.Parallel()  // 标记此测试可与其他 Parallel 测试并行
    // ...
}
```

### 16.4 测试执行最佳实践

1. **优先使用 subagent 并行**：独立测试文件用不同 subagent 执行
2. **分组执行**：相关测试分组，组内串行，组间并行
3. **快速失败**：使用 `-failfast` 遇到失败立即停止
4. **超时控制**：设置合理超时避免死锁测试阻塞

```bash
# 示例：带超时和快速失败的测试
go test -v -timeout 60s -failfast ./servers/scene_server/internal/ecs/com/cnpc/... -run "TradeProxy"
```

---

## 17. 行为树（BT）测试模式

行为树系统的测试覆盖应包含以下四个维度：

### 17.1 节点注册测试

验证所有行为节点在 `factory.go` 中正确注册，确保 JSON 配置中引用的节点名能被解析。

```go
func TestNodeFactoryRegistration(t *testing.T) {
    // 基础节点
    basicNodes := []string{"Sequence", "Selector", "Log", "Wait", ...}
    // 行为节点（NPC 自然语义）
    behaviorNodes := []string{"ChaseTarget", "StopMoving", "StartDialog", ...}
    // 别名（兼容旧名称）
    aliases := []string{"StartPursuit", "StopPursuit", ...}

    for _, name := range allNodes {
        _, err := factory.CreateNode(name, nil)
        assert.NoError(t, err)
    }
}
```

**新增行为节点时必须同步更新此测试。**

### 17.2 JSON 树配置加载测试

验证所有 `bt/trees/*.json` 文件能被正确加载和解析。

```go
func TestAllJSONFilesValid(t *testing.T) {
    entries, _ := trees.EmbeddedFS.ReadDir(".")
    for _, entry := range entries {
        // 验证 JSON 解析成功、树名非空、根节点存在
    }
}
```

**新增 JSON 树文件时必须确认此测试覆盖到。**

### 17.3 调度名称解析测试

验证 `resolveTreeName(planName, task)` 的映射逻辑：

| planName | TaskType | 期望结果 |
|----------|----------|----------|
| daily_schedule | GSSMain | daily_schedule |
| pursuit | GSSMain | pursuit |
| — | Transition(name="pursuit_to_move_transition") | pursuit_to_move_transition |
| — | GSSEnter | "" |
| — | GSSExit | "" |

### 17.4 树名与注册树匹配测试

验证所有 plan 对应的 JSON 树文件都已嵌入并能正确加载：

```go
func TestResolveTreeName(t *testing.T) {
    planNames := []string{"daily_schedule", "meeting", "dialog", "pursuit", "investigate", ...}
    for _, plan := range planNames {
        jsonFile := plan + ".json"
        data, err := trees.ReadEmbeddedFile(jsonFile)
        assert.NoError(t, err)
    }
}
```

**新增 plan 时必须创建对应的 JSON 树文件并更新此测试。**

### 17.5 测试命令

```bash
# 运行所有 BT 测试
go test -v ./servers/scene_server/internal/common/ai/bt/...

# 运行指定测试
go test -v ./servers/scene_server/internal/common/ai/bt/ -run "TestNodeFactory"
go test -v ./servers/scene_server/internal/common/ai/bt/ -run "TestPhasedTreeNames"
```
