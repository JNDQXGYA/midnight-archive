/*  t_execution.pl -- adversary_execution 集成测试。负责人：丙。
 *
 *  运行（项目根目录）：
 *      swipl -q -g "main, halt" tests/integration/t_execution.pl
 *
 *  全部用假的世界状态和"给定的求解结果"驱动，不依赖甲的状态库，
 *  也不依赖乙的正式领域文件：验证的是校验、执行、失效、回退这一层逻辑。
 */

:- use_module('../../adversary_execution.pl').
:- use_module('../../planner_bridge.pl').

main :-
    flag(failures, _, 0),
    format("~n[validate]~n"),
    test_validate,
    format("~n[apply]~n"),
    test_apply,
    format("~n[simulate]~n"),
    test_simulate,
    format("~n[turn: legal plan]~n"),
    test_turn_legal,
    format("~n[turn: illegal plan]~n"),
    test_turn_illegal,
    format("~n[turn: no solution]~n"),
    test_turn_no_solution,
    format("~n[turn: cached plan reused]~n"),
    test_turn_cache,
    flag(failures, F, F),
    (   F =:= 0
    ->  format("~nALL PASS~n")
    ;   format("~n~w FAILURE(S)~n", [F])
    ),
    (   F =:= 0 -> halt(0) ; halt(1) ).

% 与 mock_domain.pddl 同构的世界：星核在中庭，盗影在库房，守夜人在档案室。
base_atoms([ link(vault, archive),
             link(archive, atrium),
             player_at(entrance),
             thief_at(vault),
             warden_at(atrium),
             core_at(atrium),
             phase_race,
             exit_unsealed,
             carrier_unmarked ]).

test_validate :-
    base_atoms(Atoms),
    check(legal_action(Atoms, move_thief(vault,archive)), 'legal: move along a link'),
    check(\+ legal_action(Atoms, move_thief(vault,atrium)), 'illegal: no link vault->atrium'),
    check(\+ legal_action(Atoms, take_core(vault)), 'illegal: core is not in the vault'),
    check(\+ legal_action(Atoms, secure_core(vault)), 'illegal: thief holds no core yet'),
    check(\+ legal_action(Atoms, capture_carrier(atrium)), 'illegal: nothing marked/sealed'),
    check(( missing_preconditions(Atoms, take_core(vault), Missing),
            Missing == [core_at(vault)] ),
          'diagnostics: reports exactly the missing atom'),
    check(( missing_preconditions(Atoms, fly_away(x), Missing2),
            Missing2 == [unknown_action(fly_away(x))] ),
          'diagnostics: unknown action is reported too').

test_apply :-
    base_atoms(Atoms0),
    apply_action(Atoms0, move_thief(vault,archive), Atoms1),
    check(( memberchk(thief_at(archive), Atoms1),
            \+ memberchk(thief_at(vault), Atoms1) ),
          'apply: move updates the position'),
    apply_action(Atoms0, take_core(atrium), Atoms2),
    check(( memberchk(thief_holds_core, Atoms2),
            \+ memberchk(core_at(atrium), Atoms2) ),
          'apply: take_core moves the core to the thief'),
    apply_action(Atoms0, mark_carrier(atrium), Atoms3),
    check(( memberchk(carrier_marked, Atoms3),
            \+ memberchk(carrier_unmarked, Atoms3) ),
          'apply: mark replaces the previous carrier status'),
    apply_action(Atoms0, seal_exit(atrium), Atoms4),
    check(( memberchk(exit_sealed, Atoms4),
            \+ memberchk(exit_unsealed, Atoms4) ),
          'apply: seal replaces the previous gate state').

test_simulate :-
    base_atoms(Atoms0),
    Plan = [ move_thief(vault,archive),
             move_thief(archive,atrium),
             take_core(atrium) ],
    simulate_plan(Atoms0, Plan, Atoms),
    check(memberchk(thief_holds_core, Atoms), 'simulate: whole plan is executable'),
    check(( catch(simulate_plan(Atoms0, [take_core(vault)], _), Err, true),
            Err = error(illegal_action(take_core(vault), _), _) ),
          'simulate: illegal step throws with context').

test_turn_legal :-
    plan_cache_clear,
    base_atoms(Atoms0),
    adversary_turn(Atoms0,
                   [ version(11), goal([thief_holds_core]),
                     outcome(plan([move_thief(vault,archive),
                                   move_thief(archive,atrium)])) ],
                   Events, Atoms),
    check(Events == [enemy_action(move_thief(vault,archive))], 'turn: one action per turn'),
    check(memberchk(thief_at(archive), Atoms), 'turn: world advanced by exactly one step').

test_turn_illegal :-
    plan_cache_clear,
    base_atoms(Atoms0),
    adversary_turn(Atoms0,
                   [ version(12), goal([thief_holds_core]),
                     fallback_target(archive),
                     outcome(plan([take_core(vault)])) ],
                   Events, Atoms),
    check(( Events == [ invalid_action(take_core(vault)),
                        fallback(inconsistent_plan([core_at(vault)])),
                        enemy_action(move_thief(vault,archive)) ] ),
          'turn: illegal head rejected, fallback moves deterministically'),
    check(memberchk(thief_at(archive), Atoms), 'turn: fallback still changes the world').

test_turn_no_solution :-
    plan_cache_clear,
    base_atoms(Atoms0),
    adversary_turn(Atoms0,
                   [ version(13), goal([thief_holds_core]),
                     fallback_target(atrium),
                     outcome(no_solution) ],
                   Events, Atoms),
    check(( Events == [ fallback(no_solution),
                        enemy_action(move_thief(vault,archive)) ] ),
          'turn: no_solution falls back towards the target'),
    check(memberchk(thief_at(archive), Atoms), 'turn: atoms updated after fallback').

test_turn_cache :-
    plan_cache_clear,
    base_atoms(Atoms0),
    adversary_turn(Atoms0,
                   [ version(14), goal([thief_holds_core]),
                     outcome(plan([move_thief(vault,archive),
                                   move_thief(archive,atrium)])) ],
                   E1, Atoms1),
    check(E1 == [enemy_action(move_thief(vault,archive))], 'cache: first turn plans'),
    % 第二回合故意给一个会失败的求解结果：如果缓存生效，它根本不该被调用。
    adversary_turn(Atoms1,
                   [ version(14), goal([thief_holds_core]),
                     outcome(no_solution) ],
                   E2, Atoms2),
    check(E2 == [enemy_action(move_thief(archive,atrium))],
          'cache: second turn reuses the stored tail instead of replanning'),
    check(memberchk(thief_at(atrium), Atoms2), 'cache: cached step really executed').

check(Goal, Name) :-
    (   catch(call(Goal), E, (format("  error: ~q~n", [E]), fail))
    ->  format("  PASS  ~w~n", [Name])
    ;   format("  FAIL  ~w~n", [Name]),
        flag(failures, N, N+1)
    ).
