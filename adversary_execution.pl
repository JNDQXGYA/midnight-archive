/*  adversary_execution.pl -- 动作校验、一步执行、失效重规划与回退。负责人：丙。
 *
 *  设计上的两个原则：
 *
 *  1. 校验是"纯"的。legal_action/2 只读世界快照，不改任何状态；改状态只发生在
 *     apply_action/3 里。这样"计划里的动作在当前世界是否合法"可以反复问、
 *     可以单独测试，也可以拿来跑回归。
 *
 *  2. 世界以"原子列表"表示。快照由甲提供（见 INTERFACE.md 第 1 节），
 *     这里不直接读甲的知识库，也不直接写：调用方拿 apply_action/3 算出的新
 *     原子列表去更新真实状态。
 *
 *  前置条件表与 PDDL 领域必须一致。乙改了 domain 的某个前置条件，这里要同步改，
 *  这是"运行时校验"的代价，也是报告里要说明的取舍（见 INTERFACE.md 第 2 节）。
 */

:- module(adversary_execution,
          [ legal_action/2
          , missing_preconditions/3
          , apply_action/3
          , simulate_plan/3
          , adversary_turn/4
          , fallback_action/3
          , preconditions/2
          , effect/3
          , distances/3
          ]).

:- use_module(library(lists)).
:- use_module(planner_bridge).

% ---------------------------------------------------------------------------
% 动作模型（必须与 adversary_domain.pddl 保持一致）
% ---------------------------------------------------------------------------

preconditions(move_thief(From, To),
              [ at_thief(From), link(From, To) ]).

preconditions(move_warden(From, To),
              [ at_warden(From), link(From, To) ]).

preconditions(take_core(Loc),
              [ phase(race), at_thief(Loc), at_core(Loc) ]).

preconditions(secure_core,
              [ phase(race), thief_holds_core, at_thief(vault) ]).

preconditions(mark_carrier(Loc),
              [ phase(recover), at_thief(Loc), at_player(Loc) ]).

preconditions(seal_exit(Loc),
              [ phase(recover), at_warden(Loc), gate(locked) ]).

preconditions(capture_carrier(Loc),
              [ phase(recover), at_warden(Loc), at_player(Loc),
                carrier(marked), gate(sealed) ]).

% effect(Action, Added, Deleted)
% Deleted 的元素是 del(Atom) 或 del_all(Functor)，后者用于"状态机赋值"，
% 例如标记从 unmarked 变成 marked 时要先把旧的 carrier/1 删干净。
effect(move_thief(From, To),
       [ at_thief(To) ], [ del(at_thief(From)) ]).

effect(move_warden(From, To),
       [ at_warden(To) ], [ del(at_warden(From)) ]).

effect(take_core(Loc),
       [ thief_holds_core ], [ del(at_core(Loc)) ]).

effect(secure_core,
       [ core_secured ], []).

effect(mark_carrier(_),
       [ carrier(marked) ], [ del_all(carrier) ]).

effect(seal_exit(_),
       [ gate(sealed) ], [ del_all(gate) ]).

effect(capture_carrier(_),
       [ core_recovered ], [ del_all(carrier) ]).

% ---------------------------------------------------------------------------
% 校验
% ---------------------------------------------------------------------------

%% legal_action(+Atoms,+Action) is semidet.
%  注意：这里不能用 forall/2。forall 内部建立的绑定不会传出来，
%  findall(legal_action(Atoms,A), ...) 就会拿到一堆没实例化的动作项。
legal_action(Atoms, Action) :-
    preconditions(Action, Pre),
    preconditions_hold_(Pre, Atoms).

preconditions_hold_([], _).
preconditions_hold_([P|Ps], Atoms) :-
    member(P, Atoms),
    preconditions_hold_(Ps, Atoms).

%% missing_preconditions(+Atoms,+Action,-Missing) is det.
%  诊断用：告诉调用方到底缺哪个原子。演示出问题时，这条日志能一眼分清
%  是"设计参数不对"还是"桥接写错了"。
missing_preconditions(Atoms, Action, Missing) :-
    (   preconditions(Action, Pre)
    ->  exclude(atom_member_(Atoms), Pre, Missing)
    ;   Missing = [unknown_action(Action)]
    ).

atom_member_(Atoms, A) :- memberchk(A, Atoms).

% ---------------------------------------------------------------------------
% 应用
% ---------------------------------------------------------------------------

%% apply_action(+Atoms,+Action,-Atoms2) is det.
apply_action(Atoms0, Action, Atoms) :-
    (   effect(Action, Adds, Dels)
    ->  foldl(apply_del_, Dels, Atoms0, Atoms1),
        append(Adds, Atoms1, Atoms2),
        sort(Atoms2, Atoms)
    ;   throw(error(no_effect_for(Action), apply_action/3))
    ).

apply_del_(del(A), Atoms0, Atoms) :-
    delete(Atoms0, A, Atoms).
apply_del_(del_all(F), Atoms0, Atoms) :-
    exclude(has_functor_(F), Atoms0, Atoms).

has_functor_(F, Term) :-
    compound(Term),
    functor(Term, F1, 1),
    F1 == F.

%% simulate_plan(+Atoms,+Plan,-Atoms2) is det.
%  整条计划能不能在给定世界里走完；走不完就抛出带缺失原子的错误。
simulate_plan(Atoms0, Plan, Atoms) :-
    foldl(simulate_step_, Plan, Atoms0, Atoms).

simulate_step_(Action, Atoms0, Atoms) :-
    (   legal_action(Atoms0, Action)
    ->  apply_action(Atoms0, Action, Atoms)
    ;   missing_preconditions(Atoms0, Action, Missing),
        throw(error(illegal_action(Action, missing(Missing)),
                    context(simulate_plan/3, _)))
    ).

% ---------------------------------------------------------------------------
% 一回合的执行
% ---------------------------------------------------------------------------

%% adversary_turn(+Atoms,+Options,-Events,-Atoms2) is det.
%  Options:
%    version(+Int)            规划相关状态版本，默认 0
%    goal(+Atoms)             当前阶段的目标原子，用于缓存键
%    outcome(+Outcome)        直接给定求解结果（测试用）
%    solver(:Goal)            自定义求解器，按 call(Goal, Atoms, Outcome)
%    fallback_target(+Loc)    回退时朝哪个房间走
adversary_turn(Atoms0, Options, Events, Atoms) :-
    opt_(version, Options, 0, Version),
    opt_(goal, Options, [], Goal),
    goal_key_(Goal, Key),
    (   plan_cache_lookup(Version, Key, [Head|Tail]),
        legal_action(Atoms0, Head)
    ->  apply_action(Atoms0, Head, Atoms),
        plan_cache_store(Version, Key, Tail),
        Events = [enemy_action(Head)]
    ;   (   plan_cache_lookup(Version, Key, [StaleHead|_])
        ->  plan_cache_clear,
            Prefix = [invalid_action(StaleHead), replan(stale_plan)]
        ;   Prefix = []
        ),
        replan_turn_(Atoms0, Options, Version, Key, Prefix, Events, Atoms)
    ).

replan_turn_(Atoms0, Options, Version, Key, Prefix, Events, Atoms) :-
    solve_(Atoms0, Options, Outcome),
    (   Outcome = plan([Head|Tail])
    ->  (   legal_action(Atoms0, Head)
        ->  apply_action(Atoms0, Head, Atoms),
            plan_cache_store(Version, Key, Tail),
            append(Prefix, [enemy_action(Head)], Events)
        ;   missing_preconditions(Atoms0, Head, Missing),
            append(Prefix, [invalid_action(Head),
                            fallback(inconsistent_plan(Missing))], P1),
            fallback_turn_(Atoms0, Options, P1, Events, Atoms)
        )
    ;   Outcome = plan([])
    ->  Atoms = Atoms0,
        append(Prefix, [enemy_wait(goal_reached)], Events)
    ;   Outcome = no_solution
    ->  append(Prefix, [fallback(no_solution)], P1),
        fallback_turn_(Atoms0, Options, P1, Events, Atoms)
    ;   Outcome = planner_error(Status, _)
    ->  append(Prefix, [fallback(planner_error(Status))], P1),
        fallback_turn_(Atoms0, Options, P1, Events, Atoms)
    ;   Atoms = Atoms0,
        append(Prefix, [enemy_wait(unknown_outcome)], Events)
    ).

fallback_turn_(Atoms0, Options, Prefix, Events, Atoms) :-
    (   fallback_action(Atoms0, Options, Action),
        legal_action(Atoms0, Action)
    ->  apply_action(Atoms0, Action, Atoms),
        append(Prefix, [enemy_action(Action)], Events)
    ;   Atoms = Atoms0,
        append(Prefix, [enemy_wait(no_legal_action)], Events)
    ).

%% solve_(+Atoms,+Options,-Outcome) is det.
solve_(Atoms, Options, Outcome) :-
    (   opt_(outcome, Options, none, Outcome0),
        Outcome0 \== none
    ->  Outcome = Outcome0
    ;   opt_(solver, Options, none, Solver),
        Solver \== none
    ->  call(Solver, Atoms, Outcome)
    ;   Outcome = planner_error(no_solver, 'no solver configured')
    ).

% ---------------------------------------------------------------------------
% 确定性回退
% ---------------------------------------------------------------------------

%% fallback_action(+Atoms,+Options,-Action) is semidet.
%  规划器无解或给出的计划不可用时使用：优先选朝 fallback_target 靠近的合法
%  移动，否则随便挑一个合法动作，一个都没有就失败（调用方输出 enemy_wait）。
fallback_action(Atoms, Options, Action) :-
    opt_(fallback_target, Options, none, Target),
    findall(A, legal_action(Atoms, A), Legal),
    Legal \== [],
    (   Target \== none,
        distances(Atoms, Target, Dist),
        member(A, Legal),
        moves_closer_(A, Dist)
    ->  Action = A
    ;   member(Action, Legal)
    ).

moves_closer_(Action, Dist) :-
    (   Action = move_thief(From, To)
    ;   Action = move_warden(From, To)
    ),
    dist_of_(Dist, From, DFrom),
    dist_of_(Dist, To, DTo),
    DTo < DFrom.

dist_of_(Dist, Loc, D) :- memberchk(Loc-D, Dist).

%% distances(+Atoms,+Origin,-Pairs) is det.
%  按 link/2 做广度优先，得到 Origin 到各房间的最短步数，元素为 Loc-Steps。
distances(Atoms, Origin, Pairs) :-
    findall(link(F, T), member(link(F, T), Atoms), Forward),
    findall(link(T, F), member(link(F, T), Atoms), Backward),
    append(Forward, Backward, Edges),
    bfs_([Origin-0], Edges, [], Pairs).

bfs_([], _, Seen, Seen).
bfs_([L-D|Queue], Edges, Seen0, Seen) :-
    (   memberchk(L-_, Seen0)
    ->  bfs_(Queue, Edges, Seen0, Seen)
    ;   D1 is D + 1,
        findall(N-D1, member(link(L, N), Edges), Next),
        append(Queue, Next, Queue1),
        bfs_(Queue1, Edges, [L-D|Seen0], Seen)
    ).

% ---------------------------------------------------------------------------
% 工具
% ---------------------------------------------------------------------------

goal_key_(Goal, Key) :-
    (   Goal == []
    ->  Key = none
    ;   term_hash(Goal, Hash),
        atomic_list_concat(['g', Hash], Key)
    ).

opt_(Key, Options, Default, Value) :-
    (   opt_in_(Key, Options, V)
    ->  Value = V
    ;   Value = Default
    ).

opt_in_(Key, [Opt|_], Value) :-
    compound(Opt),
    Opt =.. [Key|Args],
    Args = [Value].
opt_in_(Key, [_|Rest], Value) :-
    opt_in_(Key, Rest, Value).
