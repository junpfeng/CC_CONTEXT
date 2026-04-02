# GTA5 动物系统复刻

## 核心需求
目前的动物系统过于简单（4种动物、仅 Idle/Walk/Run/Flight/Follow 5个状态），需要复刻 GTA5 中动物系统的核心体验。

## 调研上下文

### 现有系统架构
- **服务端**: OrthogonalPipeline 4维度（Engagement/Expression/Locomotion/Navigation），AnimalIdleHandler/FollowHandler/NavigateBtHandler/BirdFlightHandler
- **客户端**: AnimalController → FsmComp(5状态) → AnimComp → AudioComp → InteractComp
- **协议**: AnimalData(type/state/idle_sub/speed/heading/follow_target/variant/category), AnimalFeedReq/Res, SummonDogReq/Res, AnimalStateChangeNtf
- **配置**: CfgInitMonster(速度/视野), CfgAudioAnimal, CfgMonsterPrefab, CfgMonsterAnimation
- **LOD**: 3级(Full<50m/Medium<150m/Low<300m/Off>300m)，tick频率100/300/1000ms
- **当前动物**: Dog(48), Bird(47), Crocodile(49), Chicken(50)，共8只（2Dog+3Croc+1Bird+2Chicken）
- **寻路**: 三级fallback（路网A*→NavMesh→直线兜底）

### GTA5 动物系统参考
- **28种动物** 分3大类：陆地（鹿/野猪/美洲狮/土狼/狗/猫等）、空中（鹰/海鸥/鸟群）、水下（鲨鱼/海豚/鱼）
- **生态区域生成**: 动物按生态位出现在对应地形（山狮在山区、鲨鱼在海洋、鹿在森林）
- **行为原型**: 被动型（接近逃跑）、攻击型（美洲狮/鲨鱼主动攻击）、伴侣型（Franklin的Chop）
- **群体行为**: 鲨鱼2-3只成群、鹿群、鸟群编队飞行（leader-follower）
- **感知系统**: 视觉+听觉，枪声扩大逃跑半径
- **昼夜循环**: 部分动物仅特定时段出现（夜行土狼）
- **玩家交互**: 狩猎、喂食/绑定、被攻击、野生动物摄影
- **GTA Online 移除动物**: CPU开销过大——手机端核心约束

### 手机端约束
| 关注点 | 约束 | 缓解措施 |
|--------|------|----------|
| CPU | <2ms AI/帧 | AI LOD降频；装饰型动物零AI |
| Draw Call | <30全部动物 | 同种合批；激进despawn |
| 生成数 | GTA Online因性能移除 | 硬上限可配置 |
| 网络 | 手机带宽 | 仅状态变化时同步 |

## 范围边界
- 做：行为升级（攻击/逃跑/群体/感知）、交互优化（头顶气泡投喂/轮盘召唤）、数量提升到20只、Chicken解除Rest锁定
- 不做：新增物种、真实伤害系统、生态区域生成、昼夜循环、骑乘、狩猎击杀、水下动物

## 初步理解
在现有 4 种动物 + 5 状态的基础上，向 GTA5 靠拢升级。本阶段聚焦行为丰富度和交互体验，不扩展物种。

## 待确认事项
已全部确认。

## 确认方案

### 锁定决策

**物种与数量**：
- 保持现有 4 种：Dog(48)、Bird(47)、Crocodile(49)、Chicken(50)
- 数量提升：Dog 4 + Croc 4 + Bird 6 + Chicken 6 = 20 只（MaxLandAnimals/MaxBirdAnimals 相应调整）
- Chicken 解除 Rest 锁定，与其他动物一样拥有 Idle/Wander 行为

**鳄鱼攻击系统（演示级）**：
- 感知范围 15m，攻击触发距离 5m
- 行为：感知→接近→攻击动画+推开效果→冷却→回归巡逻
- 不扣血，仅做攻击表现（动画+镜头轻震+玩家被推开2m），后期再接入伤害
- 玩家暂不能反击击杀鳄鱼
- 注意：鳄鱼目前无攻击动画（仅idle/walk），需新增攻击clip或复用walk加速作为冲击表现

**投喂交互（3D头顶气泡）**：
- 复用现有 AnimalInteractComp 近距检测 + InteractionPanel 屏幕空间浮动UI
- 玩家进入3m范围→狗头顶出现投喂按钮气泡（已有机制，优化视觉）
- 点击即触发投喂动画，无需消耗食物物品（演示用，移除背包检查）
- 投喂后狗进入 Follow 状态 30s

**召唤狗按钮（GTA5互动轮盘）**：
- 复用现有轮盘系统（HandheldWheelPanel/PoseWheelPanel架构）
- 在互动轮盘中新增"召唤狗"选项（图标+文字）
- 替代当前Alt+P的SummonDogPanel，召唤最近50m内的狗
- 如无现成轮盘可挂载，退化为主界面右侧快捷按钮

**群体行为（简化版）**：
- 同种动物生成时5-10m内成群2-4只
- 逃跑触发：群内第一只感知到威胁后触发，其余0.3-0.5s内跟随逃跑
- 逃跑方向：以威胁源反方向为基准，每只±15°随机偏移
- 服务端实现：AnimalGroupComp记录群组ID，逃跑时广播群组成员

**感知系统**：
- 视觉感知范围：Bird 30m、Dog 20m、Crocodile 15m、Chicken 10m
- 听觉感知：枪声事件扩大逃跑半径至2倍视觉范围
- 复用现有 CreatureMetadata 的 AwarenessRadius/VisionRange 字段
- 鳄鱼感知后切换为攻击行为，其余动物切换为逃跑行为

**客户端状态扩展**：
- 新增 AnimalState_Flee=6（逃跑）、AnimalState_Attack=7（攻击，鳄鱼专用）
- 客户端FSM新增 AnimalFleeState、AnimalAttackState
- 攻击表现：攻击动画+镜头轻震+玩家被推开2m（客户端本地表现）

**协议变更**：
- AnimalData 新增字段：uint32 group_id=9（群组ID）、uint64 threat_source_id=10（威胁源）
- AnimalState enum 新增：Flee=6、Attack=7
- 无需新增Req/Res消息，复用现有AnimalFeedReq（移除item_id校验）和SummonDogReq

**配置变更**：
- CreatureMetadata/MonsterConfig 更新感知参数
- SpawnAreaConfig 调整数量上限和群组生成参数
- Chicken 移除 Rest 锁定标记

### 待细化
- 鳄鱼攻击动画资源：如无现成clip，由执行引擎决定用walk加速模拟还是需要美术提供
- 召唤狗具体挂载到哪个轮盘（HandheldWheel/PoseWheel/新建），由执行引擎根据现有UI结构决定
- 群组生成的具体Spawner改造细节
- 感知系统与现有LOD的交互（LODOff时是否跳过感知计算）

### 验收标准
1. 大世界中生成20只动物（4Dog+4Croc+6Bird+6Chicken），全部正常漫游
2. Chicken不再锁定Rest，能正常Idle↔Wander
3. 玩家接近鳄鱼5m内，鳄鱼发起攻击动画+推开表现（不扣血）
4. 被动动物（Dog/Bird/Chicken）在玩家接近感知范围时触发逃跑
5. 同种动物成群生成（2-4只），逃跑方向基本一致
6. 靠近狗时头顶出现投喂气泡按钮，点击触发投喂+Follow
7. 玩家通过互动轮盘/快捷按钮可召唤最近的狗
8. 枪声触发更大范围的动物逃跑
9. 服务端make build+客户端编译均通过，无回归
