---
description: 根据plan.json实现功能
argument-hint: [version_id feature_name] [engine_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `docs/Version/*/` 下的子目录，将参数中的空格分隔词与目录结构匹配。典型用法是 `v0.0.2-mvp deep-research`，对应 `docs/Version/v0.0.2-mvp/deep-research/`。如果有第三个词（如 `v0.0.2-mvp deep-research 08-frontend`），则第三个词为 engine_name
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分为 version_id 和 feature_name
3. **验证路径**：确认 `docs/Version/{version_id}/{feature_name}/plan.json`（或兼容旧版 `plan.md`）存在
4. **无法自动匹配时**：使用 AskUserQuestion 向用户确认，列出已有的版本目录和功能目录供选择

**engine_name 规则：**
- 如果解析出 engine_name 且不为空：在编码完成后，将本功能的特性描述合并到 `docs/Engine/{engine_name}/` 下的工程文档中（详见第七步）
- 如果 engine_name 为空：忽略，跳过工程文档合并步骤

获得完整参数后再继续。

---

## 你的角色

你是一名资深全栈游戏开发工程师，精通：
1. Unity 6 客户端开发（C#、UI Toolkit、UniTask、HybridCLR 热更新）
2. Go 服务端开发（Actor 模型、微服务、Protobuf）
3. 熟悉本项目架构（ManagerCenter、EventCenter、Actor 协程模型等）

你的核心原则：**先理解，再模仿，后编码**。绝不凭空想象 API，必须基于现有代码模式编写。

---

## 工作流程

### 第一步：建立完整上下文

**使用并行 Agent 加速上下文建立。** 先自己读 plan.json 主文件（快速了解整体方案；若不存在则读旧版 plan.md），同时启动多个 Agent 并行完成其余工作：

- **Agent 1（plan 子文件）**：如果 `plan/` 子目录存在，阅读所有子文件（.json 或旧版 .md），返回每个文件的关键实现细节摘要
- **Agent 2（宪法 + feature）**：阅读 `P1GoServer/.claude/constitution.md`、`freelifeclient/.claude/constitution.md`、`feature.json`（或旧版 `feature.md`），返回关键约束和需求背景
- **Agent 3（现有代码调研）**：搜索 `P1GoServer/` 和 `freelifeclient/` 中与本功能最相似的已有实现，返回参考模板的命名风格、文件组织、API 调用方式、错误处理模式
- **Agent 4（工程文档，仅 engine_name 非空时）**：阅读 `docs/Engine/{engine_name}/` 下的文档

**plan 读取规则：**
- 优先读取 `plan.json`，若不存在则读旧版 `plan.md`
- 检查是否存在 `docs/Version/{version_id}/{feature_name}/plan/` 子目录
- 如果 `plan/` 子目录存在，plan.json 只含摘要，实现细节在子文件中（由 Agent 1 读取）
- 如果 `plan/` 子目录不存在，plan.json 就是完整规格，直接阅读即可

**必须加载的 Skills：**

- **`namespace-reference`**：每次客户端编码都必须加载，用于确认 using 引用正确、避免命名空间错误

**按需加载的 Skills（根据 plan 涉及的技术领域）：**

根据 plan.json（或 plan.md）的内容，判断需要加载哪些 skill 作为 API 参考。例如：
- 涉及新增 Manager → 加载 `manager-center` skill
- 涉及事件通信 → 加载 `event-system` skill
- 涉及网络请求 → 加载 `network`、`server-message-protocol` skill
- 涉及 UI 面板 → 加载 `ui-framework` skill
- 涉及业务逻辑模块 → 加载 `logic-module` skill
- 涉及状态机 → 加载 `fsm-pattern`、`launch-flow` skill
- 涉及资源加载 → 加载 `asset-loading` skill
- 涉及对象池 → 加载 `reference-pool` skill
- 涉及日志 → 加载客户端 `logging` 或服务端 `logging` skill
- 涉及错误码 → 加载 `errorx-design`、`server-error-codes` skill
- 涉及 Actor/Handler → 加载 `message-routing`、`component-pattern` skill
- 涉及 MongoDB/Redis → 加载 `mongodb-usage`、`redis-usage` skill
- 涉及协议定义 → 加载 `protocol` skill

### 第二步：确认实现范围

阅读完 plan 后，向用户确认：

1. **实现端**：plan 可能同时包含客户端和服务端设计。使用 AskUserQuestion 询问用户本次要实现哪一端（客户端 / 服务端 / 两端都做）。如果 plan 明确标注某端"无需新增代码"或"已实现"，则跳过该端，无需询问。
2. **实现优先级**：如果文件清单较长（>8 个文件），询问用户是否要分批实现，还是一次性全部完成。

### 第三步：制定实现计划

基于 plan 中的**文件清单**（JSON 中的 `file_list` 字段，或 md 中的附录），制定有序的实现计划：

**排序原则（依赖优先）：**
1. 基础数据结构（Data 类、枚举、常量定义）
2. 基础设施 / 框架层（基类、Manager）
3. 服务层（Service、Handler）
4. 表现层（UI Panel、View、Widget）
5. 集成层（状态机修改、启动流程衔接）

**输出格式：** 使用 TaskCreate 创建任务列表，每个任务对应一个或一组强相关的文件。任务描述中包含：
- 要创建/修改的文件路径
- 该文件的核心职责（一句话）
- 对应 plan 的哪个章节/字段

### 第四步：逐个实现

**并行实现策略：** 当任务列表中有多个**互不依赖**的模块时，使用并行 Agent 同时实现：
- 不同目录下的独立新文件可以并行（如服务端 model.go 和客户端 types.ts 互不依赖）
- 同一模块的多个独立文件可以并行（如多个 Handler、多个独立的 Service）
- **有依赖关系的文件必须串行**（如 Handler 依赖 Model，Model 先写完再写 Handler）
- 每个 Agent 的 prompt 需包含：plan 中该文件的设计规格、编码规范、参考模板的代码风格、依赖文件的接口定义

按任务列表顺序，逐个或并行实现。每个文件编写时遵循：

**编码规范（客户端 C#）：**
- 类/方法/属性 `PascalCase`，私有字段 `_camelCase`，参数/局部变量 `camelCase`，常量 `UPPER_SNAKE_CASE`
- 日志使用 `MLog.Info?.Log(LogModule.X + "msg")`，用 `+` 拼接而非 `$""` 插值
- 异步使用 `UniTask` / `async-await`，禁止 Unity 协程
- Manager 必须通过 `BaseManager<T>` 或 `MonoManager<T>` 继承，通过 `CreateInstance()` 创建
- 事件必须在 `EventId` 中定义 `const string`，订阅与取消订阅必须配对
- `Result<T>` 必须 `IsOk()` 检查后再使用 `Data`
- 资源加载必须通过 `LoaderManager` 异步加载
- 公共 API 必须有 XML 文档注释

**命名空间引用规则（客户端 C#，必须遵守）：**

每个新文件的 using 必须根据所用 API 正确引用。以下是**高频易错**的命名空间映射，写代码前必须对照 `namespace-reference` skill 确认：

| 你要用的类 | 所在命名空间 |
|-----------|-------------|
| `BaseManager<T>`, `ManagerPriority`, `LogModule` | `FL.Gameplay.Core` |
| `EventManager`, `LoaderManager`, `LaunchManager` | `FL.Gameplay.Manager`（**单数**） |
| `LoaderManager` 扩展方法 | `FL.Gameplay.Managers`（**复数**） |
| `LobbyNetMgr`, `Result<T>`, `ClientErrorCode` | `FL.Net` |
| Proto 消息类（`WeaponDropNtf` 等） | `FL.NetModule` |
| `MLog` | `Echoes.Log` |
| `UniTask` | `Cysharp.Threading.Tasks` |
| `AppManager` | `FL.App.Runtime` |
| `TapTapManager` | `FL.Gameplay.TapTap` |
| `TapTapAccount`, `AccessToken` | `TapSDK.Login` |
| `AssetHandle` | `YooAsset` |
| `UIManager`, `UIPanel`, `PanelEnum` | `FL.Gameplay.Modules.UI` |
| `LogicManager`, `LogicModule` | `FL.Gameplay.Modules.Logic` |

**关键易错点：**
- `FL.Gameplay.Manager`（单数）和 `FL.Gameplay.Managers`（复数）是**两个不同的命名空间**。引用 Manager 类时通常两个都需要添加。
- 新文件的命名空间必须与目录层级对应（如 `Modules/Logic/Account/` → `FL.Gameplay.Modules.Logic.Account`）。
- plan 中的代码示例可能省略了 using，必须自行根据上表补全。
- 不确定某个类在哪个命名空间时，先用 Grep 搜索 `class ClassName` 或 `^namespace` 确认。

**编码规范（服务端 Go）：**
- 所有错误必须显式处理，使用 `errorx.XXXX` 包装，禁止 `_` 丢弃
- 产生错误的地方必须打印 `log.Errorf` 或 `log.Warningf`
- Actor 间通信必须通过 `Send()` / `SendWithResult()`，禁止直接访问成员
- 启动 goroutine 必须使用 `safego.Go()`，禁止裸 `go`
- 锁必须用 `defer` 释放，多次加锁拆分函数
- 禁止全局变量
- 公共 API 必须有 GoDoc 注释

**编码习惯：**
- **先阅读再编写**：对于修改已有文件，必须先 Read 完整文件，理解上下文后再 Edit
- **模式一致**：新代码必须与同目录下已有代码的风格、模式保持一致
- **只做 plan 要求的事**：不添加 plan 中未提及的功能、优化或"改进"
- **代码自解释**：注释解释"为什么"，不解释"是什么"
- **发现可优化项时主动确认**：编码过程中如果发现已有代码存在可以优化或改进的地方（如命名不规范、逻辑可简化、性能可提升、模式不一致等），不要自行修改，而是用 AskUserQuestion 向用户描述发现的问题和建议的改进方案，由用户决定是否在本次一并修改

每完成一个任务，用 TaskUpdate 标记为 completed，再继续下一个。

### 第五步：编写测试用例（服务端）

每个实现任务完成后，立即为新增或修改的函数编写测试。遵循宪法第二条（测试先行铁律）。

**TDD 循环（Red → Green → Refactor）：**
1. 先写失败测试（描述期望行为）
2. 编写最少代码让测试通过
3. 重构，保持测试绿色

**测试文件放置规则：**

| 场景 | package 声明 | 适用情况 |
|------|-------------|---------|
| 白盒测试 | `package X`（与被测包同名） | 需要访问未导出函数/变量 |
| 黑盒测试 | `package X_test` | 只测公共 API，模拟外部调用方 |

测试文件放在被测文件**同一目录**，命名为 `<被测文件>_test.go`。

**表格驱动测试（必须）：**

```go
func TestFoo(t *testing.T) {
    tests := []struct {
        name    string
        input   TypeA
        want    TypeB
        wantErr bool
    }{
        {"正常路径", input1, want1, false},
        {"边界值_nil", nil, zero, false},
        {"错误情况", badInput, zero, true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := Foo(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if got != tt.want {
                t.Errorf("got %v, want %v", got, tt.want)
            }
        })
    }
}
```

**Fake Object（优先于 Mock）：**

被测函数依赖接口时，写手工 fake 结构体，而非 mock 框架：
- Fake 只实现测试需要的方法，其余方法返回零值
- Fake 定义在 `_test.go` 文件中，不污染生产代码

**测试 Fixture（配置加载类）：**

需要读取 JSON 配置的测试，用 `t.TempDir()` 创建临时目录（测试结束自动清理）：

```go
tmpDir := t.TempDir()
os.Mkdir(filepath.Join(tmpDir, "entity"), 0755)
os.WriteFile(filepath.Join(tmpDir, "entity", "test.json"), []byte(jsonContent), 0644)
mgr := NewConfigMgr(tmpDir)
```

**何时修改现有测试：**
- 修改函数签名 → 同步更新对应测试的调用
- 修改函数行为（如默认值变化）→ 更新 `want` 字段
- 修改配置文件格式 → 验证新格式的测试用例
- 删除函数 → 删除对应测试

**覆盖重点：**
- 正常路径（完整合法输入）
- 边界值（nil、空切片、空字符串、越界枚举）
- 默认值分支（字段缺失时的 fallback 行为）
- 错误路径（非法类型、缺失必要字段）

### 第五步半：编译验证与测试（必须）

**编码完成后、进入合宪性自检之前，必须先验证代码能编译通过并通过测试。**

**服务端编译 + 测试：**

如果本次修改了服务端代码，执行以下命令：

```bash
# 编译验证
cd E:/gta/Projects/Server && make build 2>&1 | tail -20

# 单元测试（编译通过后执行）
cd E:/gta/Projects/Server && make test 2>&1 | tail -30
```

- 编译失败 → **立即修复编译错误**，重新编译直到通过
- 测试失败 → 分析失败原因，修复代码或测试，重新运行直到通过
- 编译和测试都通过后，才能进入下一步

**客户端编译验证：**

如果本次修改了客户端代码，对每个新增/修改的 `.cs` 文件执行以下自检：

1. **using 验证**：逐个检查文件顶部的 using 语句，确认每个引用的命名空间在项目中真实存在。对不确定的命名空间，用 Grep 搜索 `namespace XXX` 确认
2. **类型存在性验证**：代码中引用的所有外部类型（类名、枚举、接口），用 Grep 搜索 `class/enum/interface ClassName` 确认存在
3. **API 签名验证**：调用的外部方法，用 Grep 搜索方法签名确认参数和返回值正确

> ⚠️ Unity 项目无法在 CLI 编译，上述自检是编译的替代方案。如果自检发现问题，立即修复后重新检查。

### 第六步：合宪性自检

**如果同时实现了客户端和服务端，使用并行 Agent 分别自检：**
- **Agent A（客户端自检）**：对照 `freelifeclient/.claude/constitution.md` + 编译正确性检查所有客户端新增/修改文件
- **Agent B（服务端自检）**：对照 `P1GoServer/.claude/constitution.md` 检查所有服务端新增/修改文件

所有代码编写完成后，对照两端宪法进行逐条自检：

**客户端自检（对照 `freelifeclient/.claude/constitution.md` + 编译正确性）：**

| 条款 | 检查项 |
|------|--------|
| **编译：using** | 每个新文件的 using 是否完整？对照 `namespace-reference` skill 逐一确认。重点检查：`FL.Gameplay.Manager`（单数，Manager 类）和 `FL.Gameplay.Managers`（复数，扩展方法）是否都已引用？ |
| **编译：命名空间** | 新文件的 namespace 是否与目录层级对应？（如 `Modules/Logic/Account/` → `FL.Gameplay.Modules.Logic.Account`） |
| **编译：API 存在性** | plan 中的 API 调用是否与实际代码一致？（如 `LobbyCmd.Login()` vs `LobbyCmd.LobbyLogin()`、`NotifyKick.Code` vs `NotifyKick.Reason`）。对不确定的 API，用 Grep 搜索实际方法签名确认。 |
| **编译：类型匹配** | Proto 字段名、枚举值是否与 `.pb.cs` 文件中的实际定义一致？（Proto 生成的 C# 字段是 PascalCase） |
| **编译：跨命名空间引用** | 子命名空间中的类访问父命名空间的类（如从 `Logic.Lobby` 访问 `Logic.LogicManager`）C# 可自动解析，但访问不同命名空间树的类（如从 `Modules.UI` 访问 `FL.Net`）必须有显式 using。 |
| 1.1 YAGNI | 是否只实现了 plan 要求的功能？ |
| 1.2 框架优先 | 是否复用了 ManagerCenter、EventCenter 等已有基础设施？ |
| 1.4 MonoBehaviour 节制 | 纯逻辑是否使用了 BaseManager 而非 MonoManager？ |
| 2.1-2.5 Manager 架构 | Manager 是否通过 CreateInstance 创建？优先级是否声明？通信是否走事件？ |
| 3.1-3.4 事件驱动 | 事件是否注册到正确的 EventModule？EventId 是否有 const 定义？订阅是否配对？ |
| 4.1 UniTask | 异步是否使用 UniTask？有无遗漏的 Unity 协程？ |
| 5.1-5.5 网络 | HTTP/Socket 是否分层正确？Result 是否检查？Push 是否走 Handler？ |
| 6.1-6.2 内存性能 | 热路径是否避免了 new/装箱/LINQ？频繁对象是否用了 ReferencePool？ |
| 7.1 日志 | 是否使用 MLog 而非 Debug.Log？拼接是否用 `+`？ |
| 7.2 错误处理 | catch 块是否有日志？Result 错误是否处理？ |
| 8.1-8.2 资源加载 | 是否通过 LoaderManager 异步加载？有无同步加载？ |

**服务端自检（对照 `P1GoServer/.claude/constitution.md`）：**

| 条款 | 检查项 |
|------|--------|
| 1.1 YAGNI | 是否只实现了 plan 要求的功能？ |
| 1.2 标准库优先 | 是否避免引入不必要的第三方依赖？ |
| 3.1 错误处理 | 所有 error 是否都显式处理？是否用 errorx 包装？ |
| 3.2 错误日志 | 产生错误处是否有 log.Errorf/Warningf？ |
| 3.3 无全局变量 | 是否有新增的全局变量？ |
| 5.1 Actor 独立性 | Actor 数据是否只在自身协程内访问？ |
| 5.2.1 消息传递 | 跨 Actor 通信是否通过 Send()？有无直接访问成员？ |
| 5.5.1 defer 释放锁 | 使用锁时是否用 defer 释放？ |
| 5.6.1 safego | 新启动的 goroutine 是否使用 safego.Go()？ |
| 6.1 业务 ID | 跨进程操作是否有业务 ID 贯穿？ |

输出自检结果表格（✅ 通过 / ❌ 违反 + 修复说明）。如有违反，**立即修复**后重新自检。

### 第七步：合并特性到工程文档（仅当 engine_name 非空时执行）

当用户提供了 `engine_name` 参数时，将本功能的**核心特性描述**合并到工程文档 `docs/Engine/{engine_name}/` 中。

**目标文件**：`docs/Engine/{engine_name}/` 下的 `.md` 文件（通常每个目录只有一个主文档）。

**操作流程：**

1. 读取目标工程文档的当前内容
2. 从 `feature.json`（或 `feature.md`）和 `plan.json`（或 `plan.md`）中提取**特性描述**（见下方"提取规则"）
3. 将提取的内容**追加或融合**到工程文档中，保持文档整体结构连贯

**提取规则 — 合并什么：**
- 功能概述：本功能做什么、解决什么问题
- 核心流程：主要业务流程的概念性描述（如"玩家点击登录 → 账号认证 → 连接大厅 → 进入游戏"）
- 协议概要：涉及的消息类型和用途（如"ReqAccLogin 用于账号登录请求"），不含字段细节
- 架构要点：关键设计决策（如"HTTP 负责账号认证，Socket 负责实时通信"）
- 异常处理策略：核心异常场景和处理方式（如"被踢线时断开连接并返回登录界面"）

**提取规则 — 不合并什么：**
- 具体代码片段、类定义、函数签名
- 具体文件路径和目录结构
- Protobuf 字段级定义
- 版本特定的临时限制（如"v0.0.1 使用硬编码"）
- 合宪性自检结果
- 测试用例

**文档格式要求：**
- 如果工程文档当前只有 `name`/`description` 头部，则新建完整的文档结构
- 如果工程文档已有内容，则将新特性**融合**到已有章节中，避免重复，保持一份连贯的系统级文档
- 使用 Markdown 格式，层级清晰
- 语言风格：面向开发者的技术文档，简洁准确，不冗余

**工程文档推荐结构：**

```markdown
# {系统名称}

## 概述
系统的整体目标和职责范围。

## 核心流程
### 流程名称
流程的概念性描述（文字或简化时序图）。

## 架构设计
### 客户端
关键模块和职责。
### 服务端
关键 Actor/Service 和职责。

## 通信协议
涉及的消息类型、用途、走 HTTP 还是 Socket。

## 异常与容错
核心异常场景和处理策略。
```

### 第八步：输出实现总结

最后向用户输出简洁的实现总结：
- 新增文件列表（带路径）
- 修改文件列表（带路径 + 修改概述）
- 关键实现决策说明（如有偏离 plan 的地方，说明原因）
- 工程文档更新说明（如果执行了第七步，说明合并了什么内容到哪个文档）
- 后续需要用户手动完成的事项（如 UI 资源文件、配置文件等非代码工作）

### 第九步：持久化开发日志

将第八步的实现总结写入 `docs/Version/{version_id}/{feature_name}/develop-log.md`，作为本次开发的持久化记录。

**文件路径**：`docs/Version/{version_id}/{feature_name}/develop-log.md`

**写入规则：**
- 如果文件不存在，创建新文件
- 如果文件已存在（例如之前分批实现过），**追加**新的日志条目到文件末尾，不覆盖已有内容
- 每次追加时用 `---` 分隔线和日期标题区分不同批次

**文档格式：**

```markdown
# 开发日志：{feature_name}

## {日期} - {实现范围简述}

### 新增文件
- `路径/文件名` — 职责描述

### 修改文件
- `路径/文件名` — 修改概述

### 关键决策
- 决策描述（如有偏离 plan 的地方，说明原因）

### 测试情况
- 测试通过/失败的概要

### 待办事项
- 后续需要手动完成的事项（如有）
```

**内容要求：**
- 与第八步输出给用户的总结内容一致，但格式化为 Markdown 文档
- 包含日期（从系统获取 currentDate）
- 包含实现范围（客户端/服务端/两端）
- 包含测试结果概要
- 如果有合宪性自检中发现并修复的问题，简要记录

**完成声明（Ralph Loop 机制）— 不可跳过：**
在 develop-log.md 末尾，你必须根据实际完成情况追加以下标记之一：

- `ALL_FILES_IMPLEMENTED` — 表示你已经实现了任务/plan 范围中的**所有**文件
- 如果只完成了部分文件（上下文不够、遇到困难等），**不要写这一行**，而是在待办事项中列出未完成的文件清单

这是自动化流水线判断你是否真正完成的唯一依据。虚报会导致后续 Review 失败和质量下降。

---

## 禁止事项

1. **禁止编造 API**：不确定某个类/方法是否存在时，必须先搜索代码库确认
2. **禁止超范围实现**：plan 没提到的功能一律不做
3. **禁止忽略错误**：客户端的 Result、服务端的 error 必须处理
4. **禁止跳过上下文**：不读现有代码就开始写是被禁止的
5. **禁止破坏已有代码**：修改现有文件时不能改变其原有功能的行为

---

请先完成参数解析，然后从第一步开始执行。
