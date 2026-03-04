# 代码审查规范

本文档集中描述 dev-workflow 中的代码审查规范、检查清单和验证要点。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 审查 Agent 说明（Section 1） | Phase 2 设计审查、Phase 6 产出审查 |
| 代码质量检查（Section 2-4） | Phase 6 代码审查 |
| 安全性审查（Section 5） | Phase 6 安全审查 |
| 限制检查（Section 6-7） | Phase 6 容量审查、上线前检查 |
| 序列化检查（Section 8） | Phase 6 协议审查 |
| 游戏专项检查（Section 9） | Phase 6 业务审查 |
| 快速检查清单（Section 11） | 上线前快速验证 |

### 相关文档

| 文档 | 用途 |
|------|------|
| `DB.md` | 数据库限制详情（Section 7 引用） |
| `PROTO.md` | 客户端请求限制详情（Section 6 引用） |
| `TEST.md` | 测试覆盖评估标准 |
| `SKILL.md` | Phase 7 经验沉淀（审查相关经验沉淀到本文档） |

---

## 1. 审查概述

### 1.1 审查时机

| 阶段 | 审查内容 |
|------|----------|
| Phase 4 实现后 | 代码质量、编码规范 |
| Phase 6 产出审查 | 全面审查（功能完整性、安全性、事务性、测试覆盖） |
| 上线前 | 容量限制、序列化检查、压测结果 |

### 1.2 审查 Agent

dev-workflow 使用以下专用 Agent：

| Agent | 职责 | 使用阶段 | 关注重点 |
|-------|------|----------|----------|
| `dev-workflow-design-reviewer` | 设计方案审查 | **Phase 2** | 架构合理性、协议设计、DB 设计 |
| `dev-workflow-code-reviewer` | 代码质量审查 | Phase 6 | Rules 合规、编码规范、代码风格 |
| `dev-workflow-security-reviewer` | 安全性审查 | Phase 6 | 注入、凭证泄露、越权访问 |
| `dev-workflow-transaction-reviewer` | 事务性审查 | Phase 6 | 事务边界、回滚、幂等、并发 |
| `dev-workflow-test-designer` | 测试覆盖评估 | Phase 6 | 测试充分性、边界用例 |

> **注意**：`dev-workflow-design-reviewer` 在 Phase 2 设计阶段使用，其余 4 个 Agent 在 Phase 6 产出审查时并行执行。

---

## 2. Rules 合规检查

审查代码是否符合 `P1GoServer/.claude/rules/` 目录下的项目规范。

### 2.1 代码风格规范 (go-style.md)

| 检查项 | 规范要求 |
|--------|----------|
| 文件命名 | 小写加下划线（如 `player_manager.go`） |
| 函数/变量命名 | 驼峰命名（如 `getUserInfo`） |
| 公开导出 | 大驼峰（如 `GetUserInfo`） |
| 常量命名 | 大写下划线（如 `MAX_PLAYER_COUNT`） |

### 2.2 自动生成代码

以下文件/目录为自动生成，**禁止手动修改**：

| 路径模式 | 说明 |
|----------|------|
| `common/config/cfg_*.go` | 游戏配置代码 |
| `*_pb.go` | Protobuf 生成代码 |
| `common/proto/scene_service.go` | RPC 服务代码 |
| `common/proto/scene_client.go` | RPC 客户端代码 |
| `servers/scene_server/internal/common/message_cache.go` | 消息缓存 |
| `servers/scene_server/internal/net_func/server_func.go` | 服务函数 |
| `servers/scene_server/internal/service/scene_service.go` | 场景服务 |

### 2.3 其他规范文件

| 规范文件 | 检查重点 |
|----------|----------|
| `development-workflow.md` | 开发流程规范 |
| `behavior-tree.md` | 行为树节点实现规范 |
| `ai-decision.md` | AI 决策系统实现规范 |
| `ecs-architecture.md` | ECS 架构规范 |
| `executor-system.md` | 执行器系统规范 |
| `sensor-system.md` | 感知器系统规范 |
| `npc-component.md` | NPC 组件规范 |
| `logging.md` | 日志规范 |

---

## 3. 代码质量检查

### 3.1 基础检查清单

| 检查项 | 说明 |
|--------|------|
| 错误处理 | 不忽略错误（除非明确说明原因） |
| 错误包装 | 使用 wrap 包装错误上下文 |
| 资源释放 | 使用 defer 关闭资源（文件、连接等） |
| Context 使用 | 合理使用 context 控制超时 |
| 并发安全 | 共享变量必须加锁 |
| defer 解锁 | 使用 defer 释放锁 |
| 锁持有时间 | 避免锁持有时间过长 |

### 3.2 构建和测试

```bash
# 构建验证
make build              # 构建所有服务器
make scene_server       # 构建场景服务器

# 代码检查
make lint               # golangci-lint 检查
make fmt                # 代码格式化

# 测试验证
make test               # 运行所有测试
```

---

## 4. 事务性代码审查

### 4.1 检查清单

| 检查项 | 审查内容 |
|--------|----------|
| **验证顺序** | 是否先完成所有验证再执行状态变更？ |
| **回滚机制** | 失败路径是否正确回滚所有已变更的状态？ |
| **锁的使用** | 锁是否正确获取和释放？是否使用 defer？ |
| **并发安全** | 共享数据访问是否有竞态条件？ |
| **幂等实现** | 幂等键生成和检查逻辑是否正确？ |
| **超时处理** | 是否设置合理的超时？超时后是否正确处理？ |
| **日志记录** | 关键操作是否有足够的日志用于追踪？ |
| **错误处理** | 错误是否正确传播？是否有静默失败？ |
| **资源泄漏** | 是否有未释放的锁、未关闭的连接？ |

### 4.2 事务性代码规范

#### 先验证后执行

```go
// 正确：先验证
if !canDeduct(player, cost) { return ErrInsufficientFunds }
if !hasSpace(player.Bag) { return ErrBagFull }
// 验证通过后再执行
player.DeductMoney(cost)
player.Bag.AddItem(item)
```

#### 保存快照用于回滚

```go
snapshot := entity.Snapshot()
defer func() {
    if err != nil { entity.Restore(snapshot) }
}()
```

#### 使用 defer 确保清理

```go
lock.Lock()
defer lock.Unlock()
```

#### 跨服务调用使用请求ID

```go
reqID := uuid.New().String()
resp, err := rpcClient.Call(ctx, reqID, req)
```

#### 记录关键操作日志

```go
log.Info("transaction_start", "player_id", pid, "action", "trade", "req_id", reqID)
// ... 执行操作
log.Info("transaction_end", "player_id", pid, "action", "trade", "req_id", reqID, "result", "success")
```

---

## 5. 安全性审查

### 5.1 检查清单

| 检查项 | 审查内容 |
|--------|----------|
| **注入攻击** | 输入是否经过验证和清理？ |
| **凭证泄露** | 是否有敏感信息硬编码或日志输出？ |
| **越权访问** | 是否正确验证用户权限？ |
| **资源访问** | 是否检查资源所有权？ |
| **跨服务边界** | RPC 调用是否验证调用方身份？ |
| **配置安全** | 敏感配置是否使用环境变量或加密存储？ |

### 5.2 常见安全问题

| 问题类型 | 检查要点 |
|----------|----------|
| SQL/NoSQL 注入 | 查询参数是否使用参数化查询 |
| 命令注入 | 系统命令是否使用安全的执行方式 |
| 路径遍历 | 文件路径是否验证和规范化 |
| 整数溢出 | 数值运算是否检查边界 |
| 空指针 | 指针使用前是否判空 |

---

## 6. 客户端请求限制检查

验证实现是否遵循客户端请求限制规范（详见 `PROTO.md`）。

### 6.1 频率限制

| 分类 | 限制项 | 值 | 位置 |
|------|--------|-----|------|
| 聊天 | 消息频率 | 1000条/分钟 | `servers/logic_server/internal/domain/mgr/func_chat.go:23` |
| 关注 | 操作间隔 | 500ms | `servers/relation_server/internal/domain/rate_limiter.go:23` |
| 事件 | 处理间隔 | 100ms | `servers/scene_server/internal/ecs/system/sensor/event_sensor.go:25` |

### 6.2 数量限制

| 分类 | 限制项 | 值 |
|------|--------|-----|
| 关注 | 最大关注人数 | 200 人 |
| 方案 | 个人布局方案数 | 10 个 |
| 衣服 | 衣服部件列表 | 1-100 个 |
| 混合 | 单次混合数量 | 10 个 |
| 留言 | 置顶留言数 | 3 条 |

### 6.3 容量限制

| 分类 | 限制项 | 值 |
|------|--------|-----|
| 聊天 | 公共频道消息 | 10,000 条 |
| 聊天 | 私聊消息 | 1,000 条 |
| 事件 | 事件队列 | 1,000 个 |
| GAS | 上下文容量 | 100 个 |

### 6.4 冷却/超时

| 分类 | 限制项 | 值 |
|------|--------|-----|
| 交易 | 交易冷却 | 1 分钟 |
| 警察 | 逮捕冷却 | 2 秒 |
| 对话 | 对话超时 | 60 秒 |
| 聊天 | 私聊保留 | 30 天 |
| 登录 | 最大重试 | 2 次 |

### 6.5 数值限制

| 分类 | 限制项 | 值 | 位置 |
|------|--------|-----|------|
| 好感度 | 最大好感度 | 100 | `servers/scene_server/internal/ecs/res/town_contact/town_contact.go:43` |

### 6.6 审查要点

- [ ] 新增 RPC/HTTP 接口是否定义了调用频率限制？
- [ ] 数组/列表类数据是否定义了容量上限？
- [ ] 资源消耗型操作是否定义了合理的冷却时间？
- [ ] 超时处理是否正确（超时后状态是否回滚）？
- [ ] 数值类数据是否定义了上下限（如好感度 0-100）？
- [ ] 批量操作接口是否有单次数量上限？

---

## 7. 数据库容量限制检查

验证实现是否遵循数据库存储限制（详见 `DB.md` Section 9）。

### 7.1 MongoDB 限制

| 限制项 | 限制值 | 审查要点 |
|--------|--------|----------|
| 单文档大小 | **16 MB** | 数组字段是否可能无限增长？ |
| 字段名长度 | 128 字节 | 字段命名是否过长？ |
| 嵌套深度 | 100 层 | 嵌套结构是否过深？ |
| 索引数量 | 64 个/集合 | 是否添加过多索引？ |

### 7.2 Redis 限制

| 限制项 | 限制值 | 审查要点 |
|--------|--------|----------|
| 缓存 TTL | **7 天** | 数据访问频率是否足够？ |
| 单 Key 大小 | 512 MB | 缓存数据是否过大？ |

### 7.3 db_server 限制

| 限制项 | 限制值 | 定义位置 |
|--------|--------|----------|
| 表数量上限 | 256 | `servers/db_server/internal/data/types.go:13` |
| 单次查询字段数 | 100 | `servers/db_server/internal/data/types.go:18` |
| 内存缓存写超时 | 1800 秒 | `servers/db_server/internal/data/types.go:15` |
| 内存缓存读超时 | 1800 秒 | `servers/db_server/internal/data/types.go:16` |

### 7.4 审查要点

- [ ] 新增数组字段是否有容量上限？
- [ ] 文档大小是否可能超过 16MB？
- [ ] 嵌套结构是否合理？
- [ ] 索引设计是否合理？
- [ ] 缓存策略是否正确？

---

## 8. 序列化检查

验证数据在各层之间的序列化和反序列化是否正确。

### 8.1 存储格式映射

| 位置 | 格式 | 说明 |
|------|------|------|
| 业务进程内存 | Go struct | 带 `bson`/`json` tag |
| RPC 传输 | Protobuf bytes | `proto.Marshal()` 序列化 |
| db_server 内存 | `[]byte` | Row.Data 字段 |
| Redis | `[]byte` | Protobuf 二进制 |
| MongoDB | BSON 文档 | 字段名由 `bson` tag 决定 |

### 8.2 序列化检查清单

| 检查项 | 审查内容 |
|--------|----------|
| **Protobuf 定义** | 消息字段是否有正确的类型和编号？ |
| **BSON Tag** | Go struct 是否有正确的 `bson` tag？ |
| **JSON Tag** | 需要 JSON 序列化的字段是否有 `json` tag？ |
| **字段兼容性** | 新增字段是否向后兼容（optional/repeated）？ |
| **枚举值** | 枚举值是否保持稳定，不能随意修改？ |
| **默认值** | 零值/默认值是否符合预期？ |

### 8.3 常见序列化问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 字段丢失 | 缺少 `bson` tag | 添加正确的 tag |
| 反序列化失败 | Protobuf 字段编号变更 | 不要修改已有字段编号 |
| 数据不一致 | BSON/JSON tag 名称不匹配 | 统一命名规范 |
| 枚举解析错误 | 枚举值变更 | 保持枚举值稳定，只追加不修改 |
| Proto3 零值丢失 | `LoadFromData` 中 `!= 0` 守卫跳过合法的 index 0 | 移除 `!= 0` 守卫，或使用语义保证（字段值域不包含 0） |

### 8.4 审查要点

- [ ] 新增 Protobuf 消息是否正确定义？
- [ ] Go struct 是否有正确的序列化 tag？
- [ ] 字段变更是否向后兼容？
- [ ] 枚举值是否稳定？

---

## 9. 游戏服务器专项检查

### 9.1 ECS 架构检查

> 规范参考：`P1GoServer/.claude/rules/ecs-architecture.md`

| 检查项 | 审查内容 |
|--------|----------|
| 组件隔离 | 组件是否只包含数据，不包含逻辑？ |
| 系统职责 | 系统是否只处理特定组件组合？ |
| 资源管理 | 资源是否正确初始化和释放？ |
| 实体生命周期 | 实体创建/销毁是否正确处理？ |

### 9.2 NPC 系统检查

> 规范参考：`P1GoServer/.claude/rules/npc-component.md`、`P1GoServer/.claude/rules/ai-decision.md`、`P1GoServer/.claude/rules/behavior-tree.md`

| 检查项 | 审查内容 |
|--------|----------|
| AI 决策 | 决策逻辑是否正确实现？ |
| 行为树 | 节点是否正确注册和执行？ |
| 状态同步 | NPC 状态是否正确同步到客户端？ |
| 数据存盘 | NPC 数据是否正确保存和加载？ |

### 9.2.1 行为等价性审查（重构/迁移专用）

当将硬编码逻辑迁移到行为树节点时，必须逐一对比新旧代码的行为等价性：

| 检查项 | 审查内容 |
|--------|----------|
| 操作步骤顺序 | 新代码的组件操作顺序是否与原始代码一致？ |
| 参数值一致 | 传入组件方法的参数值是否完全一致？（特别注意类型转换） |
| 组件获取方式 | 新代码是否获取了原始代码中使用的所有组件？ |
| 失败路径 | 组件获取失败时的行为是否等价？（原始 return vs 新代码 BtNodeStatusFailed） |
| 日志级别 | 新代码的日志级别是否与原始代码一致？（Warning vs Debug） |
| Feature 操作 | Feature 的读取和更新是否与原始代码一致？ |
| 超时设置 | 超时计算逻辑是否等价？ |

**审查方法**：将原始 handler 函数与对应行为节点的 OnEnter 逐行对比，制作等价性对照表。

**经验教训（BT 重构案例）**：
- 日志级别容易从 `Scene.Warningf` 降级为 `log.Debugf`，需特别注意
- `updateFeature` 的静默失败（decisionComp == nil 时无日志）容易被忽视
- resolveTreeName 未命中时应考虑是否需要回退到硬编码 executeTask

### 9.2.2 AttributeSet 使用审查

| 检查项 | 审查内容 |
|--------|----------|
| **SetValue 返回值** | 所有 `AttributeSet.SetValue()` 调用是否检查返回值？未检查 = 静默失败 |
| **Initialize 兜底** | SetValue 返回 false 时是否用 `Initialize()` 兜底创建条目？ |
| **HasAttribute 前置** | 批量读取前是否确认 key 已初始化？`GetValue` 对不存在的 key 返回 0.0 |
| **LoadProto 覆盖范围** | `LoadProto` 只初始化 DB 中存在的 key，首次创建的属性不会在 DB 中 |

**典型错误模式**（武器轮盘修复案例）：
```go
// 错误：bulletIdKey 可能未被 LoadProto 初始化，SetValue 静默返回 false
weapon.AttributeSet.SetValue(bulletIdKey, float64(bid))

// 正确：检查返回值，失败时 Initialize
if !weapon.AttributeSet.SetValue(bulletIdKey, float64(bid)) {
    weapon.AttributeSet.Initialize(bulletIdKey, float64(bid))
}
```

### 9.2.3 包循环依赖检查

当新增跨包调用时，检查是否引入循环依赖：

| 检查项 | 审查内容 |
|--------|----------|
| **import 链路** | A→B→A 形成循环？Go 编译器会报错，但设计时应提前规避 |
| **解决方案选择** | 单点使用→内联到调用方；多点复用→提取到独立包打破循环 |

### 9.3 场景系统检查

> 规范参考：`P1GoServer/.claude/rules/sensor-system.md`、`P1GoServer/.claude/rules/executor-system.md`

| 检查项 | 审查内容 |
|--------|----------|
| 场景隔离 | 不同场景类型是否正确隔离？ |
| 玩家管理 | 玩家进入/离开是否正确处理？ |
| 协议填充 | 同步协议是否填充正确的字段？ |
| 状态机 | 场景状态转换是否正确？ |

### 9.4 交易系统检查

> 规范参考：Section 4 事务性代码审查

| 检查项 | 审查内容 |
|--------|----------|
| 事务完整性 | 交易是否原子执行？ |
| 物品转移 | 物品是否正确转移所有权？ |
| 货币处理 | 货币扣除/增加是否正确？ |
| 回滚机制 | 交易失败是否正确回滚？ |

---

## 10. 综合审查流程

### 10.1 Phase 6 审查步骤

**第一步：并行 Agent 审查**

同时启动 4 个 subagent 审查实际代码产出（参考 Section 1.2 Agent 列表）：

1. `dev-workflow-code-reviewer`：审查代码质量、Rules 合规
2. `dev-workflow-security-reviewer`：审查安全性
3. `dev-workflow-transaction-reviewer`：审查事务性实现
4. `dev-workflow-test-designer`：评估测试覆盖（参考 `TEST.md`）

**第二步：综合审查**

1. 阅读设计方案，提取所有功能点和验收标准
2. 分工程运行 `git diff` 查看所有改动
3. 逐项核对：每个功能点是否已实现
4. 协议检查：协议定义是否与设计一致
5. 配置检查：配置项是否与设计一致
6. DB 检查：表结构、索引、Migration 是否与设计一致
7. 事务性检查：事务边界、回滚、幂等是否正确
8. 跨工程集成检查：工程间数据流是否正确
9. 运行构建和测试：确认通过
10. 汇总所有 subagent 审查结果

### 10.2 审查报告模板

```markdown
## 审查报告

### 基本信息
- 功能名称：[name]
- 审查时间：[date]
- 审查人：[reviewer]

### 功能完整性核对

| 功能点 | 状态 | 备注 |
|--------|------|------|
| [功能1] | ✅/❌ | |
| [功能2] | ✅/❌ | |

### 代码质量审查

| 检查项 | 状态 | 问题描述 |
|--------|------|----------|
| Rules 合规 | ✅/❌ | |
| 错误处理 | ✅/❌ | |
| 并发安全 | ✅/❌ | |

### 安全性审查

| 检查项 | 状态 | 问题描述 |
|--------|------|----------|
| 注入攻击 | ✅/❌ | |
| 越权访问 | ✅/❌ | |
| 凭证泄露 | ✅/❌ | |

### 事务性审查

| 检查项 | 状态 | 问题描述 |
|--------|------|----------|
| 验证顺序 | ✅/❌ | |
| 回滚机制 | ✅/❌ | |
| 幂等实现 | ✅/❌ | |

### 容量限制检查

| 检查项 | 状态 | 问题描述 |
|--------|------|----------|
| 请求频率 | ✅/❌ | |
| 数据容量 | ✅/❌ | |
| DB 限制 | ✅/❌ | |

### 序列化检查

| 检查项 | 状态 | 问题描述 |
|--------|------|----------|
| Protobuf | ✅/❌ | |
| BSON Tag | ✅/❌ | |
| 兼容性 | ✅/❌ | |

### 测试覆盖

> 测试标准参考 `TEST.md`

| 测试类型 | 状态 | 覆盖率 |
|----------|------|--------|
| 单元测试 | ✅/❌ | |
| 集成测试 | ✅/❌ | |
| 边界测试 | ✅/❌ | |

### 问题汇总

| 序号 | 严重程度 | 问题描述 | 修复建议 |
|------|----------|----------|----------|
| 1 | 高/中/低 | | |

### 结论

- [ ] 通过审查，可以上线
- [ ] 需要修复后重新审查
- [ ] 需要重大修改，不建议上线
```

---

## 11. 快速检查清单

上线前快速检查，确保关键项目都已验证。

### 11.1 必检项目

- [ ] `make build` 构建通过
- [ ] `make test` 测试通过
- [ ] `make lint` 无错误
- [ ] 新增请求有频率限制
- [ ] 数组字段有容量上限
- [ ] 文档大小不会超过 16MB
- [ ] 序列化 tag 正确
- [ ] 事务操作有回滚机制
- [ ] 敏感操作有日志记录
- [ ] 无安全漏洞

### 11.2 相关文档

| 文档 | 路径 | 用途 |
|------|------|------|
| PROTO.md | `.claude/skills/dev-workflow/PROTO.md` | 客户端请求限制详情 |
| DB.md | `.claude/skills/dev-workflow/DB.md` | 数据库架构和限制详情 |
| TEST.md | `.claude/skills/dev-workflow/TEST.md` | 测试规范和验证清单 |
| Rules | `P1GoServer/.claude/rules/*.md` | 项目编码规范 |
