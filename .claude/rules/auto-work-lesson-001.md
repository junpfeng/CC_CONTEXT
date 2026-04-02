---
description: 涉及客户端 C# 代码的任务，编码完成后必须验证客户端编译通过
globs:
alwaysApply: true
---

# 跨端任务双端编译验证

## 触发条件
当任务涉及以下任一场景时触发：
- 新增或修改 `freelifeclient/` 下的 .cs 文件
- 修改 Proto 协议并运行代码生成（生成的 C# 代码写入客户端）
- 修改客户端引用的共享配置或接口定义

## 规则内容
1. **编码完成后，必须同时验证服务端和客户端编译**，不能只验证一端
2. 服务端验证：在 `P1GoServer/` 下执行 `go build ./...`
3. 客户端验证：通过 Unity MCP 的 `console-get-logs` 检查编译错误，或通过 hook 自动触发的 Roslyn 检查确认无 CS 错误
4. **编译验证必须在提交 review 之前完成**，不能依赖 review 阶段发现编译错误
5. 常见客户端编译陷阱：
   - `Vector3` 等类型在 `UnityEngine` 和 `System.Numerics` 之间的 CS0104 歧义 — 新建 .cs 文件时显式添加 `using UnityEngine;` 并检查是否需要排除 `System.Numerics`
   - Proto 生成代码引入新命名空间依赖，客户端侧未添加对应 using
   - 接口重构后实现类未同步更新

## 来源
auto-work meta-review #5，基于 0.0.1/NPC_refactor_to_big_world 的工作数据。
7/7 涉客户端任务中 6 个（86%）需要额外编译修复步骤，task-09 单任务编译修复 3 次。
meta-review #2/#3/#4 连续提议此规则但未落地，本次为第 4 次提议后正式创建。
