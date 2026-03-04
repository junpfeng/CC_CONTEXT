# 策划配置工程

自动生成的游戏配置数据，来自数据系统（策划工具导出）。

## 目录结构

```
config/
  RawTables/          # 策划配置根目录（98 个子目录）
    BTTreeMeta/       # 行为树配置（JSON）
    Data_Item/        # 道具配置（xlsx）
    npc/              # NPC 配置
    localization/     # 多语言翻译（JSON）
    ...               # 其余按功能模块划分
```

## 文件格式

- `.xlsx` — 策划表格，由数据系统导出
- `.json` — 结构化配置（行为树、翻译等）
- `.txt` — 枚举/标志位定义

## 宪法

1. **禁止手动修改** `RawTables/` 下的任何文件，所有数据由数据系统管理
2. 配置变更需通过策划工具导出，再提交到仓库
3. 读取配置的 Go 代码在 `P1GoServer/common/config/cfg_*.go`（同样是自动生成）
4. 如需修改配置结构，联系策划或修改 `tools/generate_tool/` 中的生成器
