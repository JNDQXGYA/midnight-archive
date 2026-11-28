/*  pyperplan_runner.pl -- JC4002 Group 17 (maintained by member C)
 *
 *  Based on the runner supplied with the assessment.  All changes below were
 *  verified with SWI-Prolog 11.0.1 and Pyperplan 2.1 on Windows.
 *
 *  1. A stale <problem>.soln is deleted before every call.  Without this, an
 *     unsolvable problem silently returns the plan of an earlier call.
 *  2. The original exit-status test `Status = exit(0)` could never succeed,
 *     because process_wait/2 already unifies Status with the integer.
 *     Fixed with (=:=)/2.  "No solution" is now reported separately from a
 *     planner crash.
 *  3. A UTF-8 BOM in a .pddl file makes Pyperplan fail with
 *     `ParseError: Expected '(', got \ufeff`.  ensure_no_bom/1 strips it.
 *  4. Optional call timeout, so a hung planner cannot freeze the game.
 *
 *  Public interface:
 *    run_pyperplan_soln(+Exe,+Domain,+Problem,-Actions)
 *        Throws error(no_solution(Problem),_) or
 *               error(planner_error(Status,Stderr),_) on failure.
 *    run_pyperplan_plan(+Exe,+Domain,+Problem,-Outcome)
 *    run_pyperplan_plan(+Exe,+Domain,+Problem,+Options,-Outcome)
 *        Outcome = plan(Actions) | no_solution | planner_error(Status,Stderr)
 *        Options: timeout(+Seconds) (default 10)
 *    read_plan_file(+SolnFile,-Actions)
 *    ensure_no_bom(+File)
 */

:- module(pyperplan_runner,
          [ run_pyperplan_soln/4
          , run_pyperplan_plan/4
          , run_pyperplan_plan/5
          , read_plan_file/2
          , ensure_no_bom/1
          ]).

:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(pcre)).
:- use_module(library(option)).

%% run_pyperplan_soln(+Exe,+Domain,+Problem,-Actions) is det.
run_pyperplan_soln(Exe, Domain, Problem, Actions) :-
    run_pyperplan_plan(Exe, Domain, Problem, Outcome),
    outcome_actions_(Outcome, Problem, Actions).

outcome_actions_(plan(Actions), _, Actions).
outcome_actions_(no_solution, Problem, _) :-
    throw(error(no_solution(Problem), context(run_pyperplan_soln/4, _))).
outcome_actions_(planner_error(Status, Stderr), _, _) :-
    throw(error(planner_error(Status, Stderr), context(run_pyperplan_soln/4, _))).

%% run_pyperplan_plan(+Exe,+Domain,+Problem,-Outcome) is det.
run_pyperplan_plan(Exe, Domain, Problem, Outcome) :-
    run_pyperplan_plan(Exe, Domain, Problem, [], Outcome).

%% run_pyperplan_plan(+Exe,+Domain,+Problem,+Options,-Outcome) is det.
run_pyperplan_plan(Exe, Domain, Problem, Options, Outcome) :-
    option(timeout(Timeout), Options, 10),
    soln_path_(Problem, SolnFile),
    prepare_(Domain, Problem, SolnFile),
    (   catch(call_with_time_limit(
                  Timeout,
                  invoke_(Exe, Domain, Problem, Status, Stderr)),
              error(time_limit_exceeded, _),
              fail)
    ->  classify_(Status, Stderr, SolnFile, Outcome)
    ;   format(string(Msg), "planner did not finish within ~w s", [Timeout]),
        Outcome = planner_error(timeout, Msg)
    ).

invoke_(Exe, Domain, Problem, Status, Stderr) :-
    setup_call_cleanup(
        process_create(Exe, [Domain, Problem],
                       [ stdout(null),
                         stderr(pipe(Err)),
                         process(PID)
                       ]),
        read_string(Err, _, Stderr),
        close(Err)),
    process_wait(PID, exit(Status)).

prepare_(Domain, Problem, SolnFile) :-
    ensure_no_bom(Domain),
    ensure_no_bom(Problem),
    (   exists_file(SolnFile)
    ->  catch(delete_file(SolnFile), _, true)
    ;   true
    ).

classify_(Status, Stderr, SolnFile, Outcome) :-
    (   Status =:= 0
    ->  (   exists_file(SolnFile)
        ->  (   catch(read_plan_file(SolnFile, Actions), _, fail)
            ->  Outcome = plan(Actions)
            ;   Outcome = no_solution
            )
        ;   Outcome = no_solution
        )
    ;   Outcome = planner_error(Status, Stderr)
    ).

%% ensure_no_bom(+File) is det.
%  Removes a leading UTF-8 BOM, if any.  Idempotent: a BOM-free file is
%  left untouched.  Silently succeeds if the file cannot be read.
ensure_no_bom(File) :-
    (   exists_file(File),
        catch(read_file_to_codes(File, [0xEF,0xBB,0xBF|Rest], [encoding(octet)]), _, fail)
    ->  setup_call_cleanup(
            open(File, write, Out, [encoding(octet)]),
            forall(member(B, Rest), put_byte(Out, B)),
            close(Out)),
        format(user_error, "~w: UTF-8 BOM removed~n", [File])
    ;   true
    ).

%% read_plan_file(+SolnFile,-Actions) is det.
read_plan_file(SolnFile, Actions) :-
    (   exists_file(SolnFile)
    ->  setup_call_cleanup(
            open(SolnFile, read, In, [encoding(utf8)]),
            read_string(In, _, Content0),
            close(In)),
        (   string_concat("\uFEFF", Content, Content0)
        ->  true
        ;   Content = Content0
        ),
        parse_plan_text_(Content, Actions)
    ;   throw(error(existence_error(file, SolnFile), _))
    ).

soln_path_(Problem, SolnFile) :-
    atom_string(Problem, PStr),
    string_concat(PStr, ".soln", SStr),
    atom_string(SolnFile, SStr).

parse_plan_text_(Text, Actions) :-
    split_string(Text, "\n", "\r", Lines0),
    include(has_paren_, Lines0, Lines),
    maplist(line_to_action_term_, Lines, Actions).

has_paren_(Line) :- sub_string(Line, _, _, _, "(").

line_to_action_term_(Line, Term) :-
    (   re_matchsub("\\(([^\\)]+)\\)", Line, Dict, [])
    ->  Str = Dict.1,
        string_lower(Str, Low),
        split_string(Low, " ", " \t", Parts),
        maplist(atom_string, Atoms, Parts),
        Atoms = [Name|Args],
        Term =.. [Name|Args]
    ;   atom_string(Term, Line)
    ).