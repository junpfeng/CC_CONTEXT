# 工作空间宪法

以下规则具有最高优先级，任何情况下不得违反。

## 产品定位约束

- **目标平台**：手机端。所有实现必须满足手游级别的性能预算（CPU、内存、带宽、发热）
- **联网架构**：Client-Server 架构。服务器为 Go，客户端为 Unity（C#）
- **服务器权威**：游戏状态由服务器裁决，客户端仅负责表现和输入预测，禁止客户端信任本地计算结果

## 禁止手动编辑的区域

以下文件或区域由工具自动生成/管理，禁止手动编辑：

- `P1GoServer/common/proto/` — 协议代码生成产物（由 `old_proto/_tool_new/1.generate.py` 生成）
- `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/` — 客户端协议生成代码
- `freelifeclient/Assets/Scripts/Gameplay/Config/Gen/` — 配置表生成代码
- `P1GoServer/servers/*/internal/service/*_service.go` — 服务接口生成代码

## 跨端一致性

- **协议同步**：修改 Proto 协议后，必须运行 `old_proto/_tool_new/1.generate.py` 同时更新客户端和服务器代码，禁止单端手动修改生成代码
- **命名约定**：网络消息遵循统一命名：`*Req`（请求）、`*Res`（响应）、`*Ntf`（服务端推送）

## 工作流程

1. 提交代码前必须确认构建和测试通过
2. 修改代码前必须查阅对应项目的 `.claude/rules/`，包括其 `constitution.md`
3. 按需加载子工程文档（详见根目录 `CLAUDE.md`）

## 错误处理

- 所有错误必须显式处理，禁止静默忽略（如 Go 的 `_ = err`、C# 的空 `catch`、Python 的裸 `except: pass`）
- 错误日志必须在产生错误的地方打印，不能只返回错误码。Go 用 `log.Errorf`，C# 用 `MLog.Error?.Log`
- 错误向上传播时必须携带上下文信息，便于定位问题根因
- 日志输出必须包含足够的上下文信息（时间、模块、关键参数），便于线上排查

## 代码质量

- 遵循 YAGNI 原则，只实现明确要求的功能。能用简单方案解决的问题，不用复杂设计
- 每个模块/类/函数只做好一件事（单一职责）
- 注释解释"为什么"不是"是什么"
- 只在有明确性能瓶颈时才进行优化，且优化需有数据支撑。热路径（Tick/Update）中需关注分配和 GC
- 新增功能必须附带对应的单元测试或集成测试
- 删除代码时同步删除相关测试，不留死代码

## 安全规则

- 密钥、Token、密码等敏感信息禁止硬编码，必须通过环境变量或密钥管理服务获取
- `.env`、`credentials.json` 等敏感文件必须加入 `.gitignore`，禁止提交到仓库
- 第三方依赖引入前需确认其安全性和维护状态，避免引入已知漏洞的版本
- 数据库查询必须使用参数化查询，禁止拼接 SQL

## 子工程索引

| 工程 | CLAUDE.md | Rules 路径 | 说明 |
|------|-----------|-----------|------|
| P1GoServer | `P1GoServer/CLAUDE.md` | `P1GoServer/.claude/rules/` | Go 分布式游戏服务器（活跃） |
| freelifeclient | `freelifeclient/CLAUDE.md` | `freelifeclient/.claude/rules/` | Unity 游戏客户端（活跃） |
