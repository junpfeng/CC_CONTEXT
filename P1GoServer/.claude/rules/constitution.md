---
paths:
  - P1GoServer/**
---

# P1GoServer 宪法

以下规则具有最高优先级，任何情况下不得违反。

## 禁止手动编辑的区域

1. `orm/golang/`、`orm/redis/`、`orm/mongo/` — ORM 自动生成代码，修改 `/resources/orm` XML 后执行 `make orm` 重新生成
2. `common/config/cfg_*.go` — 游戏配置自动生成代码，数据源是游戏数据系统

## Git Submodule

3. `base/` — 基础工具库，需在 git2.miao.one 对应仓库修改
4. `resources/proto/` — 协议定义，需在 proto 子仓库修改
