# Phase 7：经验沉淀

> 领域依赖：按经验类型 Read 对应文档后追加内容

## 沉淀分类

| 经验类型 | 目标文档 |
|----------|----------|
| 编码规范 | `P1GoServer/.claude/rules/` |
| 数据库 | `DB.md` |
| 协议 | `PROTO.md` |
| 测试 | `TEST.md` |
| 审查 | `REVIEW.md` |
| 配置 | `CONFIG.md` |
| 架构约定 | `P1GoServer/CLAUDE.md` |
| Agent 优化 | Agent Memory |

## 流程

1. 识别经验类型 → 匹配目标文档 → Edit 追加 → 验证一致性
2. 询问用户：是否有需记录的经验？需新增/修改 Rules？需更新辅助文档？

## 自动沉淀提醒

| 触发条件 | 建议沉淀到 |
|----------|-----------|
| 新 DB 存储限制 | `DB.md` Section 9 |
| 新客户端请求接口 | `PROTO.md`（客户端请求限制） |
| 新测试技巧/工具 | `TEST.md` |
| 新审查检查项 | `REVIEW.md` |
| 配置部署变更 | `CONFIG.md` |
| 重复编码问题 | `P1GoServer/.claude/rules/` |
| 新架构约定 | `P1GoServer/CLAUDE.md` |

---

## 历史案例

### 协议工程修改规范

详细规范已整合到 `PROTO.md`（Edit 优于 Write、生成脚本选择、不同步排查、子模块操作）。

### 场景隔离模式

复用现有系统为新场景时的标准模式（6 步）：

1. 添加场景类型枚举
2. 添加行为控制字段（enableXxx bool + sceneType）
3. 提供场景专用构造函数
4. 在 scene_impl.go switch 分支中初始化
5. 行为代码中用条件字段分支隔离
6. 协议同步用 sceneType 填充对应字段

**审查清单**：构造函数设置正确、初始化在正确 switch 分支、行为分支正确、协议填充正确、存储方法独立、原场景回归测试。
