/*  planner_bridge.pl -- Prolog 状态转 PDDL、规划调用与计划缓存。负责人：丙。
 *
 *  本文件只做三件事：
 *    1. 把一份"世界摘要"渲染成 problem.pddl（render_problem/2, write_problem/2）
 *    2. 调用 pyperplan 拿到计划（solve_problem/3,4）
 *    3. 缓存计划并处理失效（plan_cache_* / advance_plan/2）
 *
 *  它刻意不依赖甲的状态库：世界摘要由调用方给出，格式是
 *
 *      spec(Name, DomainName, Objects, Init, Goal)
 *
 *  其中 Objects 是 [Type-[obj1,obj2,...], ...]，Init 和 Goal 是 PDDL 原子
 *  对应的 Prolog 项，例如 thief_at(vault)、link(vault,archive)。
 *  真正"从 game_state 读状态"的那一层（state_atoms/1）等甲确定
 *  谓词与 snapshot 形状后再接，见 INTERFACE.md。
 *
 *  渲染约定：
 *    - 输出 UTF-8、无 BOM、LF 换行（见 .gitattributes 与 P0 记录）
 *    - 0 元谓词直接写原子名（pyperplan 2.1 支持，已实测）
 *    - 前置条件里不能出现 not（pyperplan 限制，已实测）
 */

:- module(planner_bridge,
          [ render_problem/2
          , write_problem/2
          , solve_problem/2
          , solve_problem/3
          , problem_path/3
          , adversary_domain/1
          , plan_goal_key/2
          , plan_cache_lookup/3
          , plan_cache_store/3
          , plan_cache_clear/0
          , cached_plan/1
          , advance_plan/2
          ]).

:- use_module(library(readutil)).
:- use_module(config).
:- use_module(pyperplan_runner).

:- dynamic plan_cache_/3.        % plan_cache_(Version, GoalKey, Plan)

%% render_problem(+Spec,-Text) is det.
render_problem(Spec, Text) :-
    with_output_to(string(Text), render_problem_(Spec)).

render_problem_(spec(Name, Domain, Objects, Init, Goal)) :-
    format("(define (problem ~w)~n", [Name]),
    format("  (:domain ~w)~n", [Domain]),
    format("  (:objects~n"),
    forall(member(Type-ObjList, Objects), render_object_line_(Type, ObjList)),
    format("  )~n"),
    format("  (:init~n"),
    forall(member(A, Init), render_fact_line_(A)),
    format("  )~n"),
    format("  (:goal (and~n"),
    forall(member(G, Goal), render_fact_line_(G)),
    format("  ))~n"),
    format(")~n", []).

render_object_line_(Type, ObjList) :-
    atomic_list_concat(ObjList, ' ', Names),
    format("    ~w - ~w~n", [Names, Type]).

render_fact_line_(Fact) :-
    format("    "),
    render_fact_(Fact),
    format("~n", []).

render_fact_(Fact) :-
    (   compound(Fact)
    ->  Fact =.. [Name|Args],
        atomic_list_concat(Args, ' ', ArgText),
        format("(~w ~w)", [Name, ArgText])
    ;   format("(~w)", [Fact])
    ).

%% write_problem(+Spec,+Path) is det.
%  UTF-8 无 BOM。Prolog 的 encoding(utf8) 写出去不带 BOM，这是刻意的：
%  pyperplan 遇到 BOM 会报 ParseError（P0 已实测）。
write_problem(Spec, Path) :-
    render_problem(Spec, Text),
    setup_call_cleanup(
        open(Path, write, Out, [encoding(utf8)]),
        format(Out, "~s", [Text]),
        close(Out)).

%% problem_path(+Spec,+Version,-Path) is det.
%  每个 (版本, 目标) 组合一个文件，避免误读上一次的计划。
problem_path(Spec, Version, Path) :-
    plan_goal_key(Spec, GoalKey),
    atomic_list_concat(['p_', Version, '_', GoalKey, '.pddl'], File),
    config:runtime_path(File, Path).

%% plan_goal_key(+Spec,-Key) is det.
plan_goal_key(spec(_, _, _, _, Goal), Key) :-
    term_hash(Goal, Hash),
    atomic_list_concat(['g', Hash], Key).

%% adversary_domain(-Path) is semidet.
adversary_domain(Path) :-
    config:project_path('adversary_domain.pddl', Path),
    exists_file(Path).

%% solve_problem(+Spec,-Outcome) is det.
solve_problem(Spec, Outcome) :-
    solve_problem(Spec, [], Outcome).

%% solve_problem(+Spec,+Options,-Outcome) is det.
%  Options: version(+Int) 默认 0；domain(+Path)；timeout(+Seconds) 默认 10
%  Outcome = plan(+Actions) | no_solution | planner_error(+Status,+Message)
solve_problem(Spec, Options, Outcome) :-
    option_value(version, Options, 0, Version),
    option_value(timeout, Options, 10, Timeout),
    (   option_value(domain, Options, none, DomainOpt),
        DomainOpt \== none
    ->  Domain = DomainOpt
    ;   adversary_domain(Domain)
    ->  true
    ;   Outcome = planner_error(no_domain, 'adversary_domain.pddl not found')
    ),
    (   var(Outcome)
    ->  config:ensure_runtime_dir,
        problem_path(Spec, Version, ProblemFile),
        write_problem(Spec, ProblemFile),
        (   config:planner_exe(Exe)
        ->  run_pyperplan_plan(Exe, Domain, ProblemFile, [timeout(Timeout)], Outcome)
        ;   Outcome = planner_error(no_planner,
                                    'no pyperplan executable found: set PYPERPLAN_EXE or create config.local.pl')
        )
    ;   true
    ).

%% option_value(+Key,+Options,+Default,-Value) is det.
option_value(Key, Options, Default, Value) :-
    (   option_in_(Key, Options, V)
    ->  Value = V
    ;   Value = Default
    ).

option_in_(Key, [Opt|_], Value) :-
    compound(Opt),
    Opt =.. [Key|Args],
    Args = [Value].
option_in_(Key, [_|Rest], Value) :-
    option_in_(Key, Rest, Value).

%% plan_cache_lookup(+Version,+GoalKey,-Plan) is semidet.
plan_cache_lookup(Version, GoalKey, Plan) :-
    plan_cache_(Version, GoalKey, Plan).

%% plan_cache_store(+Version,+GoalKey,+Plan) is det.
plan_cache_store(Version, GoalKey, Plan) :-
    retractall(plan_cache_(Version, GoalKey, _)),
    assertz(plan_cache_(Version, GoalKey, Plan)).

%% plan_cache_clear is det.
plan_cache_clear :-
    retractall(plan_cache_(_, _, _)).

%% cached_plan(-Plan) is semidet.
cached_plan(Plan) :-
    plan_cache_(_, _, Plan).

%% advance_plan(+Plan,-Rest) is semidet.
%  执行完自己计划的第一步后，尾部仍然有效。注意：这时**不要**递增
%  world_version，否则缓存永远命中不了（见 INTERFACE.md 的失效规则）。
advance_plan([_|Rest], Rest).
