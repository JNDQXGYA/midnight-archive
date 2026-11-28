/*  t_runner.pl -- pyperplan_runner 回归测试。负责人：丙。
 *
 *  运行（项目根目录）：
 *      swipl -q -g "main, halt" tests/integration/t_runner.pl
 *
 *  这三个用例对应我们修掉的三处问题，测试文件在运行时生成，
 *  不往仓库里提交带 BOM 的 PDDL 或陈旧的 .soln：
 *    1. stale  -- 先种一个假 .soln，再求解，必须拿到真计划而不是假计划
 *    2. unsolvable -- 目标不可达，必须得到 no_solution 而不是崩溃
 *    3. bom   -- problem 文件带头 UTF-8 BOM，必须被自动剥掉后正常求解
 */

:- use_module('../../planner_bridge.pl').
:- use_module('../../pyperplan_runner.pl').

main :-
    flag(failures, _, 0),
    config:ensure_runtime_dir,
    config:project_path('tests/fixtures/adversary_domain_snapshot.pddl', Domain),
    config:planner_exe_report(Report),
    format("~nplanner: ~q~n~n", [Report]),
    run_stale(Domain),
    run_unsolvable(Domain),
    run_bom(Domain),
    flag(failures, F, F),
    (   F =:= 0
    ->  format("~nALL PASS~n")
    ;   format("~n~w FAILURE(S)~n", [F])
    ),
    (   F =:= 0 -> halt(0) ; halt(1) ).

solvable_spec(spec('runner_solvable', 'midnight_archive_adversaries',
                   [ location-[vault, archive, atrium, entrance] ],
                   [ link(vault, archive),
                     link(archive, atrium),
                     player_at(entrance),
                     thief_at(vault),
                     warden_at(atrium),
                     core_at(atrium),
                     phase_race,
                     exit_unsealed,
                     carrier_unmarked
                   ],
                   [ thief_holds_core ])).

% 星核不在任何地方 => take_core 永远不可用 => 无解
unsolvable_spec(spec('runner_unsolvable', 'midnight_archive_adversaries',
                     [ location-[vault, archive, atrium, entrance] ],
                     [ link(vault, archive),
                       link(archive, atrium),
                       player_at(entrance),
                       thief_at(vault),
                       warden_at(atrium),
                       phase_race,
                       exit_unsealed,
                       carrier_unmarked
                     ],
                     [ thief_holds_core ])).

% 1. 陈旧 .soln
run_stale(Domain) :-
    solvable_spec(Spec),
    case_file(stale, Problem),
    config:planner_exe(Exe),
    write_problem(Spec, Problem),
    atom_concat(Problem, '.soln', Soln),
    plant_soln_(Soln, "(bogus_action)"),
    format("[stale]~n"),
    run_pyperplan_plan(Exe, Domain, Problem, Outcome),
    check(( Outcome = plan(Plan),
            Plan \= [],
            \+ memberchk(bogus_action, Plan),
            Plan = [move_thief(vault,archive)|_] ),
          'stale .soln is replaced by a real plan').

% 2. 无解
run_unsolvable(Domain) :-
    unsolvable_spec(Spec),
    case_file(unsolvable, Problem),
    config:planner_exe(Exe),
    write_problem(Spec, Problem),
    format("~n[unsolvable]~n"),
    run_pyperplan_plan(Exe, Domain, Problem, Outcome),
    check(Outcome == no_solution, 'unsolvable problem yields no_solution'),
    check(( catch(run_pyperplan_soln(Exe, Domain, Problem, _), Err, true),
            Err = error(no_solution(_), _) ),
          'run_pyperplan_soln throws no_solution').

% 3. BOM
run_bom(Domain) :-
    solvable_spec(Spec),
    case_file(bom, Problem),
    config:planner_exe(Exe),
    write_problem(Spec, Problem),
    prepend_bom_(Problem),
    format("~n[bom]~n"),
    check(( read_first_bytes_(Problem, [0xEF,0xBB,0xBF]) ),
          'fixture really starts with a BOM'),
    run_pyperplan_plan(Exe, Domain, Problem, Outcome),
    check(( Outcome = plan([move_thief(vault,archive)|_]) ),
          'BOM is stripped and the problem is solved').

case_file(Name, Path) :-
    atomic_list_concat(['runner_', Name, '.pddl'], File),
    config:runtime_path(File, Path).

plant_soln_(File, Text) :-
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       format(Out, "~w~n", [Text]),
                       close(Out)).

prepend_bom_(File) :-
    read_file_to_codes(File, Codes, [encoding(octet)]),
    setup_call_cleanup(open(File, write, Out, [encoding(octet)]),
                       format(Out, "~s", [[0xEF,0xBB,0xBF|Codes]]),
                       close(Out)).

read_first_bytes_(File, Bytes) :-
    setup_call_cleanup(open(File, read, In, [encoding(octet)]),
                       read_string(In, 3, Head),
                       close(In)),
    string_codes(Head, Bytes).

check(Goal, Name) :-
    (   catch(call(Goal), E, (format("  error: ~q~n", [E]), fail))
    ->  format("  PASS  ~w~n", [Name])
    ;   format("  FAIL  ~w~n", [Name]),
        flag(failures, N, N+1)
    ).
