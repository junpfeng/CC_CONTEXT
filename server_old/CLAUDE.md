# CLAUDE.md

## 项目概述

Rust 旧版游戏服务器，**仅 scene 进程仍在使用**，其余服务已迁移至 P1GoServer。

**技术栈**: Rust 2021, 自定义 ECS (mecs), rapier3d 物理, Recast/Detour 导航, MongoDB, Redis, Protobuf (prost), smol 异步运行时

## 构建

```bash
make scene          # 构建 scene（debug）
make scene -r       # 构建 scene（release）
make clean          # 清理
```

## 目录结构

```
servers/scene/        # ★ 唯一在用的进程
libs/                 # 共享库（mecs, mphysics, navigation-rs, hotdata, mrpc, mnet 等）
common/               # 跨服务共享逻辑
proto/                # Protobuf 生成代码
```

## Scene 服务器

```
servers/scene/src/
├── ecs_app/          # ECS 应用入口
├── ecs_plugin/       # ECS 插件
├── ecs_system/       # ECS 系统
├── scene/            # 场景管理
├── ai/               # AI 系统
├── entity_comp/      # 实体组件（46+ 子目录）
├── entity_func/      # 实体函数
├── entity_trigger/   # 实体触发器
├── movement/         # 移动系统
├── damage/           # 伤害系统
├── crime/            # 犯罪系统
├── interact/         # 交互系统
├── gas/              # 能力系统
├── gm.rs             # GM 命令
└── main.rs           # 入口
```

## 运行时配置

`bin/config.toml` 中 scene 相关：`behavior_tree_dir`, `navmesh_path`, `physics_path`, `waypoint_path`
