/*  config.pl -- 可提交的公共配置。负责人：丙。
 *
 *  规划器可执行文件按以下顺序解析：
 *    1. 环境变量 PYPERPLAN_EXE
 *    2. config.local.pl 里的 local_override(planner_exe, Exe)
 *       （本机文件，已被 .gitignore 忽略，不进仓库）
 *    3. 项目内 .venv / venv 的 pyperplan
 *    4. PATH 上的 pyperplan
 *
 *  全部失败时 planner_exe/1 失败。调用方必须给出明确提示并走回退策略，
 *  不得假装规划成功。
 */

:- module(config,
          [ planner_exe/1
          , planner_exe_source/2
          , planner_exe_report/1
          , project_root/1
          , project_path/2
          , runtime_dir/1
          , runtime_path/2
          , ensure_runtime_dir/0
          ]).

:- dynamic local_override/2.
:- dynamic project_root_/1.

:- initialization(set_project_root_).
:- initialization(load_local_config_).

set_project_root_ :-
    (   prolog_load_context(directory, Dir)
    ->  true
    ;   Dir = '.'
    ),
    retractall(project_root_(_)),
    assertz(project_root_(Dir)).

load_local_config_ :-
    project_root(Root),
    atomic_list_concat([Root, /, 'config.local.pl'], File),
    (   exists_file(File)
    ->  catch(consult(File), E, print_message(warning, E))
    ;   true
    ).

%% project_root(-Dir) is det.
project_root(Root) :- project_root_(Root).

%% project_path(+Relative,+Absolute) is det.
project_path(Rel, Abs) :-
    project_root(Root),
    atomic_list_concat([Root, /, Rel], Abs).

%% runtime_dir(-Dir) is det.
runtime_dir(Dir) :-
    project_path('runtime', Dir).

%% runtime_path(+File,-Path) is det.
runtime_path(File, Path) :-
    atomic_list_concat(['runtime/', File], Rel),
    project_path(Rel, Path).

%% ensure_runtime_dir is det.
%  runtime/ 存在（有 .gitkeep），但换台机器 clone 后仍然可能缺，这里保证它存在。
ensure_runtime_dir :-
    runtime_dir(Dir),
    (   exists_directory(Dir)
    ->  true
    ;   make_directory_path(Dir)
    ).

%% planner_exe(-Exe) is semidet.
planner_exe(Exe) :-
    planner_exe_source(Exe, _).

%% planner_exe_source(-Exe,-Source) is semidet.
planner_exe_source(Exe, env) :-
    catch(getenv('PYPERPLAN_EXE', V), _, fail),
    V \== '',
    exists_file(V),
    Exe = V.

planner_exe_source(Exe, local) :-
    local_override(planner_exe, V),
    V \== '',
    exists_file(V),
    Exe = V.

planner_exe_source(Exe, venv) :-
    member(Rel, [ '.venv/Scripts/pyperplan.exe'
                , 'venv/Scripts/pyperplan.exe'
                , '.venv/bin/pyperplan'
                , 'venv/bin/pyperplan'
                ]),
    project_path(Rel, Exe),
    exists_file(Exe).

planner_exe_source(Exe, path) :-
    path_executable_('pyperplan', Exe).

%% planner_exe_report(-Report) is det.
%  Report = planner(Source, Exe) | planner(not_found, none)
planner_exe_report(Report) :-
    (   planner_exe_source(Exe, Source)
    ->  Report = planner(Source, Exe)
    ;   Report = planner(not_found, none)
    ).

%% path_executable_(+Name,-Path) is semidet.
path_executable_(Name, Path) :-
    (   current_prolog_flag(windows, true)
    ->  Sep = ';', Exts = ['.exe', '.cmd', '.bat']
    ;   Sep = ':',  Exts = ['']
    ),
    catch(getenv('PATH', PathStr), _, fail),
    atomic_list_concat(Dirs, Sep, PathStr),
    member(Dir, Dirs),
    Dir \== '',
    member(Ext, Exts),
    atomic_list_concat([Dir, /, Name, Ext], Cand),
    exists_file(Cand),
    Path = Cand,
    !.
