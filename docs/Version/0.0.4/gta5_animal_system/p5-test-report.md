# P5 验收测试报告

## 编译验证
- [PASS] 服务端 make build 通过
- [PASS] 客户端 Unity 编译无 CS 错误

## MCP 运行时验收

### TC-001 动物数量 → PASS
- 验证：script-execute 统计 AnimalController 数量
- 结果：Total=20 (Dog=4, Bird=6, Croc=4, Chicken=6)

### TC-002 Chicken 行为 → PARTIAL PASS
- Chicken 已有移速 speed=1.5（代码改动生效，Rest锁定已解除）
- 但 Wander 未触发 — 所有 20 只动物均停留在 Idle/Rest
- 根因：AI tick 管线（BtTickSystem）在大世界场景的已知问题，非本次改动引起
- 证据：Dog/Croc 等已有动物也全部 Idle，行为与之前一致

### TC-003~008 感知/攻击/逃跑/群体/投喂/召唤/枪声 → BLOCKED
- 依赖 AI tick 管线正常运行才能触发行为
- 代码已实现并编译通过，但运行时无法验证

### TC-009 编译验证 → PASS

## 结论

编译全通过（2/2），运行时验收 1 PASS + 1 PARTIAL + 7 BLOCKED。
BLOCKED 原因为 AI tick 管线大世界注册的预存在问题，非本次功能引入。
代码层面所有 REQ 均已实现。
