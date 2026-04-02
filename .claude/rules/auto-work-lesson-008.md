---
description: Override 组件生命周期方法时，必须检查基类是否有非空实现并调用 base.Method()
globs:
alwaysApply: true
---

# Override 生命周期方法必须调用 base

## 触发条件
当编写或修改以下方法的 override 时触发：
- `OnRemove()` / `OnClear()` / `OnInit()` / `OnExit()` / `OnDisable()` / `OnDestroy()`
- 任何组件系统（Comp、State、Handler）中继承自基类的生命周期方法

## 规则内容
1. **编写 override 后，立即 grep 基类**：找到基类对应方法，确认是否有非空实现（非 `{ }` 空体）
2. **有实现必须调用 base**：若基类方法有逻辑（哪怕只有一行），override 中必须显式调用 `base.XXX()`
3. **调用位置规范**：
   - `OnInit` / `OnEnable`：base 调用在**方法开头**（先初始化基类）
   - `OnRemove` / `OnClear` / `OnDisable` / `OnDestroy`：base 调用在**方法末尾**（先清理子类，再清理基类）
4. **扫描命令**（编码完成后对新增/修改的 .cs 文件执行）：
   ```
   grep -n "override.*OnRemove\|override.*OnClear\|override.*OnInit\|override.*OnExit" <file.cs>
   ```
   对每个命中行，检查方法体是否包含对应 `base.` 调用

## 来源
auto-work meta-review #6，基于 0.0.3/V2_NPC task-06 的工作数据。
task-06 HIGH-2：`OnRemove()` override 缺少 `base.OnRemove()` 调用，导致基类资产句柄未释放（泄漏）。
属机械性遗漏，可通过编码后扫描完全避免。
