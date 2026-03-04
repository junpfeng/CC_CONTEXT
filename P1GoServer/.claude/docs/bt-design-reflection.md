# 行为树系统设计反思

## 问题陈述

行为树系统从设计到实现经历了完整的 Part 0-6 阶段，但最终系统无法工作：

- **表象**：`BtRunner.trees` 为空，行为树从未被实际使用
- **根因**：场景初始化时没有调用 `RegisterExampleTrees` 或 `RegisterTreesFromConfig`
- **影响**：`Executor.OnPlanCreated` 中的 `btRunner.HasTree()` 始终返回 false，永远回退到原有 Task 逻辑

## 一、思维盲区分析

### 1.1 组件思维 vs 集成思维

**问题**：在设计和实现过程中，过度关注单个组件的正确性，忽视了组件间的连接。

**具体表现**：
- Part 1 实现了 `BtRunner`，验收标准是"能够注册、启动、停止行为树"
- Part 4 实现了 `RegisterExampleTrees`，验收标准是"一个完整可运行的行为树示例"
- Part 6 实现了 `ExecutorResource` 和 `BtTickSystem`，验收标准是"编译通过"

每个 Part 都"通过"了，但没有人负责确保它们被正确连接。

**盲区本质**：把"组件可用"等同于"系统可用"。

### 1.2 假设性验证

**问题**：验证是假设性的，而非实际运行验证。

**具体表现**：
```
设计文档描述的流程：
Scene 创建 → executor.RegisterBehaviorTree(...) → btTickSystem = NewBtTickSystem(...)

实际代码：
Scene 创建 → executorRes = NewExecutorResource(s) → btTickSystem = NewBtTickSystem(...)
                     ↑
                     这里缺少了 RegisterBehaviorTree 调用
```

设计文档（Part 6 的 6.6 执行流程图）清晰描述了注册行为树的步骤，但实现时跳过了这一步，却没有发现问题。

**盲区本质**：信任设计文档的描述，而不是验证实际代码路径。

### 1.3 "编译通过即完成"心态

**问题**：把编译成功当作验收标准。

**具体表现**：
```
Part 4 完成记录：
**编译验证**: `make build APPS='scene_server'` 通过

Part 5 完成记录：
**编译验证**: `make build APPS='scene_server'` 通过

Part 6 验收标准：
- [x] `make build APPS='scene_server'` 编译通过
```

编译通过只能证明语法正确，不能证明逻辑正确。一个从未被调用的函数也能编译通过。

## 二、任务拆分问题

### 2.1 缺少"集成任务"

设计文档将工作分解为：
- Part 1: 核心基础设施（BtContext, BtRunner）
- Part 2: 叶子节点
- Part 3: 系统集成（Executor 修改, BtTickSystem）
- Part 4: 示例与验证
- Part 5: 配置驱动
- Part 6: BtRunner-Executor 集成

**问题**：Part 3 和 Part 6 都叫"集成"，但都只是代码层面的集成（修改 Executor 结构体、创建 BtTickSystem），没有包含"调用集成"任务。

**缺失的任务**：
```
Part 7: 系统启动集成（应该存在但不存在）
- 任务 7.1: 在 scene_impl.go 中调用 RegisterExampleTrees
- 任务 7.2: 端到端测试：创建 NPC → 触发 Plan → 验证行为树执行
- 验收标准: 日志中出现 "[BtTickSystem] tree completed" 字样
```

### 2.2 验收标准的粒度问题

每个 Part 的验收标准都是"单元级别"的：

| Part | 验收标准 | 实际验证范围 |
|------|----------|--------------|
| Part 1 | BtRunner 能注册/启动/停止 | 单元测试 |
| Part 3 | Executor 能判断是否使用行为树 | 代码检查 |
| Part 4 | 行为树示例可运行 | 示例存在 |
| Part 6 | 编译通过 | 语法正确 |

没有一个验收标准是"端到端"级别的：
- 从 GSS Brain 产生 Plan
- 到 Executor 检查行为树
- 到 BtRunner 执行
- 到 BtTickSystem 驱动 Tick
- 到行为树完成触发重评估

### 2.3 Agent 分工的盲区

设计文档描述了双 Agent 并行方案：
- Agent A: 核心框架（BtContext → BtRunner → Executor）
- Agent B: 节点与系统（叶子节点 → BtTickSystem）

**问题**：谁负责"把它们连起来"？

两个 Agent 都完成了自己的任务，但没有 Agent 负责：
1. 在 scene_impl.go 中调用注册函数
2. 验证端到端流程

这是经典的"责任边界"问题：每个 Agent 都认为自己完成了任务，但系统整体不工作。

## 三、验收标准的缺陷

### 3.1 没有"运行时验证"

所有验收标准都是静态的：
- 代码存在
- 编译通过
- 单元测试通过

没有动态验收：
- 启动服务器
- 创建 NPC
- 观察日志
- 验证行为

### 3.2 没有"负面路径"验证

验收标准假设一切正常工作：
- "BtRunner 能够注册行为树" —— 但没有验证"行为树确实被注册了"
- "OnPlanCreated 优先检查行为树" —— 但没有验证"检查的结果是什么"

应该增加的负面验证：
- "当 BtRunner.trees 为空时，系统应该有明确的警告日志"
- "如果 RegisterExampleTrees 未被调用，启动时应该报告 0 棵已注册行为树"

### 3.3 没有"可观测性"设计

系统缺少关键的可观测性：
- 启动时不报告"已注册 N 棵行为树"
- 运行时不报告"当前 N 棵行为树运行中"
- Plan 触发时不报告"行为树命中/未命中"

如果有这些日志，问题会在第一次测试时就被发现。

## 四、根本原因总结

```
                     设计阶段
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
   组件设计完整    接口定义清晰    流程图准确
        │               │               │
        └───────────────┼───────────────┘
                        │
                   实现阶段
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
  Part 1-5 实现    Part 6 实现    验收"通过"
   (组件就绪)     (结构就绪)    (编译成功)
        │               │               │
        └───────────────┴───────────────┘
                        │
                        ▼
            ╔═══════════════════════╗
            ║  缺失的关键步骤：      ║
            ║  调用 Register 函数   ║
            ╚═══════════════════════╝
                        │
                        ▼
                系统无法工作
```

**根本原因**：设计和实现过程中，把"准备好可以被调用"当作"已经被调用"。

## 五、改进建议

### 5.1 强制端到端验收

每个功能的验收标准必须包含端到端测试：
```
验收标准：
- [ ] 静态检查：代码存在、编译通过
- [ ] 单元测试：组件功能正确
- [ ] 集成测试：组件间交互正确
- [ ] 端到端测试：完整用户场景可工作
```

### 5.2 增加"连接任务"

任务拆分时，必须包含明确的"连接任务"：
```
Part X: 组件 A 实现
Part Y: 组件 B 实现
Part Z: 组件 A-B 连接（必须存在）
  - 在启动流程中调用 A
  - 验证 A 的输出被 B 接收
  - 端到端验证
```

### 5.3 可观测性优先

任何新系统必须在设计阶段就定义可观测性：
```go
// 启动时
log.Infof("[BtRunner] initialized, registered_trees=%d", len(r.trees))

// 运行时
log.Infof("[BtRunner] HasTree check, plan=%s, found=%v", planName, found)

// 周期性
log.Infof("[BtTickSystem] status, running_trees=%d", len(runningTrees))
```

### 5.4 "愚蠢问题"清单

在验收前强制回答：
1. 这个函数被谁调用？（不是"应该被谁调用"，而是"实际被谁调用"）
2. 如何证明它在运行？（不是"编译通过"，而是"运行时日志"）
3. 如果它不工作，会有什么症状？（定义预期的失败模式）
4. 如何快速判断它是否工作？（定义健康检查）

### 5.5 "最小可验证系统"原则

在实现完整功能前，先实现最小可验证版本：
```go
// 最小版本：在 scene_impl.go 中
func (s *scene) initNpcAISystemsFromConfig() error {
    // ...existing code...

    if cfg.EnableDecision {
        executorRes := decision.NewExecutorResource(s)
        s.AddResource(executorRes)

        // 最小验证：注册一个测试行为树
        testTree := nodes.NewSequenceNode(
            nodes.NewLogNode("BT TEST: Tree is working!"),
        )
        executorRes.GetExecutor().RegisterBehaviorTree("__test__", testTree)
        log.Infof("[Scene] BT test tree registered")

        // ...rest of code...
    }
}
```

这样在第一次运行时就能发现系统是否真正工作。

## 六、结论

这次失败不是技术能力问题，而是工程流程问题：

1. **设计文档很完整** —— 但实现时遗漏了关键步骤
2. **代码组件都正确** —— 但没有被正确连接
3. **验收标准都通过** —— 但验收标准本身不完整

核心教训：**"可以工作"和"正在工作"之间的差距，需要明确的集成步骤和端到端验证来弥合**。

下次遇到类似的分布式组件系统时，在设计阶段就应该问：
> "这些组件被谁实例化？被谁调用？调用链是什么？如何验证调用链是通的？"

而不是假设"组件存在 = 组件会被使用"。
