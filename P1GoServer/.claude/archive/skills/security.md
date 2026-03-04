---
name: security
description: 安全审查，检测代码中的安全漏洞
---

# 安全审查助手

当用户调用此 skill 时，对代码进行安全审查。

## 审查清单

### 1. 输入验证

- [ ] 所有用户输入都经过验证
- [ ] 参数边界检查
- [ ] 类型验证
- [ ] 格式验证（邮箱、URL、手机号等）

```go
// 不安全
func handler(input string) {
    query := "SELECT * FROM users WHERE id = " + input
}

// 安全
func handler(input string) {
    id, err := strconv.Atoi(input)
    if err != nil || id < 0 {
        return errors.New("invalid id")
    }
    query := "SELECT * FROM users WHERE id = ?"
    db.Query(query, id)
}
```

### 2. SQL 注入防护

- [ ] 使用参数化查询
- [ ] 使用 ORM 提供的安全方法
- [ ] 避免字符串拼接 SQL

### 3. 认证与授权

- [ ] 密码正确加密存储（bcrypt/argon2）
- [ ] Session/Token 安全管理
- [ ] 权限检查完整
- [ ] 敏感操作需要重新认证

### 4. 敏感数据处理

- [ ] 敏感数据加密存储
- [ ] 日志中不记录敏感信息
- [ ] 传输层使用 HTTPS
- [ ] 密钥安全管理

```go
// 不安全
log.Printf("User login: %s, password: %s", user, password)

// 安全
log.Printf("User login: %s", user)
```

### 5. 错误处理

- [ ] 不向用户暴露内部错误详情
- [ ] 错误信息不包含敏感信息
- [ ] 统一的错误响应格式

```go
// 不安全
return fmt.Errorf("database error: %v", err)

// 安全
log.Errorf("database error: %v", err)
return errors.New("internal server error")
```

### 6. 并发安全

- [ ] 共享资源正确加锁
- [ ] 避免 race condition
- [ ] Channel 安全使用

### 7. 依赖安全

```bash
# 检查依赖漏洞
go list -m all | nancy sleuth
govulncheck ./...
```

### 8. 常见漏洞

| 漏洞类型 | 检查点 |
|---------|--------|
| XSS | HTML 转义、CSP 头 |
| CSRF | Token 验证 |
| SSRF | URL 白名单验证 |
| 路径遍历 | 文件路径验证 |
| 命令注入 | 避免 shell 调用 |

## 输出格式

```markdown
## 安全审查报告

### 扫描范围
- 文件数: X
- 代码行数: Y

### 发现的问题

#### 高危 (Critical)
- [ ] 问题描述 (文件:行号)
  - 风险: 描述风险
  - 修复: 修复建议

#### 中危 (Medium)
- [ ] 问题描述 (文件:行号)

#### 低危 (Low)
- [ ] 问题描述 (文件:行号)

### 安全建议
1. 建议1
2. 建议2

### 总结
[整体安全状况评估]
```

## 使用方式

- `/security` - 审查当前变更
- `/security path/to/file.go` - 审查指定文件
- `/security --full` - 全面安全审查
