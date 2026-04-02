---
description: 提交Bug到对应版本的功能文档中
argument-hint: <version> <feature_name> <bug描述>
---

## 参数解析

用户传入的原始参数：`$ARGUMENTS`

**参数格式：** `<version> <feature_name> <bug描述>`

- `version`：版本号（如 `0.0.1`），为参数的第一个空格分隔段
- `feature_name`：功能名称（如 `match`、`login`），为参数的第二个空格分隔段
- `bug描述`：Bug 的现象描述，为参数剩余的所有内容

**参数缺失处理：**

1. **三个参数都有** → 直接执行
2. **缺少 bug 描述** → 用 AskUserQuestion 询问 Bug 现象描述
3. **只有 version** → 用 AskUserQuestion 询问功能名称和 Bug 描述
4. **参数为空** → 用 AskUserQuestion 一次性询问版本号、功能名称、Bug 描述（3 个问题）

---

## 执行流程

### 第一步：确定文件路径

Bug 文档路径：`docs/bugs/$version/$feature_name/$feature_name.md`

**Bug 编号确定**：读取 Bug 文档（如存在），统计已有条目数量（已修复+未修复），新 Bug 编号 = 总数 + 1。文档不存在则编号为 1。

图片目录路径：`docs/bugs/$version/$feature_name/$bug_number/images/`

### 第二步：检查并创建目录结构

1. 检查 `docs/bugs/$version/$feature_name/` 目录是否存在，不存在则创建
2. 检查 `docs/bugs/$version/$feature_name/$bug_number/images/` 目录是否存在，不存在则创建
3. 检查 Bug 文档文件是否存在

### 第三步：通过 Unity MCP 自动截图

**不要询问用户是否有截图，直接自主截图。** 如果用户主动提供了截图路径则优先使用用户的。

#### 截图流程

1. **分析 bug 描述，确定需要截取的画面**：
   - 解析 bug 描述中的关键词（如"小地图"→打开小地图、"点击XX按钮"→先点击再截图、"NPC图例"→点击图例 Toggle）
   - 如果 bug 涉及 UI 操作，必须先通过 MCP 模拟操作（打开面板、点击按钮等），**操作完成后再截图**
   - 如果 bug 涉及场景表现（如"看不到NPC"），直接截 Game View

2. **UI 操作方法**（通过 `python3 scripts/mcp_call.py script-execute`）：
   ```
   python3 scripts/mcp_call.py script-execute '{
     "csharpCode": "using UnityEngine; public class Script { public static string Main() { /* UI操作代码 */ return \"done\"; } }"
   }'
   ```
   常用操作：
   - 打开面板：`UIManager.Open<XxxPanel>().Forget()`（需 `using Cysharp.Threading.Tasks; using FL.Framework.UI; using FL.Gameplay.Modules.UI;`）
   - Toggle 图例：`MapManager.LegendControl.ToggleShowAllBigWorldNpc(true)`（需 `using FL.Gameplay.Modules.UI;`）
   - 查找 UI 对象：`GameObject.Find("CanvasRoot/PanelName")`（注意根节点是 `CanvasRoot` 不是 `UICanvas`）
   - 点击 uGUI 按钮：找到 Button 组件调用 `onClick.Invoke()`

   **截图操作顺序**：先操作 UI（打开面板/点击按钮）→ 等待渲染（`sleep 1-2s`）→ 再截图

3. **截图保存方法**（通过 `script-execute` + Python wrapper 避免 JSON 转义问题）：

   **推荐方式**：将 C# 代码写入临时文件 `scripts/temp_screenshot.cs`，然后用 Python wrapper 调用：
   ```python
   python3 -c "
   import json, subprocess
   code = open('scripts/temp_screenshot.cs').read()
   params = json.dumps({'csharpCode': code})
   result = subprocess.run(['python3', 'scripts/mcp_call.py', 'script-execute', params], capture_output=True, text=True, timeout=15)
   print(result.stdout[:500])
   "
   ```

   **截图 C# 代码（包含 UI 层，推荐）**：
   ```csharp
   using UnityEngine;
   public class Script {
       public static string Main() {
           var tex = ScreenCapture.CaptureScreenshotAsTexture();
           if (tex == null) return "ScreenCapture failed";
           var bytes = tex.EncodeToPNG();
           System.IO.File.WriteAllBytes("SAVE_PATH", bytes);
           Object.DestroyImmediate(tex);
           return "Saved, size=" + bytes.Length;
       }
   }
   ```
   > ⚠️ `ScreenCapture.CaptureScreenshotAsTexture()` 包含 UI 层（UI Toolkit + uGUI），适合截取带面板的画面。
   > ⚠️ `Camera.main` 渲染方式**不含 UI 层**，仅适合截取纯 3D 场景。

   **UI 操作 C# 代码示例**（打开面板）：
   ```csharp
   using UnityEngine;
   using Cysharp.Threading.Tasks;
   using FL.Framework.UI;
   using FL.Gameplay.Modules.UI;
   public class Script {
       public static string Main() {
           UIManager.Open<MapPanel>().Forget();
           return "MapPanel opened";
       }
   }
   ```

   - `SAVE_PATH` 替换为 `docs/bugs/$version/$feature_name/$bug_number/images/$feature_name_bugN_描述.png`

4. **截图命名规则**：`$feature_name_bugN_场景描述.png`（如 `V2_NPC_bug1_game_view.png`、`V2_NPC_bug1_minimap_toggle.png`）

5. **多张截图**：如果 bug 描述涉及多个场景（如"大世界看不到NPC"+"小地图点击图例无反应"），分别操作并截取多张图

6. **MCP 不可用时的降级**（禁止询问用户）：
   - 尝试重启 MCP：`python3 scripts/mcp_call.py ping '{}'`，失败则 `powershell scripts/unity-restart.ps1`
   - 如果 Unity 未启动，自行启动 Unity 并等待 MCP 恢复
   - 如果 MCP 始终不可用（重试3次后），跳过截图步骤，在 bug 文档中标注 `<!-- 截图缺失：MCP 不可用 -->`，继续完成 bug 记录

#### 用户主动提供截图时

如果用户提供了截图文件路径，将文件复制到 `docs/bugs/$version/$feature_name/$bug_number/images/` 目录，命名规则 `$feature_name_bugN_原始文件名`

### 第三点五步：自动判定严重度

根据 bug 描述自动分类严重度（不问用户）：

| 关键词匹配 | 严重度标签 |
|-----------|-----------|
| 含"编译错误"/"CS 错误"/"build failed"/"compile error"/"编译失败" | `compile-error` |
| 含"配置缺失"/"配置表"/"config missing"/"配置不存在"/"打表" | `config-missing` |
| 含"显示"/"动画"/"UI"/"截图"/"视觉"/"画面"/"特效"/"渲染" | `visual-bug` |
| 其他 | `logic-bug` |

按顺序匹配，命中第一个即停止。将判定结果记为 `{severity}`，写入第四步的 bug 条目。

### 第四步：写入 Bug 条目

- **文件存在** → 读取文件内容，在 `# 未修复bug` 部分追加新条目
- **文件不存在** → 创建新文件，使用标准模板

**新文件标准模板：**

```markdown
# 未修复bug
- [ ] [bug描述]
  - **严重度**: {severity}
```

**追加格式（无图片）：**

```markdown
- [ ] [bug描述]
  - **严重度**: {severity}
```

**追加格式（有图片）：**

```markdown
- [ ] [bug描述]
  - **严重度**: {severity}
  - **截图**：
    - ![截图说明](N/images/feature_name_bugN_filename.png)
```

多张图片时每张一行：

```markdown
- [ ] [bug描述]
  - **严重度**: {severity}
  - **截图**：
    - ![截图1](N/images/feature_name_bugN_1_filename1.png)
    - ![截图2](N/images/feature_name_bugN_2_filename2.png)
```

**注意：**
- 图片引用使用相对路径 `$bug_number/images/`，确保 bug-fix 命令读取时能直接定位图片
- 如果文件已有内容，确保新条目追加在 `# 未修复bug` 部分的最后一行之后
- 保持与已有条目格式一致（使用 `- [ ]` 复选框格式）
- 如果文件中使用的是 `[]` 而非 `- [ ]`，则统一修正为 `- [ ]` 格式

### 第五步：输出确认

输出简洁的确认信息：

```
已提交 Bug #$bug_number 到 docs/bugs/$version/$feature_name/$feature_name.md：
- [ ] [bug描述]
  - **严重度**: {severity}
[如果有图片] 截图已保存到 docs/bugs/$version/$feature_name/$bug_number/images/
```

---

## 禁止事项

1. **禁止修改已有 Bug 条目**：只追加新条目，不修改已有内容（格式统一除外）
2. **禁止分析或修复 Bug**：本命令只负责记录，修复请使用 `/bug/fix`
3. **禁止创建多余文件**：只操作 Bug 文档和图片目录

---

请先完成参数解析，然后执行。
