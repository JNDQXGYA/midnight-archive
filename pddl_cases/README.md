# 乙部分 PDDL 模型与测试

本目录包含乙负责的 PDDL 模型测试、可重放计划与连续回合演示。PDDL 文件是本分支的实现基础，Prolog 状态序列化、计划缓存和运行时执行仍需由甲、丙在联调中完成。

本分支中的辅助脚本和追踪用于学习、测试和联调，不替代小组成员对正式提交内容的自行理解、重写与验证。正式代码、报告与展示材料须由小组共同完成并按课程要求提交。

## 文件与独立场景

| 文件 | 起始快照 | 目标 |
| --- | --- | --- |
| `../adversary_problem.pddl` | 开局，盗影在库房、守夜人在档案室、玩家在入口、星核在天文室 | `core_secured` 且守夜人在闸门 |
| `default_race_problem.pddl` | 默认问题的回归副本 | 同默认问题 |
| `recover_goal_problem.pddl` | 玩家和盗影同在天文室，玩家已持星核，守夜人在闸门 | `captured` 和 `core_recovered` |
| `cooperation_problem.pddl` | 盗影在库房、守夜人在档案室、玩家在天文室并已持星核 | 完整的标记、封锁、抓捕协作 |

这三个 `.pddl` 文件是彼此独立的静态规划基线，并不表示同一局游戏的连续时刻。连续三角色演示由 `tools/timeline_runner.py` 生成。

## 动作覆盖

| 动作 | 前置条件摘要 | 效果摘要 | 测试场景 |
| --- | --- | --- | --- |
| `move_thief(From, To)` | 盗影在 From 且有地图连接 | 盗影到 To | 默认、协作 |
| `move_warden(From, To)` | 守夜人在 From 且有地图连接 | 守夜人到 To | 三个场景 |
| `take_core(Loc)` | `race`，盗影与星核同处 | 盗影持有星核 | 默认 |
| `secure_core(Loc)` | `race`，盗影持有星核且 Loc 是库房 | `core_secured` | 默认 |
| `mark_carrier(Loc)` | `recover`，盗影与携带者同处且未标记 | `carrier_marked` | 变化、协作 |
| `seal_exit(Loc)` | `recover`，守夜人在出口且未封锁 | `exit_sealed` | 变化、协作 |
| `capture_carrier(Loc)` | `recover`，守夜人与携带者同处，已标记且出口已封锁 | `captured` 和 `core_recovered` | 变化、协作 |

星核状态 `core_at`、`thief_holds_core`、`player_has_core`、`core_secured`、`core_recovered` 互斥。每次所有权转移都删除前一事实并加入后一事实。

## Prolog 接口与运行时失效

`locked` 和 `open` 都序列化为 `exit_unsealed`，`sealed` 序列化为 `exit_sealed`。`unmarked` 与 `marked` 分别对应 `carrier_unmarked` 与 `carrier_marked`。这些正事实满足 STRIPS 的限制，同时防止重复封锁和重复标记。

`path/3` 是地图来源，状态序列化将每条双向路径写成 `link/2`。`i_am_at/1` 对应 `player_at/1`，`adversary_at(thief|warden, Room)` 分别对应 `thief_at/1` 和 `warden_at/1`。星核只能从 `at(star_core, Room)`、玩家物品栏、`enemy_holding(thief, star_core)`、`core_secured`、`core_recovered` 其中一个 Prolog 表示转换为一个对应的 PDDL 事实。

玩家在天文室取得星核时，Prolog 将 `phase_race` 改为 `phase_recover`，把地面星核替换为 `player_has_core`，并废弃旧计划。每回合只执行一个重新校验过的对手动作。位置、星核状态、阶段、出口或标记的规划相关变化应增加世界版本。缓存版本不同、阶段导出的目标不同，或首个动作不再合法时，运行时废弃缓存并重新规划。灯火和回合数的独立变化不增加规划版本，也不触发重规划。

| 状态变化 | 将被拒绝的缓存动作 | 后续处理 |
| --- | --- | --- |
| 玩家取得星核 | `take_core` | 切换目标并重规划 |
| `ward_charm` 清除标记 | `capture_carrier` | 拒绝并重规划 |
| `brass_key` 重新打开出口 | `capture_carrier` | 拒绝并重规划 |
| 人物位置变化 | 移动、标记或抓捕 | 重新校验前置条件 |

重量、灯火、随机事件、回合和终局判断都留在 Prolog。领域只使用 `:strips` 与 `:typing`。

## 复现

在 Python 3.11 环境中安装 `pyperplan==2.1` 后，从仓库根目录运行：

```powershell
python -m pip install pyperplan==2.1
python -m unittest discover -s tests/pddl -v
python pddl_cases/tools/verify_reference.py
python pddl_cases/tools/timeline_runner.py
```

`tools/verify_reference.py` 用 Pyperplan 的 BFS 为三个独立问题求解并逐步重放。它检查动作的每一步前置条件、目标、七动作覆盖、两个对手参与，以及玩家抢先取得星核、使用 `ward_charm` 和使用 `brass_key` 后缓存动作会失效。已验证的样例计划保存在本目录的 `*.plan.txt`，分别有 12、5 和 12 个动作。该验证脚本不生成 `.soln` 文件。存在多条合法的最短移动路线，因此 Pyperplan 可能输出不同的动作交错顺序。样例按对应问题重放后达到目标。

## 连续三角色回合演示

执行 `python pddl_cases/tools/timeline_runner.py` 会从唯一的开局状态分别产生三条连续追踪。每个有效玩家命令耗费一回合和一点灯火，演示关闭 20% 穿堂风以保持可复现。`lamp_oil` 在扣除行动灯火后恢复 4 点，最高 12。`look`、`map`、`status`、`inventory`、`instructions` 和非法命令都不推进对手。已运行的完整输出见 [timeline_trace.txt](./timeline_trace.txt)。

两个快速路线使用完全相同的玩家序列。玩家依次在入口拿钥匙、到中庭拿灯油、到天文室拿星核、经长廊到闸门、用钥匙开门并 `escape`。物品重量为钥匙 1、灯油 1、星核 2，恰好达到容量 4。`escape` 在这份学习演示中先于对手响应检查，符合“满足条件即可逃离”的明确时序假设。

| 追踪 | race 共享回合策略 | 取得星核前的实际位置 | 结果 |
| --- | --- | --- | --- |
| `guard_first_fast` | 守夜人先沿最短路到闸门，随后盗影推进 | 盗影在库房，守夜人在闸门 | 守夜人在玩家进入闸门前封锁。钥匙打开后，策略特意延后一次重新封锁，玩家逃离。 |
| `race_balanced_fast` | 两个盗影推进槽位后给守夜人一个槽位，再循环 | 盗影在天文室，守夜人在中庭 | 盗影立即标记，守夜人仍落后，无法在玩家逃离前封锁。 |
| `guard_first_slow` | 与第一条相同 | 玩家在中庭使用灯油并额外绕行两步，使取得星核晚三回合 | 盗影标记，守夜人封锁。玩家可进入已封锁的闸门，但随后被抓捕。 |

对手选择不读取后续脚本。每个响应先把当前玩家、盗影、守夜人、阶段、星核、出口和标记状态序列化为新的 PDDL 问题，并保留当前阶段的 PDDL 目标，再使用实际领域模型将候选动作接地并验证。PDDL 动作的效果也由该接地动作应用。调度的优先级是示范层逻辑，与 Pyperplan 对独立问题执行的 BFS 搜索分开。恢复阶段的优先级是抓捕、同处时立即标记、出口处立即封锁、守夜人朝出口移动、盗影根据当前地图到闸门的下一跳预测拦截。标记和封锁都已成立时，守夜人会向预测拦截点移动或在该点等待。守夜人移动时会说明它和玩家到出口的当前距离，以及封锁需要额外一个响应，供判断是否赶得上。

玩家用 `brass_key` 打开已封锁的出口时，演示中的调度策略只延后一次重新封锁，避免每次开锁都在同一响应被马上重复封锁。它是演示的公平性调度约定，不改变 PDDL 动作或 Prolog 游戏规则。

## 边界

参考没有把“守夜人先到闸门”添加成 `secure_core` 的人为顺序条件。默认目标同时要求 `core_secured` 和守夜人在闸门，不过若游戏终局在 `core_secured` 时立即结束，守夜人可能还未到达。该时序和玩家逃离路线需要由甲、丙联调确认。

`exit` 静态事实指定 `gatehouse`，`vault_room` 指定 `vault`。接口更改时，团队需要同步更新领域、问题、状态序列化、动作校验和测试。
