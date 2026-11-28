# INTERFACE.md — 模块接口契约（草案，待确认为准）

负责人：丙（规划集成）。**这份文件是提案，不是定稿。** 请甲确认第 1 节，乙确认第 2 节，确认后在 PR 里改成"已冻结"并注明日期。定稿后任何改动都要同步改 `planner_bridge.pl` 和相关测试。

目标只有一个：让"世界状态 → problem.pddl → 计划 → 执行"这条链路上，只有**一处**定义每个事实叫什么名字。

---

## 1. 甲：状态谓词与快照（待确认）

### 1.1 人话版

桥接层不需要读甲的整个知识库，只需要甲提供一个**只读快照**，内容是"当前世界的真值列表"，而且这些真值**直接用 PDDL 的名字命名**。这样桥接层几乎不用写转换代码，也不会出现"两套名字对不上"的联调事故。

```prolog
% legal_state_snapshot(-Atoms) is det.
% Atoms 是当前世界真值的列表，元素形状与 PDDL 原子一致。
legal_state_snapshot([ at_player(entrance),
                       at_thief(vault),
                       at_warden(archive),
                       at_core(observatory),
                       phase(race),
                       gate(locked),
                       carrier(unmarked),
                       link(vault,archive),
                       ... ]).
```

### 1.2 需要冻结的谓词

| Prolog 事实 | 含义 | 取值 |
|---|---|---|
| `i_am_at(L)` | 玩家位置 | 房间名 |
| `adversary_at(thief, L)` / `adversary_at(warden, L)` | 对手位置 | 房间名 |
| `at(Item, L)` | 地面物品（桥上只关心 `star_core`） | `star_core` |
| `inventory(List)` | 玩家背包（有顺序、可重复计算重量） | 物品名列表 |
| `phase(P)` | 阶段 | `race` / `recover` |
| `gate_state(S)` | 闸门 | `locked` / `open` / `sealed` |
| `carrier_status(S)` | 玩家是否被标记 | `unmarked` / `marked` |
| `enemy_holding(thief, star_core)` | 盗影持核 | 0 元事实 |
| `core_secured` | 星核已被送回库房 | 0 元事实 |
| `core_recovered` | 星核已被夺回 | 0 元事实 |
| `lantern_energy(N)` / `turn(N)` | 灯火、回合 | 整数，**不进 PDDL** |
| `world_version(N)` | 规划相关状态版本 | 整数 |

### 1.3 快照的映射规则（桥接层照此实现，甲只需保证事实名）

| 快照原子 | PDDL 原子 |
|---|---|
| `at_player(L)` | `(at_player L)` |
| `at_thief(L)` / `at_warden(L)` | `(at_thief L)` / `(at_warden L)` |
| `at_core(L)` | `(at_core L)` |
| `phase(P)` | `(phase P)` |
| `gate(S)` | `(gate S)` |
| `carrier(S)` | `(carrier S)` |
| `thief_holds_core` | `(thief_holds_core)` |
| `core_secured` / `core_recovered` | 同名 0 元谓词 |
| `link(A,B)` | `(link A B)` |

**不进入 PDDL 的东西**：灯火、回合数、背包内容、物品重量、钥匙与护符的持有状态。这些只在 Prolog 里影响玩家能不能动，不影响对手怎么规划。

### 1.4 版本递增规则（这条最容易写错）

- 玩家移动、拿/放物品、开锁、用护符、阶段切换、闸门状态变化、标记状态变化 → **递增 `world_version`**
- 对手自己执行完一个动作 → **不递增**，改用 `advance_plan/2` 把缓存计划的第一步丢掉
- 灯火和回合变化 → **不递增**（它们不进 PDDL）

理由：如果对手自己的动作也递增版本，缓存每回合都会失效，计划缓存就成了摆设。

---

## 2. 乙：PDDL 领域契约（待确认）

### 2.1 建议的类型与谓词

```pddl
(:requirements :strips :typing)

(:types loc thing mode - object)

(:predicates
    (link ?a ?b - loc)
    (at_player ?l - loc)
    (at_thief ?l - loc)
    (at_warden ?l - loc)
    (at_core ?l - loc)
    (phase ?m - mode)                 ; race | recover
    (gate ?m - mode)                  ; locked | open | sealed
    (carrier ?m - mode)               ; unmarked | marked
    (thief_holds_core)
    (core_secured)
    (core_recovered))
```

要点：

- `:requirements` 写 `(:strips :typing)`，不要抄课程样例的 `:adl`。
- 枚举值（`race`、`locked`、`marked` 等）作为 `mode` 类型的**对象**放进 `:objects`，不要用 0 元谓词堆砌（0 元谓词可用，但一个状态机用参数化更好读）。
- **前置条件里不能出现 `not`**（pyperplan 硬限制，已实测：`SemanticError: unknown predicate not`）。需要"某物还没被拿"这类条件时，用状态谓词的取值来表达，例如 `(core loose)` 而不是 `(not (holding_core))`。
- 效果里用 `not` 是允许的（唯一表达删除的方式）。

### 2.2 动作签名

| 动作 | 参数 | 前置 | 效果 |
|---|---|---|---|
| `move_thief` | `?from ?to - loc` | `at_thief(?from)`, `link(?from,?to)` | 更新 `at_thief` |
| `move_warden` | `?from ?to - loc` | `at_warden(?from)`, `link(?from,?to)` | 更新 `at_warden` |
| `take_core` | `?l - loc` | `phase(race)`, `at_thief(?l)`, `at_core(?l)` | 删 `at_core`，加 `thief_holds_core` |
| `secure_core` | 无 | `phase(race)`, `thief_holds_core`, `at_thief(vault)` | 加 `core_secured` |
| `mark_carrier` | `?l - loc` | `phase(recover)`, `at_thief(?l)`, `at_player(?l)` | `carrier(marked)` |
| `seal_exit` | `?g - loc` | `phase(recover)`, `at_warden(?g)`, `gate(locked)` | `gate(sealed)` |
| `capture_carrier` | `?l - loc` | `phase(recover)`, `at_warden(?l)`, `at_player(?l)`, `carrier(marked)`, `gate(sealed)` | `core_recovered` |

两个说明：

- `secure_core` 里写死 `vault` 是因为地图已冻结；如果要通用化，加一个 `(vault ?l)` 一元谓词即可，但动作数别再加了。
- `mark_carrier` 现在要求同房间，而玩家每回合都在动，实际很难触发。建议改成**相邻**（`link(?l,?playerloc)`）或者在参数里直接传玩家位置，否则"标记 → 抓捕"那条协作链演不出来。这个由乙决定，但请在 PR 里说明选了哪种。

### 2.3 需要交付的文件

| 文件 | 内容 |
|---|---|
| `adversary_domain.pddl` | 上面这套，能被 pyperplan 2.1 求解 |
| `adversary_problem.pddl` | 游戏开始时的默认问题（race 阶段） |
| `pddl_cases/case_default.pddl` | 默认争夺 + 守出口 |
| `pddl_cases/case_recover.pddl` | 玩家拿走星核后的目标变化 |
| `pddl_cases/case_coop.pddl` | 标记 + 封锁 + 抓捕的完整协作 |

桥接层的测试只需要 `adversary_domain.pddl`；其余我用来做执行层和"无解回退"的回归用例。

---

## 3. 丙：对下游的承诺

```prolog
% 渲染并求解；Outcome = plan(Actions) | no_solution | planner_error(Status, Message)
solve_problem(+Spec, +Options, -Outcome)
% Options: version(+Int), domain(+Path), timeout(+Seconds)

% 计划缓存
plan_cache_lookup(+Version, +GoalKey, -Plan)
plan_cache_store(+Version, +GoalKey, +Plan)
plan_cache_clear
advance_plan(+Plan, -Rest)
```

失败语义：

| Outcome | 含义 | 调用方该做什么 |
|---|---|---|
| `plan(Actions)` | 有计划 | 校验首动作后执行一步 |
| `no_solution` | 规划器正常跑完但无解 | 丢弃计划，走确定性回退，记 `fallback/1` 事件 |
| `planner_error(no_planner, _)` | 没找到规划器 | 提示安装，走回退，**不得假装成功** |
| `planner_error(N, Msg)` | 规划器自身报错 | 记日志，走回退 |

### 3.1 执行层（adversary_execution.pl）

```prolog
legal_action(+Atoms, +Action)                    % 只读检查，不改世界
missing_preconditions(+Atoms, +Action, -Missing) % 诊断：缺哪个原子
apply_action(+Atoms, +Action, -Atoms2)
simulate_plan(+Atoms, +Plan, -Atoms2)            % 整条计划能不能走完
adversary_turn(+Atoms, +Options, -Events, -Atoms2)
```

`adversary_turn/4` 一手包办"缓存有效就用、失效就重规划、重规划失败就回退"。
它不直接改真实世界：调用方拿返回的 `Atoms2` 去更新自己的状态。

**一条纪律**：`preconditions/2` 与 `effect/3` 必须和 `adversary_domain.pddl` 一致。
乙改 domain 的前置条件，丙这边必须同步改，否则会出现"规划器认为合法、运行时认为非法"，
每回合都退化成回退分支。这条写进报告的"局限与取舍"里，比藏着好。

---

## 4. 丙 ↔ 丁：事件项

执行层只输出下面这几种项，`ui.pl` 的 `show_events/1` 负责显示：

```prolog
enemy_action(Action)      % 对手执行了一个合法动作
invalid_action(Action)    % 计划里的动作在当前世界非法（附原因见日志）
replan(Reason)            % 计划失效后重规划
fallback(Reason)          % 进入确定性回退
enemy_wait(Reason)        % 没有合法动作，本回合不动
game_message(Atom)        % 其他要显示的消息
```

`invalid_action/1` 我会额外带一条 `format(user_error, ...)` 的诊断，写明缺哪个原子，方便定位是设计问题还是代码问题。

---

## 5. 待确认清单

| # | 内容 | 谁来确认 | 建议截止 |
|---|---|---|---|
| 1 | 第 1 节的谓词名与 `legal_state_snapshot/1` 形状 | 甲 | 12/01 |
| 2 | 第 1.4 节的版本递增规则 | 甲 | 12/01 |
| 3 | 第 2 节的类型、谓词、动作签名 | 乙 | 12/01 |
| 4 | `mark_carrier` 是否改成相邻投射 | 乙 | 12/01 |
| 5 | 事件项是否需要增加或改名 | 丁 | 12/03 |
