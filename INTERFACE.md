# INTERFACE.md — 模块接口契约（草案，待确认为准）

负责人：丙（规划集成）。**第 2 节已由乙的实现冻结**（见该节），第 1 节仍待甲确认。任何改动都要同步改 `planner_bridge.pl`、`adversary_execution.pl` 和相关测试。

目标只有一个：让"世界状态 → problem.pddl → 计划 → 执行"这条链路上，只有**一处**定义每个事实叫什么名字。

---

## 1. 甲：状态谓词与快照（待确认）

### 1.1 人话版

桥接层不需要读甲的整个知识库，只需要甲提供一个**只读快照**，内容是"当前世界的真值列表"，而且这些真值**直接用 PDDL 的名字命名**。这样桥接层几乎不用写转换代码，也不会出现"两套名字对不上"的联调事故。

```prolog
% legal_state_snapshot(-Atoms) is det.
% Atoms 是当前世界真值的列表，元素形状与 PDDL 原子一致。
legal_state_snapshot([ player_at(entrance),
                       thief_at(vault),
                       warden_at(archive),
                       core_at(observatory),
                       phase_race,
                       exit_unsealed,
                       carrier_unmarked,
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
| `player_at(L)` | `(at_player L)` |
| `thief_at(L)` / `warden_at(L)` | `(at_thief L)` / `(at_warden L)` |
| `core_at(L)` | `(at_core L)` |
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

## 2. 乙：PDDL 领域契约（已冻结）

**状态：已由乙实现并冻结。** 以分支 `feature/pddl-adversaries` 的 `adversary_domain.pddl` 为准，
下面是摘要，冲突时以文件为准。`tests/fixtures/adversary_domain_snapshot.pddl` 是逐字快照，
`t_domain.pl` 会比对它的动作签名与执行层是否一致（当前 7/7 通过）。

### 2.1 类型与谓词

```pddl
(:types location)

(:predicates
    (link ?from ?to - location)
    (exit ?place - location)
    (vault_room ?place - location)
    (thief_at ?place - location)
    (warden_at ?place - location)
    (player_at ?place - location)
    (core_at ?place - location)
    (thief_holds_core)
    (player_has_core)
    (core_secured)
    (core_recovered)
    (phase_race)
    (phase_recover)
    (carrier_marked)
    (carrier_unmarked)
    (exit_unsealed)
    (exit_sealed)
    (captured))
```

要点：

- 只有一种对象类型 `location`；阶段、闸门、标记这些状态用成对的 0 元谓词表示
  （pyperplan 支持 0 元谓词，已实测）。
- **前置条件里不能出现 `not`**（pyperplan 硬限制，实测报 `SemanticError: unknown predicate not`）。
  "某物还没被拿"这类条件用成对谓词表达：`carrier_unmarked` / `carrier_marked`、
  `exit_unsealed` / `exit_sealed`；效果里再用 `not` 删掉旧的那个。
- `:requirements` 是 `(:strips :typing)`。

### 2.2 动作签名

| 动作 | 参数 | 前置 | 效果 |
|---|---|---|---|
| `move_thief` | `(?from ?to - location)` | `thief_at(?from)`, `link(?from,?to)` | 更新 `thief_at` |
| `move_warden` | `(?from ?to - location)` | `warden_at(?from)`, `link(?from,?to)` | 更新 `warden_at` |
| `take_core` | `(?loc - location)` | `phase_race`, `thief_at(?loc)`, `core_at(?loc)` | 删 `core_at`，加 `thief_holds_core` |
| `secure_core` | `(?loc - location)` | `phase_race`, `thief_at(?loc)`, `thief_holds_core`, `vault_room(?loc)` | 删 `thief_holds_core`，加 `core_secured` |
| `mark_carrier` | `(?loc - location)` | `phase_recover`, `thief_at(?loc)`, `player_at(?loc)`, `player_has_core`, `carrier_unmarked` | 删 `carrier_unmarked`，加 `carrier_marked` |
| `seal_exit` | `(?loc - location)` | `phase_recover`, `warden_at(?loc)`, `exit(?loc)`, `exit_unsealed` | 删 `exit_unsealed`，加 `exit_sealed` |
| `capture_carrier` | `(?loc - location)` | `phase_recover`, `warden_at(?loc)`, `player_at(?loc)`, `player_has_core`, `carrier_marked`, `exit_sealed` | 删 `player_has_core`，加 `captured`、`core_recovered` |

一个留给乙的设计问题（不影响丙开工）：`mark_carrier` 要求盗影和玩家同房间，而玩家每回合
都在移动，实际只在玩家停下来开锁/逃跑时才可能触发。要么接受这个限制并在报告里说明，
要么改成相邻投射（前置用 `link(?loc, ?playerloc)`）。乙定，丙按定下来的写校验。

### 2.3 交付文件

| 文件 | 内容 | 状态 |
|---|---|---|
| `adversary_domain.pddl` | 上面这套 | 乙已提交（分支未合并） |
| `adversary_problem.pddl` | 游戏开始时的默认问题（race 阶段） | 乙已提交 |
| `pddl_cases/` | 默认争夺、目标变化、协作三套 | 乙已提交 |

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
| 3 | 第 2 节的类型、谓词、动作签名 | 乙 | 已完成（见 §2） |
| 4 | `mark_carrier` 是否改成相邻投射 | 乙 | 待定（见 §2.2） |
| 5 | 事件项是否需要增加或改名 | 丁 | 12/03 |
