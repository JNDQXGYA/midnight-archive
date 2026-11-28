% config.local.example.pl -- 本机配置模板。负责人：丙。
%
% 用法：复制成 config.local.pl 后按本机情况修改。
% config.local.pl 已被 .gitignore 忽略，不会进入仓库，也不会被别人看到。
%
% 优先级低于环境变量 PYPERPLAN_EXE，高于项目内 .venv 与 PATH。

% 本机 pyperplan 可执行文件的绝对路径（Windows 用 / 分隔，Prolog 里也可以直接写 \ 但要转义）
local_override(planner_exe, 'C:/path/to/venv/Scripts/pyperplan.exe').

% 例如本仓库作者本机：
% local_override(planner_exe, 'F:/new-desk/KnowlegeRepresent/tools/venv/Scripts/pyperplan.exe').
