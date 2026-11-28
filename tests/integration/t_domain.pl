/*  t_domain.pl -- 领域文件与执行层前置条件表的一致性检查。负责人：丙。
 *
 *  运行（项目根目录）：
 *      swipl -q -g "main, halt" tests/integration/t_domain.pl
 *
 *  为什么需要这个测试：
 *  adversary_execution.pl 里的 preconditions/2 是"运行时那一份"规则，
 *  adversary_domain.pddl 是"规划器那一份"，两者必须一致。乙改了 domain 的
 *  动作名、参数个数或者加删动作，而执行层没跟上，症状是"规划器给出的计划
 *  每一步都被判非法"，最后每回合都退化成回退分支——最难查的一类 bug。
 *
 *  这个测试只比对"动作名 + 参数个数"，不比对前置条件的具体内容（那需要真正的
 *  PDDL 解析器）。动作名和 arity 是最容易漂移的部分，先卡住这一层。
 *
 *  想拿它检查正式领域，把 domain 参数换成 'adversary_domain.pddl' 即可。
 */

:- use_module(library(pcre)).
:- use_module('../../adversary_execution.pl').
:- use_module('../../config.pl').

% 执行层认识的动作
expected_signature(move_thief/2).
expected_signature(move_warden/2).
expected_signature(take_core/1).
expected_signature(secure_core/1).
expected_signature(mark_carrier/1).
expected_signature(seal_exit/1).
expected_signature(capture_carrier/1).

main :-
    flag(failures, _, 0),
    config:project_path('tests/fixtures/adversary_domain_snapshot.pddl', Mock),
    format("~n[execution table]~n"),
    test_table,
    format("~n[domain: mock_domain.pddl]~n"),
    check_domain(Mock),
    flag(failures, F, F),
    (   F =:= 0
    ->  format("~nALL PASS~n")
    ;   format("~n~w FAILURE(S)~n", [F])
    ),
    (   F =:= 0 -> halt(0) ; halt(1) ).

% 执行层自己：每个 expected_signature 都要有 preconditions 和 effect
test_table :-
    findall(F/A, ( adversary_execution:preconditions(H, _), functor(H, F, A) ), PreTable),
    findall(F/A, ( adversary_execution:effect(H, _, _), functor(H, F, A) ), EffTable),
    forall(expected_signature(Sig),
           ( label('preconditions', Sig, Name1),
             check(memberchk(Sig, PreTable), Name1) )),
    forall(expected_signature(Sig),
           ( label('effect', Sig, Name2),
             check(memberchk(Sig, EffTable), Name2) )).

check_domain(File) :-
    (   exists_file(File)
    ->  domain_actions(File, Actions),
        format("  parsed from ~w: ~q~n", [File, Actions]),
        forall(member(Sig, Actions), check_action_(Sig)),
        forall(expected_signature(Sig),
               (   memberchk(Sig, Actions)
               ->  true
               ;   format("  note  ~w is not modelled in this file (fine for the mock)~n", [Sig])
               ))
    ;   ( label('domain file missing', File, Name4), check(fail, Name4) )
    ).

check_action_(Sig) :-
    (   expected_signature(Sig)
    ->  label('domain action matches the table', Sig, Name1),
        check(true, Name1)
    ;   expected_signature(F/A0),
        Sig = F/A0
    ->  label('domain action arity mismatch', Sig, Name2),
        check(fail, Name2)
    ;   label('domain action unknown to adversary_execution', Sig, Name3),
        check(fail, Name3)
    ).

% --- PDDL 动作签名提取 -------------------------------------------------------

domain_actions(File, Actions) :-
    read_file_to_string(File, Text, [encoding(utf8)]),
    re_split(":action", Text, [_Header|Chunks]),
    exclude(empty_chunk_, Chunks, Named),
    maplist(chunk_action_, Named, Actions).

empty_chunk_(Chunk) :-
    \+ re_matchsub("^\\s*[a-z][a-z_0-9]*", Chunk, _, []).

chunk_action_(Chunk, Name/Arity) :-
    re_matchsub("^\\s*([a-z][a-z_0-9]*)", Chunk, D, []),
    atom_string(Name, D.1),
    (   re_matchsub(":parameters\\s*\\(([^)]*)\\)", Chunk, D2, [])
    ->  count_parameters_(D2.1, Arity)
    ;   Arity = 0
    ).

count_parameters_(ParamText, N) :-
    findall(x, sub_string(ParamText, _, 1, _, "?"), Marks),
    length(Marks, N).

% --- 小工具 -----------------------------------------------------------------

label(Kind, Sig, String) :-
    format(string(String), "~w: ~w", [Kind, Sig]).

check(Goal, Name) :-
    (   catch(call(Goal), E, (format("  error: ~q~n", [E]), fail))
    ->  format("  PASS  ~w~n", [Name])
    ;   format("  FAIL  ~w~n", [Name]),
        flag(failures, N, N+1)
    ).
