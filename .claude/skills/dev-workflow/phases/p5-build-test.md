# Phase 5：构建与测试

> 领域依赖（按需 Read）：`TEST.md`（测试规范）、`DEBUG.md`（日志排查）

## 构建验证

```bash
cd P1GoServer && make build
cd P1GoServer && make lint
cd P1GoServer && make fmt
```

## 测试执行

按 `TEST.md` 规范执行：单元测试（`make test`）→ 集成测试 → Migration 测试 → 回归测试。

## 验证清单

- [ ] `make build` 构建通过
- [ ] `make lint` 无错误
- [ ] `make test` 测试通过
- [ ] Migration 本地测试通过
- [ ] 协议生成代码已更新
- [ ] 配置生成代码已更新

**全部通过后，等待用户确认进入 Phase 6。**
