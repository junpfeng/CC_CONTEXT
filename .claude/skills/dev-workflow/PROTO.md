# 协议工程规范

本文档包含协议工程修改规范和客户端请求限制。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 协议工程修改规范 | Phase 2 协议设计、Phase 4 实现 |
| 客户端请求限制 | Phase 4 实现、Phase 6 审查 |

### 相关文档

| 文档 | 用途 |
|------|------|
| `DB.md` | 数据库架构和存储限制 |
| `TEST.md` | 测试规范和验证清单 |
| `REVIEW.md` | 代码审查规范 |
| `SKILL.md` | Phase 7 经验沉淀（协议相关经验沉淀到本文档） |

---

# 第一部分：协议工程修改规范

## 1. 工程位置和结构

### 1.1 协议工程路径

| 工程 | 默认路径 | 说明 |
|------|----------|------|
| 协议工程 | `proto/old_proto/` | Protocol Buffer 定义文件 |
| 生成产物 | `resources/proto/` | 协议生成的代码（git submodule） |

### 1.2 目录结构

```
workspace/server/
├── P1GoServer/                ← 业务工程
│   ├── resources/proto/       ← 协议生成产物（git submodule）
│   └── common/proto/          ← 生成的 Go 代码
│
└── proto/old_proto/           ← 协议工程
    ├── scene/
    │   └── xxx.proto          ← 协议定义源文件
    ├── logic/
    └── module.proto           ← 模块定义
```

---

## 2. 修改 .proto 文件规范

### 2.1 使用 Edit 工具而非 Write 工具

**问题**：使用 Write 工具修改 `.proto` 文件时，可能意外删除大量已有内容。

**原因**：Write 工具会完全覆盖文件内容，如果读取不完整或遗漏部分内容，会导致数据丢失。

**正确做法**：
```
1. 先用 Read 工具完整读取目标文件
2. 使用 Edit 工具精确添加/修改内容
3. 修改后用 git diff 验证变更范围
```

**错误示例**：
```
❌ 直接用 Write 覆盖整个 proto 文件
```

**正确示例**：
```
✅ 用 Edit 工具只添加新的 message 定义：
   old_string: "message LastMessage {\n...\n}"
   new_string: "message LastMessage {\n...\n}\n\nmessage NewMessage {\n...\n}"
```

### 2.2 Protobuf 字段规范

| 规范 | 说明 |
|------|------|
| 字段编号 | 已有字段编号不可修改，只能追加新编号 |
| 字段类型 | 类型变更需要考虑兼容性 |
| 枚举值 | 枚举值保持稳定，只追加不修改 |
| 保留字段 | 使用 `reserved` 标记废弃字段 |

---

## 3. 协议生成脚本

### 3.1 脚本选择

| 操作系统 | 生成脚本 |
|---------|----------|
| Windows | `1.generate.py` |
| Linux/WSL | `1.generate_linux.py` |

### 3.2 执行命令

```bash
# 进入工具目录并执行生成脚本
cd P1GoServer/resources/proto/_tool_new && python3 1.generate_linux.py
```

### 3.3 验证生成结果

```bash
# 检查生成的代码变更
cd P1GoServer && git diff common/proto/
```

---

## 4. 协议/代码不同步排查

### 4.1 常见现象

构建时出现 proto 相关的编译错误：
```
undefined: proto.XxxMessage
```

### 4.2 常见原因

1. 协议工程未拉取最新代码
2. 业务工程未拉取最新代码
3. 协议生成后未更新 git submodule
4. 生成脚本执行失败但未注意错误输出

### 4.3 排查步骤

```bash
# 1. 检查协议工程状态
cd proto/old_proto && git status && git pull

# 2. 检查业务工程子模块状态
cd P1GoServer && git submodule status resources/proto

# 3. 重新生成协议
cd P1GoServer/resources/proto/_tool_new && python3 1.generate_linux.py

# 4. 验证生成结果
cd P1GoServer && git diff common/proto/
```

---

## 5. 子模块操作

### 5.1 撤销子模块修改

```bash
# 方法1：撤销子模块内所有修改
cd P1GoServer/resources/proto && git restore .

# 方法2：从主项目目录执行
cd P1GoServer && git submodule update --force resources/proto
```

### 5.2 更新子模块到最新

```bash
cd P1GoServer/resources/proto && git pull origin master
cd ../..
git add resources/proto
git commit -m "chore: update proto submodule"
```

---

# 第二部分：客户端请求限制

本部分记录服务器对客户端请求的业务层限制。

> **审查提醒**：在 Phase 6 审查或代码 Review 时，需要检查新增的客户端请求是否定义了频率限制。如果没有，应提醒开发者添加相应的限制，防止客户端滥用接口。
>
> 检查要点：
> - 新增 RPC/HTTP 接口是否有调用频率限制？
> - 批量操作接口是否有单次数量上限？
> - 资源消耗型接口是否有冷却时间？

---

## 6. 聊天系统

### 频率限制

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 聊天消息频率 | 60秒内最多 **1000 条** | `servers/logic_server/internal/domain/mgr/func_chat.go:23` |

### 消息容量限制

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 公共频道消息历史 | **10,000 条** | `servers/chat_server/internal/common/consts.go:5` |
| 私聊频道消息历史 | **1,000 条** | `servers/chat_server/internal/common/consts.go:6` |
| 私聊消息保留时间 | **30 天** | `servers/chat_server/internal/common/consts.go:11` |

### 内容限制

| 限制项 | 说明 | 位置 |
|--------|------|------|
| 聊天消息内容 | 非空、非纯空格 | `servers/logic_server/internal/domain/mgr/func_chat.go:51-54` |

---

## 7. 关注系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 最大关注人数 | **200 人** | `servers/relation_server/internal/common/consts.go:4` |
| 单个关注槽位 | **200 人** | `servers/relation_server/internal/common/consts.go:5` |

### 频率限制

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 操作间隔 | **500 毫秒** | `servers/relation_server/internal/domain/rate_limiter.go:23` |
| 限制过期时间 | **60 分钟** | `servers/relation_server/internal/domain/rate_limiter.go:22` |

---

## 8. BBS 留言板

### 内容限制

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 置顶留言数 | **3 条** | `servers/sns_server/internal/domain/bbs_handler.go:16` |
| 留言内容 | 非空 | `servers/sns_server/internal/domain/bbs_handler.go:47` |

---

## 9. 队伍系统

| 限制项 | 来源 | 说明 |
|--------|------|------|
| 最大队伍成员数 | `common/config/cfg_teamtemplate.go` | 配置驱动，读取 `maxMemberNum` 字段 |
| 邀请有效期 | `common/config/cfg_teamtemplate.go` | 配置驱动 |
| 申请有效期 | `common/config/cfg_teamtemplate.go` | 配置驱动 |

---

## 10. 交易系统

### 冷却时间

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 交易成功后冷却 | **1 分钟** | `servers/scene_server/internal/ecs/system/decision/decision.go:23` |
| 警察逮捕冷却 | **2,000 毫秒** | `servers/scene_server/internal/ecs/com/cpolice/police_comp.go:102` |

### 好感度限制

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 最大好感度 | **100** | `servers/scene_server/internal/ecs/res/town_contact/town_contact.go:43` |

#### 好感度等级

| 等级 | 好感度范围 |
|------|----------|
| Stranger | 0-19 |
| General Stranger | 20-39 |
| Neutral | 40-59 |
| Friendly | 60-79 |
| Loyal | 80-100 |

---

## 11. 樱花校园系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 个人布局方案数 | **10 个** | `servers/scene_server/internal/net_func/sakura/workshop.go:72` |
| 衣服部件列表 | **1-100 个** | `servers/scene_server/internal/net_func/sakura/clothes.go:23` |

---

## 12. 混合台系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 单次混合最大数 | **10 个** | `servers/scene_server/internal/net_func/object/town_mix.go:19` |

---

## 13. 事件系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 事件队列最大长度 | **1,000 个** | `servers/scene_server/internal/ecs/system/sensor/event_sensor.go:26` |
| 事件处理间隔 | **100 毫秒** | `servers/scene_server/internal/ecs/system/sensor/event_sensor.go:25` |

---

## 14. GAS 系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 上下文最大容量 | **100 个** | `servers/scene_server/internal/ecs/com/cgas/gas.go:17` |

---

## 15. 登录系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 最大重试次数 | **2 次** | `servers/login_server/internal/domain/types.go:7` |
| 队列清理间隔 | **30 秒** | `servers/login_server/internal/domain/types.go:10` |

---

## 16. 对话系统

| 限制项 | 值 | 位置 |
|--------|-----|------|
| 对话超时 | **60 秒** | `servers/scene_server/internal/ecs/com/cdialog/dialog.go:59` |

---

## 17. 背包系统

配置来源：`common/config/cfg_backpackinit.go`

| 限制项 | 字段 | 说明 |
|--------|------|------|
| 背包容量 | `maxSize` | 配置驱动，不同背包类型容量不同 |
| 背包显示容量 | `showMaxSize` | UI 显示用 |
| 速度影响上限 | `speedSizeUpper` | 超过此重量开始影响速度 |
| 负重速度下限 | `speedLower` | 最低速度百分比 |

---

## 18. 小镇等级

配置来源：`common/config/cfg_townlevel.go`

| 限制项 | 字段 | 说明 |
|--------|------|------|
| 升级需要经验 | `upNeedExp` | 各等级升级所需经验值 |
| 订单还价倍率 | `orderBudget` | 影响订单价格计算 |

---

## 核心限制速查表

| 分类 | 限制项 | 值 |
|------|--------|-----|
| **频率** | 聊天消息 | 1000条/分钟 |
| **频率** | 关注操作间隔 | 500ms |
| **数量** | 最大关注人数 | 200 人 |
| **数量** | 队伍成员数 | 配置驱动 |
| **数量** | 个人方案数 | 10 个 |
| **数量** | 衣服部件 | 1-100 个 |
| **数量** | 单次混合数 | 10 个 |
| **数量** | 置顶留言 | 3 条 |
| **容量** | 公共频道消息 | 10,000 条 |
| **容量** | 私聊消息 | 1,000 条 |
| **容量** | 事件队列 | 1,000 个 |
| **容量** | GAS上下文 | 100 个 |
| **冷却** | 交易冷却 | 1 分钟 |
| **冷却** | 逮捕冷却 | 2 秒 |
| **超时** | 对话超时 | 60 秒 |
| **超时** | 私聊保留 | 30 天 |
| **重试** | 登录重试 | 2 次 |
| **数值** | 最大好感度 | 100 |
