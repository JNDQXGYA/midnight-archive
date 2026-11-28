/*  t_bridge.pl -- planner_bridge 集成测试。负责人：丙。
 *
 *  运行（在项目根目录）：
 *      swipl -q -g "main, halt" tests/integration/t_bridge.pl
 *
 *  覆盖：problem.pddl 渲染、调用 pyperplan 取计划、计划缓存与失效、计划推进。
 *  不需要甲的状态库，也不需要乙的正式领域文件。
 */

:- use_module('../../planner_bridge.pl').

main :-
    flag(failures, _, 0),
    mock_spec(Spec),
    format("~n[render]~n"),
    test_render(Spec),
    format("~n[solve]~n"),
    test_solve(Spec),
    format("~n[cache]~n"),
    test_cache(Spec),
    format("~n[advance]~n"),
    test_advance,
    flag(failures, F, F),
    (   F =:= 0
    ->  format("~nALL PASS~n")
    ;   format("~n~w FAILURE(S)~n", [F])
    ),
    (   F =:= 0 -> halt(0) ; halt(1) ).

% 与 mock_domain.pddl 同构的最小世界：两个对手，一个目标。
mock_spec(spec('mock_1_1', 'mock_archive',
               [ loc-[vault, archive, atrium, entrance],
                 mode-[race, recover, locked, open, sealed, unmarked, marked]
               ],
               [ link(vault, archive),
                 link(archive, atrium),
                 at_player(entrance),
                 at_thief(vault),
                 at_warden(atrium),
                 at_core(atrium),
                 phase(race),
                 gate(locked),
                 carrier(unmarked)
               ],
               [ thief_holds_core ])).

test_render(Spec) :-
    check(( render_problem(Spec, T),
            sub_string(T, _, _, _, "(define (problem mock_1_1)") ),
          'render: problem header'),
    check(( render_problem(Spec, T),
            sub_string(T, _, _, _, "(:domain mock_archive)") ),
          'render: domain name'),
    check(( render_problem(Spec, T),
            sub_string(T, _, _, _, "(at_thief vault)") ),
          'render: init fact'),
    check(( render_problem(Spec, T),
            sub_string(T, _, _, _, "vault archive atrium entrance - loc") ),
          'render: typed objects'),
    check(( render_problem(Spec, T),
            \+ sub_string(T, _, _, _, "\r") ),
          'render: LF only, no CR'),
    check(( render_problem(Spec, T),
            \+ sub_string(T, 0, 1, _, "\uFEFF") ),
          'render: no BOM').

test_solve(Spec) :-
    config:project_path('tests/fixtures/mock_domain.pddl', Domain),
    check(( exists_file(Domain) ), 'solve: mock domain file present'),
    check(( solve_problem(Spec, [domain(Domain), version(1)], Outcome),
            Outcome == plan([ move_thief(vault,archive),
                              move_thief(archive,atrium),
                              take_core(atrium) ]) ),
          'solve: expected plan').

test_cache(Spec) :-
    plan_goal_key(Spec, Key),
    plan_cache_store(7, Key, [move_thief(vault,archive)]),
    check(( plan_cache_lookup(7, Key, P),
            P == [move_thief(vault,archive)] ),
          'cache: store then lookup'),
    check(( \+ plan_cache_lookup(8, Key, _) ),
          'cache: different version misses'),
    plan_cache_clear,
    check(( \+ cached_plan(_) ), 'cache: clear removes everything').

test_advance :-
    check(( advance_plan([a,b,c], Rest), Rest == [b,c] ),
          'advance: drops the executed head').

check(Goal, Name) :-
    (   catch(call(Goal), E, (format("  error: ~q~n", [E]), fail))
    ->  format("  PASS  ~w~n", [Name])
    ;   format("  FAIL  ~w~n", [Name]),
        flag(failures, N, N+1)
    ).
