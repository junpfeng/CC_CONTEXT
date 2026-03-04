# 反外挂检测与标记封号系统 — 任务清单

## Rust 工程 (server_old/)

### 基础设施
- [ ] [TASK-001] 新增 `anti_cheat/` 模块骨架（mod.rs + types.rs）
- [ ] [TASK-002] 新增 `MoveValidateComp` ECS 组件并注册
- [ ] [TASK-003] 实现 `cheat_reporter.rs`（异常累积 + Redis 批量上报）

### 移动检测
- [ ] [TASK-004] 实现 `move_validator.rs`（速度/瞬移/飞天检测）
- [ ] [TASK-005] 在 `person_move()` 中接入移动校验

### 射速检测
- [ ] [TASK-006] 扩展 `CheckManager`（新增 fire rate 追踪字段 + check_fire_rate 方法）
- [ ] [TASK-007] 在 `handle_shot_data()` 中接入射速校验

### 系统集成
- [ ] [TASK-008] 注册 CheatReporter Resource + flush System 到 Scene tick

## Go 工程 (P1GoServer/)

- [ ] [TASK-101] 新增 `cheat_review.go`（Redis 消费 + MongoDB 存储 + GM 审核接口）
- [ ] [TASK-102] 在 `gm_handler.go` 中注册路由，对接 BanUser

## 配置

- [ ] [TASK-201] 新增反外挂阈值配置（Rust 侧 TOML 或常量模块）

## 任务依赖

```
TASK-001 → TASK-002 → TASK-004 → TASK-005
TASK-001 → TASK-003 → TASK-005
                     → TASK-007
TASK-006 → TASK-007
TASK-005 + TASK-007 → TASK-008
TASK-008 → TASK-101 → TASK-102
TASK-201 → TASK-004, TASK-006
```

## 并行策略

**可并行组1（无依赖）：**
- TASK-001 + TASK-201

**可并行组2（依赖组1）：**
- TASK-002 + TASK-003 + TASK-006

**可并行组3（依赖组2）：**
- TASK-004 + TASK-007（不同文件）

**串行：**
- TASK-005 → TASK-008 → TASK-101 → TASK-102
