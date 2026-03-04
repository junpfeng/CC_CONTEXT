---
name: todo
description: 扫描代码中的 TODO/FIXME 注释并管理
---

# TODO 管理助手

当用户调用此 skill 时，帮助管理代码中的 TODO 注释。

## 功能

### 1. 扫描 TODO

扫描代码中的标记注释：
- `TODO`: 待办事项
- `FIXME`: 需要修复的问题
- `HACK`: 临时解决方案
- `XXX`: 需要注意的地方
- `BUG`: 已知 Bug
- `OPTIMIZE`: 待优化

### 2. 输出格式

```markdown
## TODO 列表

### 统计
- TODO: X 个
- FIXME: Y 个
- HACK: Z 个

### 详细列表

#### TODO
| 文件 | 行号 | 内容 | 作者 | 日期 |
|------|------|------|------|------|
| file.go | 123 | 实现缓存功能 | - | - |

#### FIXME (高优先级)
| 文件 | 行号 | 内容 |
|------|------|------|
| file.go | 456 | 修复并发问题 |

#### HACK
| 文件 | 行号 | 内容 |
|------|------|------|
| file.go | 789 | 临时绕过验证 |
```

### 3. TODO 规范

推荐的 TODO 格式：
```go
// TODO(author): 描述待办事项 [可选截止日期]
// TODO(zhangsan): 添加单元测试 [2024-03-01]

// FIXME(author): 描述需要修复的问题
// FIXME: 这里有内存泄漏问题

// HACK: 临时方案，等待上游修复
// XXX: 注意这个边界条件
```

## 使用方式

- `/todo` - 扫描所有 TODO
- `/todo path/to/dir` - 扫描指定目录
- `/todo --fixme` - 只显示 FIXME
- `/todo --stats` - 只显示统计
