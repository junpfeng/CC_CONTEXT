═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC — task-01（行人路网与巡逻路线数据生成）
  版本：0.0.2
  审查文件：5 个
═══════════════════════════════════════════════

审查范围（来自 develop-log.md task-01）：
- scripts/generate_ped_road.py
- scripts/generate_patrol_routes.py
- freelifeclient/RawTables/Json/Server/npc_zone_quota.json
- freelifeclient/RawTables/Json/Server/miami_ped_road.json（生成产物）
- freelifeclient/RawTables/Json/Server/ai_patrol/bigworld/*.json（20 条路线）

---

## 一、合宪性审查

task-01 仅包含 Python 工具脚本和 JSON 配置/数据文件，无 .cs 或 .go 源文件，
客户端/服务端宪法条款不直接适用。以下为工作空间级宪法检查：

### 工作空间宪法
| 条款 | 状态 | 说明 |
|------|------|------|
| 禁止修改 Proto 生成区域 | ✅ | 未触碰任何生成代码 |
| 禁止修改 Config/Gen/ | ✅ | 未修改配置生成代码 |
| 禁止修改 resources/proto/ | ✅ | 未修改 |
| 错误显式处理 | ⚠️ | 见边界情况第 3 条 |
| 不硬编码敏感信息 | ✅ | 无密钥/Token/密码 |
| YAGNI | ✅ | 脚本仅实现 plan 要求的生成逻辑 |
| 单一职责 | ✅ | 两个脚本职责清晰独立 |
| 服务器权威 | ✅ | 配置数据由服务端读取裁决，客户端不参与 |

---

## 二、Plan 完整性

### 已实现
- [x] `scripts/generate_ped_road.py` — 从车辆路网法线偏移生成 footwalk 路点，K-means 聚类 5 分区，输出 miami_ped_road.json
- [x] `scripts/generate_patrol_routes.py` — 从行人路网 DFS+回溯生成 20 条环形巡逻路线，输出到 ai_patrol/bigworld/
- [x] `freelifeclient/RawTables/Json/Server/npc_zone_quota.json` — totalNpcBudget=50，recycleHysteresis=5，quotaInterval=5.0，5 个分区，含 AABB/densityWeight/maxNpc ✅
- [x] `freelifeclient/RawTables/Json/Server/ai_patrol/bigworld/*.json` — 20 条路线，每条 8-15 节点，约 30% 节点含 behaviorType+duration ✅
- [x] `miami_ped_road.json` — 47157 路点，42182 边，全部 type=footwalk，含 walkZone 字段 ✅

### 遗漏
无（task-01 范围内的文件已全部实现）

### 偏差
- **`generate_ped_road.py:34`**：常量 `ZONE_OUTPUT_PATH` 指向 `npc_zone_quota.json`，但脚本实际写的是 `_zone_info.json`（line 347），从未写入 `ZONE_OUTPUT_PATH`。
  Plan 要求"WalkZone AABB 由脚本自动聚类，非手工指定"，而现行流程是：
  脚本生成 `_zone_info.json` → 人工将 AABB 值复制到 `npc_zone_quota.json`。
  若重新运行脚本，`npc_zone_quota.json` 中的 AABB 不会自动同步。

---

## 三、边界情况

**[HIGH]** `generate_ped_road.py:34` — `ZONE_OUTPUT_PATH` 死代码，AABB 同步流程断裂
  场景：重新运行 `generate_ped_road.py`（因源路网更新或参数调整），`npc_zone_quota.json` 的 AABB 值不会更新，导致 WalkZone 分区边界与实际路网不一致，服务端配额计算错误（NPC 不出现在正确区域）。
  影响：数据不一致是静默的，无编译报错，运行时才会暴露，排查成本高。

**[MEDIUM]** `generate_patrol_routes.py:288-291` — `target_count` 死代码
  场景：`random.randint(MIN_ROUTES, MAX_ROUTES)` 在 line 288 被计算但立即被 line 291 `target_count = 20` 覆盖，且 line 290 的 `random.seed(42)` 在重置前消耗了随机状态（虽然 seed 紧随其后）。
  影响：代码意图不清晰，维护者难以判断 target_count 是否可配置；如后续改动误删 line 291，行为将变为不确定。

**[MEDIUM]** `generate_ped_road.py:271-282` — `check_connectivity()` BFS 使用 `list.pop(0)`（O(n) 每次），非 `deque.popleft()`
  场景：输入路网规模 47157 路点，`pop(0)` 导致 BFS 为 O(n²)。最大分区约 1549 个连通分量，每个分量遍历均受影响。
  影响：脚本为一次性工具，当前数据下可接受；但源路网规模增大时可能显著变慢（分钟级）。

**[MEDIUM]** 两个脚本缺少用户友好的文件缺失错误处理
  场景：`generate_ped_road.py:39` 和 `generate_patrol_routes.py:43` 直接 `open()` 无 try/except，输入文件缺失时输出原始 Python traceback 而非明确提示。
  影响：对工具使用者不友好，排查成本稍高；不影响正确性（错误会传播，不静默）。

---

## 四、代码质量

**[MEDIUM]** `generate_ped_road.py:34` — 常量命名误导
  `ZONE_OUTPUT_PATH` 命名暗示该路径会被写入，但实际从未使用。应删除该常量或修正为实际写入路径 `_zone_info.json`，避免维护者误解。

**[MEDIUM]** `generate_patrol_routes.py:124` — `compute_heading_deg` 局部变量 `heading_rad` 命名规范
  符合 lesson-002 规范（明确标注 `_rad`/`_deg` 后缀）。✅

**[无问题]** 以下质量项检查通过：
  - K-means 确定性（seed=42）✅
  - 坐标范围钳制 ±4096 ✅
  - 巡逻路线数据格式与 plan PatrolRoute schema 一致 ✅
  - heading 角度单位一致（脚本输出度数，符合 Unity Y 轴旋转约定）✅
  - 双向边构建正确（generate_ped_road.py:148-151）✅
  - 环形路线末节点 links 指向节点 1（generate_patrol_routes.py:163-164）✅
  - desiredNpcCount=2，20 条路线容量 40 < totalNpcBudget=50 ✅

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     1 个（必须修复）
  MEDIUM:   4 个（建议修复，可酌情安排）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH] `ZONE_OUTPUT_PATH` 死代码导致 npc_zone_quota.json AABB 与行人路网脱节——重新生成路网时数据会静默不一致，应修复为脚本直接写入或明确删除死代码并在 README 注明手动同步步骤
  2. [MEDIUM] `generate_patrol_routes.py` target_count 死代码应清理，保证代码意图清晰
  3. [MEDIUM] BFS 性能：`check_connectivity` 改用 `collections.deque` 以备路网扩容

<!-- counts: critical=0 high=1 medium=4 -->
