---
name: changelog
description: 生成变更日志和版本发布说明
---

# 变更日志助手

当用户调用此 skill 时，帮助生成变更日志。

## 变更日志格式

遵循 [Keep a Changelog](https://keepachangelog.com/) 规范：

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 新功能描述

### Changed
- 变更描述

### Deprecated
- 即将废弃的功能

### Removed
- 已移除的功能

### Fixed
- 修复的 Bug

### Security
- 安全相关更新

## [1.0.0] - 2024-01-15

### Added
- 初始发布
- 用户认证功能
- 基础 CRUD 操作

[Unreleased]: https://github.com/user/repo/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/user/repo/releases/tag/v1.0.0
```

## 分类说明

| 分类 | 描述 | 示例 |
|------|------|------|
| Added | 新增功能 | 添加用户登录功能 |
| Changed | 功能变更 | 优化查询性能 |
| Deprecated | 即将废弃 | v1 API 将在下版本移除 |
| Removed | 已移除 | 移除旧版配置支持 |
| Fixed | Bug 修复 | 修复登录超时问题 |
| Security | 安全更新 | 修复 XSS 漏洞 |

## 自动生成流程

### 1. 从 Git 提交生成

```bash
# 获取自上次发布以来的提交
git log v1.0.0..HEAD --oneline --pretty=format:"%s"
```

分析提交信息：
- `feat:` → Added
- `fix:` → Fixed
- `chore:` → Changed
- `docs:` → Changed
- `refactor:` → Changed
- `perf:` → Changed
- `security:` → Security

### 2. 版本发布说明

```markdown
# Release v1.1.0

## Highlights

- **新增用户管理功能**: 支持用户的增删改查
- **性能优化**: 查询速度提升 50%

## Breaking Changes

- API 端点 `/api/users` 重命名为 `/api/v2/users`

## Upgrade Guide

1. 更新配置文件中的 API 端点
2. 运行数据库迁移: `go run cmd/migrate/main.go`

## Full Changelog

### Added
- 用户管理 API (#123)
- 批量导入功能 (#124)

### Changed
- 优化数据库查询 (#125)

### Fixed
- 修复登录问题 (#126)

## Contributors

- @developer1
- @developer2
```

## 语义化版本

| 版本变更 | 何时使用 |
|---------|---------|
| Major (X.0.0) | 不兼容的 API 变更 |
| Minor (0.X.0) | 向后兼容的新功能 |
| Patch (0.0.X) | 向后兼容的 Bug 修复 |

## 使用方式

- `/changelog` - 生成自上次发布以来的变更日志
- `/changelog v1.0.0..v1.1.0` - 生成指定版本间的变更
- `/changelog release` - 生成发布说明
