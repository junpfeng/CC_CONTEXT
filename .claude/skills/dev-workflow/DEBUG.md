# 调试指南

## 1. 日志系统

### 1.1 日志目录

| 路径 | 说明 |
|------|------|
| `P1GoServer/bin/log/` | **主日志目录**，各进程的 glog 日志 |
| `P1GoServer/log/err/` | 各进程的 stderr 输出（仅 ERROR 级别） |
| `P1GoServer/log/out/` | 各进程的 stdout 输出（全量镜像） |

### 1.2 日志文件命名

日志文件格式：`{进程名}.INFO.{时间戳}.{pid}.log`

每个进程有一个符号链接指向最新的日志文件：
```
scene.INFO.log -> scene.INFO.20260217-115633.670288.log
```

### 1.3 进程列表

| 进程名 | 服务 | 说明 |
|--------|------|------|
| `scene` | scene_server | **最常用**，NPC 行为、ECS 系统、BT 行为树 |
| `logic` | logic_server | 核心游戏逻辑 |
| `db` | db_server | 数据库层 |
| `manager` | manager_server | 场景/世界管理 |
| `chat` | chat_server | 聊天和语音 |
| `relation` | relation_server | 玩家关系 |
| `match` | match_server | 匹配系统 |
| `login` | login_server | 认证 |

### 1.4 日志格式

```
{级别}{日期} {时间} [{源文件}:{行号}] {模块}|{场景ID}|{内容}
```

示例：
```
I0217 12:47:12.096057 [behavior_nodes.go:163] scene|[MoveBehavior] fast path: pathfind already completed, entity_id=20
E0216 23:43:42.998239 [npc_update.go:40] Scene|3|[townNpcUpdateSystem] timeMgr not found
```

级别前缀：
- `I` = INFO
- `W` = WARNING
- `E` = ERROR
- `F` = FATAL

### 1.5 err/out 日志

`log/err/` 和 `log/out/` 使用轮转命名：
```
scene_server.log      ← 最新
scene_server.log.1    ← 次新
scene_server.log.2
...
```

## 2. 日志查看方法

### 2.1 基本原则

日志文件通常非常大（单个文件可达 ~100万行）。**默认只需关注最新日志文件的最后 1000 行**。

### 2.2 查看最新日志

```bash
# 查看 scene_server 最新 INFO 日志（最常用）
tail -1000 P1GoServer/bin/log/scene.INFO.log

# 查看 scene_server 最新 ERROR（从 err 目录）
tail -1000 P1GoServer/log/err/scene_server.log

# 查看其他进程
tail -1000 P1GoServer/bin/log/logic.INFO.log
tail -1000 P1GoServer/bin/log/db.INFO.log
```

### 2.3 搜索特定错误

```bash
# 在最新日志中搜索错误关键字
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep -i "error\|warning\|failed"

# 按 entity_id 过滤
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "entity_id=20"

# 按模块过滤（如行为树）
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "\[MoveBehavior\]\|\[IdleBehavior\]\|\[SelectorNode\]"

# 按场景 ID 过滤
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "Scene|3|"
```

### 2.4 实时跟踪

```bash
# 实时跟踪 scene 日志
tail -f P1GoServer/bin/log/scene.INFO.log

# 实时跟踪并过滤
tail -f P1GoServer/bin/log/scene.INFO.log | grep "BtTickSystem\|Executor"
```

## 3. 常见调试场景

### 3.1 NPC 行为异常

重点关注：
```bash
# BT 行为树日志
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "Behavior\|SelectorNode\|abort"

# AI 决策日志
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "Executor\|BT started\|tree completed"

# 日程切换
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "schedule changed\|meeting"
```

### 3.2 Resource/System 未注册

当看到 `xxx not found` 错误时：
1. 确认该 Resource/System 在哪些场景类型中注册（`scene_impl.go` 的 `initResource` / `initAllSystems`）
2. 确认报错的场景类型是否在注册范围内
3. 确认初始化顺序是否正确（System 依赖的 Resource 必须先注册）

### 3.3 寻路/移动问题

```bash
# 路网寻路错误
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "FindPath\|roadNetwork\|NavMesh"

# 移动组件状态
tail -1000 P1GoServer/bin/log/scene.INFO.log | grep "StopMove\|SetMove\|pathfind"
```

## 4. Claude Code 中的日志查看

在 Claude Code 会话中调试时：

```bash
# 推荐：用 Bash 工具查看最近日志
tail -1000 P1GoServer/bin/log/scene.INFO.log

# 不推荐：用 Read 工具读取整个日志文件（文件过大）
# 不推荐：用 Grep 工具搜索整个日志目录（结果过多）
```

如果需要搜索历史日志，先确定时间范围，再针对具体文件搜索：
```bash
# 找到对应时间的日志文件
ls -lt P1GoServer/bin/log/scene.INFO.* | head -5

# 在特定文件中搜索
tail -1000 P1GoServer/bin/log/scene.INFO.20260216-xxxx.log | grep "关键字"
```
