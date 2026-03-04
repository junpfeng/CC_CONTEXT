## 工程关系模型

调试时需要明确 bug 所属的工程，不同工程的日志位置、构建方式、代码规范各不相同。

```
workspace/server/                    ← 工作目录（CWD）
├── P1GoServer/                      ← 业务工程（Go 游戏服务器）
│   ├── servers/                        各微服务代码
│   ├── common/                         共享库
│   ├── common/config/                  游戏配置（从配置工程生成）
│   ├── resources/proto/                协议生成的代码（git submodule）
│   ├── bin/log/                        主日志目录（glog）
│   ├── log/err/                        stderr 输出（ERROR 级别）
│   ├── log/out/                        stdout 输出（全量镜像）
│   └── .claude/rules/                  项目级 Rules
│
├── server_old/                      ← Rust 遗留工程（仅供参考，不修改）
│
├── proto/old_proto/                 ← 协议工程（Protocol Buffer 定义）
│   ├── scene/                          场景协议
│   ├── logic/                          逻辑协议
│   └── module.proto                    模块定义
│
└── config/RawTables/                ← 配置工程（游戏配置表 Excel/JSON）
    ├── TownTask/                       任务配置
    ├── TownNpc/                        NPC 配置
    └── ...                             其他配置表
```

### 工程与 Bug 类型的对应关系

| 工程 | 路径 | 典型 Bug | 日志/构建 |
|------|------|----------|-----------|
| 业务工程 | `P1GoServer/` | 运行时 panic、逻辑错误、性能问题 | 日志：`P1GoServer/bin/log/`，构建：`make build/test` |
| 协议工程 | `proto/old_proto/` | 消息字段不匹配、序列化错误 | 需重新 protoc 生成 |
| 配置工程 | `config/RawTables/` | 配置值异常、加载失败 | 需重新运行配置生成工具 |
| Rust 遗留 | `server_old/` | 仅用于对比参考历史实现 | 不修改、不构建 |

### 调试路径规则

- **代码修改**：只在 `P1GoServer/` 中修改，除非 bug 根因在协议/配置工程
- **日志查看**：始终在 `P1GoServer/bin/log/` 下查看，参照 `DEBUG.md` 的进程列表
- **Rules 遵守**：修改 `P1GoServer/` 代码时，必须遵守 `P1GoServer/.claude/rules/` 下的规范
- **跨工程 bug**：明确标注 bug 涉及哪些工程，修复时按工程分别处理
