---
description: 检查武器配置完整性（资源路径、ID引用、字段合法性）
argument-hint: [--fix 自动修复可修复的错误]
---

## 任务

运行武器配置验证脚本，检查所有武器 JSON 配置的完整性和正确性。

## 工作流程

### 第一步：运行验证脚本

运行以下命令获取 JSON 格式的检查结果：

```bash
cd E:/gta/Projects && python3 Tools/check_weapon_config.py --json
```

### 第二步：分析结果

解析脚本输出的 JSON 结果，将问题分为三类：

**A. 配置路径错误（可自动修复）**
- `model 不存在` — 配件 prefab 路径与实际文件不匹配
- `prefab 不存在` — 武器 prefab 路径错误
- `recoil_config 不存在` / `diffusion_config 不存在` — 弹道配置路径错误

**B. 资源缺失（需美术/策划处理）**
- prefab 文件确实不存在（对应目录下无任何同名文件）
- icon 图片不存在
- explosion_vfx 特效不存在

**C. 数据问题（需策划确认）**
- ID 引用断裂（template/default/item 不匹配）
- 字段值异常（damage=0, fire_rate=0 等）

### 第三步：处理错误

#### 对于 A 类（路径错误）：

1. 用 Glob 搜索实际存在的资源文件：
   ```
   Glob: E:/gta/Projects/freelifeclient/Assets/PackResources/{目录}/*
   ```
2. 找到正确文件名后，修改 `appendix.json` / `guns.json` / `throwables.json` 中的路径
3. 修改后重新运行验证脚本确认修复

如果用户传入了 `--fix` 参数，自动执行修复流程。否则只展示报告，让用户决定。

#### 对于 B 类（资源缺失）：

列出缺失资源清单，提示用户通知美术制作或 SVN 更新。不做自动修复。

#### 对于 C 类（数据问题）：

列出异常数据，提示用户确认是否为设计意图。

### 第四步：输出报告

```
## 武器配置检查报告

### 配置错误（已修复 / 待修复）
- [文件] [配件/武器名]: 旧路径 → 新路径

### 资源缺失（需美术处理）
- [文件路径]: 对应配件/武器

### 数据异常（需确认）
- [说明]

### 总结
X 个错误, Y 个警告
已修复 N 个, 待处理 M 个
```

## 验证脚本说明

脚本位置: `Tools/check_weapon_config.py`

检查范围:
- `RawTables/Weapon/json/guns.json` — 枪械配置
- `RawTables/Weapon/json/melee.json` — 近战配置
- `RawTables/Weapon/json/throwables.json` — 投掷物配置
- `RawTables/Weapon/json/appendix.json` — 配件配置
- `RawTables/Weapon/recoil/*.json` — 后坐力配置
- `RawTables/Weapon/diffusion/*.json` — 散射配置
- `Assets/PackResources/Prefab/Weapon/` — 武器 prefab 资源

检查项:
1. JSON 语法合法性
2. 所有 prefab/icon/vfx 资源路径指向实际存在的文件
3. appendix template → default → item 的 ID 交叉引用完整
4. guns/melee/throwables 的 appendix_template_id 和 default_appendix_id 在 appendix.json 中存在
5. 枚举字段值合法（slot_type, weapon_type, fire_type, fire_mode, detonation_type）
6. 数值字段范围合理（fire_rate, base_damage > 0）
7. recoil_config 和 diffusion_config 文件存在
