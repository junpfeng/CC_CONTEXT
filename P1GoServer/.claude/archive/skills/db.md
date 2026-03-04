---
name: db
description: 数据库设计、迁移和查询优化
---

# 数据库助手

当用户调用此 skill 时，帮助进行数据库相关的工作。

## 功能

### 1. 表结构设计

#### 设计原则
- 遵循第三范式，适当反范式化
- 合理使用索引
- 选择合适的数据类型
- 考虑未来扩展

#### Go 模型定义
```go
type User struct {
    ID        int64          `gorm:"primaryKey;autoIncrement"`
    UUID      string         `gorm:"type:varchar(36);uniqueIndex;not null"`
    Name      string         `gorm:"type:varchar(100);not null"`
    Email     string         `gorm:"type:varchar(255);uniqueIndex;not null"`
    Phone     string         `gorm:"type:varchar(20);index"`
    Status    int8           `gorm:"type:tinyint;default:1;index"`
    Extra     datatypes.JSON `gorm:"type:json"`
    CreatedAt time.Time      `gorm:"autoCreateTime"`
    UpdatedAt time.Time      `gorm:"autoUpdateTime"`
    DeletedAt gorm.DeletedAt `gorm:"index"`
}

func (User) TableName() string {
    return "users"
}
```

#### SQL 建表语句
```sql
CREATE TABLE `users` (
    `id` bigint NOT NULL AUTO_INCREMENT,
    `uuid` varchar(36) NOT NULL,
    `name` varchar(100) NOT NULL,
    `email` varchar(255) NOT NULL,
    `phone` varchar(20) DEFAULT NULL,
    `status` tinyint DEFAULT 1,
    `extra` json DEFAULT NULL,
    `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at` datetime DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_uuid` (`uuid`),
    UNIQUE KEY `idx_email` (`email`),
    KEY `idx_phone` (`phone`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 2. 迁移管理

```go
// 使用 golang-migrate
// migrations/000001_create_users_table.up.sql
// migrations/000001_create_users_table.down.sql

// 或使用 GORM AutoMigrate
db.AutoMigrate(&User{}, &Order{})
```

### 3. 查询优化

#### 索引分析
```sql
-- 查看查询执行计划
EXPLAIN SELECT * FROM users WHERE email = 'test@example.com';

-- 查看索引使用情况
SHOW INDEX FROM users;
```

#### 常见优化
```go
// 避免 SELECT *
db.Select("id", "name", "email").Find(&users)

// 使用索引字段
db.Where("email = ?", email).First(&user)

// 批量操作
db.CreateInBatches(users, 100)

// 预加载关联
db.Preload("Orders").Find(&users)

// 使用原生 SQL 复杂查询
db.Raw("SELECT ... FROM ... WHERE ...").Scan(&results)
```

### 4. 连接池配置

```go
sqlDB, _ := db.DB()

// 最大空闲连接数
sqlDB.SetMaxIdleConns(10)

// 最大打开连接数
sqlDB.SetMaxOpenConns(100)

// 连接最大生命周期
sqlDB.SetConnMaxLifetime(time.Hour)
```

### 5. 事务处理

```go
err := db.Transaction(func(tx *gorm.DB) error {
    if err := tx.Create(&user).Error; err != nil {
        return err
    }
    if err := tx.Create(&order).Error; err != nil {
        return err
    }
    return nil
})
```

## 输出格式

```markdown
## 数据库设计

### 表结构
| 字段 | 类型 | 说明 | 索引 |
|------|------|------|------|
| id | bigint | 主键 | PK |

### 索引设计
| 索引名 | 字段 | 类型 | 说明 |
|--------|------|------|------|

### 关系图
[ER 图描述]

### 查询示例
```sql
-- 常用查询
```
```

## 使用方式

- `/db design` - 交互式设计数据库表
- `/db model User` - 生成模型代码
- `/db migrate` - 生成迁移文件
- `/db optimize` - 分析和优化查询
