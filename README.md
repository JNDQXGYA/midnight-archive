# 星烛档案馆：午夜失窃

JC4002 Knowledge Representation 四人小组项目。项目目标是使用 SWI-Prolog 开发文字冒险游戏，并通过 PDDL 与 Pyperplan 驱动两名具有不同职责、能够动态改变目标并协作的对手。

> **仓库必须保持私有。** 本仓库用于课程小组内部协作，不得向其他小组或课程外人员分享代码、报告、运行记录或作业材料。正式代码、形式化内容与报告由小组成员共同实现、验证和解释。

## 当前状态

当前提交仅包含项目骨架、协作规约和课程提供的 Pyperplan 调用起始代码。游戏与 PDDL 模型尚未实现，因此暂时不能按完整游戏运行。

## 成员与职责

| 成员 | 主责 | 主要文件所有权 |
|---|---|---|
| 甲 | Prolog 核心、动态知识库、玩家规则与胜负条件 | `midnight_archive.pl`、`world.pl`、`game_state.pl`、`player_actions.pl` |
| 乙 | PDDL 领域、默认与演化目标、对手协作及规划测试 | `adversary_domain.pddl`、`adversary_problem.pddl`、`pddl_cases/` |
| 丙 | Pyperplan 集成、动作校验、计划失效、重规划与容错 | `planner_bridge.pl`、`adversary_execution.pl`、`pyperplan_runner.pl`、`config.pl` |
| 丁 | 文字界面、剧情内容、验收测试、通关记录、报告与展示 | `ui.pl`、`content.pl`、`acceptance_tests/`、`docs/`、`transcript.txt` |

所有成员都需要为自己的模块添加测试、提供报告技术说明、参与联调并准备口头问答。个人不得直接覆盖他人拥有的文件；跨模块修改必须通过 Pull Request 与文件负责人协商。

## 技术环境

全组统一使用：

- SWI-Prolog **11.0.0 stable**；
- Python **3.11.x**；
- Pyperplan **2.1**；
- PDDL 1.2 的 STRIPS＋typing 子集；
- UTF-8 编码与 LF 换行；
- Pyperplan 默认搜索配置。

不使用数值流、条件效果、否定前置条件、动作代价或时间动作。若教学机器无法支持统一版本，必须由全组共同决定调整，并在调整之后重新执行全部测试。

## 项目结构

```text
midnight-archive/
├── .gitattributes
├── .gitignore
├── README.md
├── requirements.txt
├── midnight_archive.pl          # start/0、start/1 与主流程
├── world.pl                     # 静态地图、物品属性与初始世界
├── game_state.pl                # 动态知识库与状态修改 API
├── player_actions.pl            # 玩家命令、回合、算术、随机性与胜负
├── adversary_domain.pddl        # 对手领域模型
├── adversary_problem.pddl       # 游戏开始时的默认问题
├── planner_bridge.pl            # Prolog 状态转 PDDL、规划调用与计划缓存
├── adversary_execution.pl       # 动作校验、执行、失效检测、重规划与回退
├── pyperplan_runner.pl          # 课程提供的规划器调用起始代码
├── config.pl                    # 可提交的公共配置
├── ui.pl                        # 地图、状态与事件输出
├── content.pl                   # 房间、物品与剧情文本
├── pddl_cases/                  # 默认、目标变化与协作规划测试
├── tests/
│   ├── unit/                    # Prolog 单元测试
│   ├── integration/             # 规划器与游戏集成测试
│   └── fixtures/                # 固定状态、输入与预期输出
├── docs/
│   └── assets/                  # 报告地图、流程图与展示材料
├── runtime/                     # 本地动态问题与计划文件，不提交生成物
├── transcript.txt               # 最终成功通关记录
└── report.pdf                   # 最终报告
```

## 环境安装

### 1. 安装 SWI-Prolog

安装 SWI-Prolog 11.0.0，并确保命令行可以执行：

```bash
swipl --version
```

官方下载页面：<https://www.swi-prolog.org/download/stable>

### 2. 创建 Python 环境

Windows PowerShell：

```powershell
py -3.11 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
pyperplan --help
```

macOS／Linux：

```bash
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
pyperplan --help
```

Pyperplan 的项目页面：<https://pypi.org/project/pyperplan/2.1/>

### 3. 配置规划器

公共配置放入 `config.pl`，本机路径放入 `config.local.pl`。不得把个人用户名、绝对路径或账号信息写进公共文件。

规划器位置优先从本机环境变量 `PYPERPLAN_EXE` 或 `config.local.pl` 获取；具体实现由丙负责。所有代码中的项目路径使用相对路径，不得依赖某一台电脑的目录结构。

### 4. 运行游戏

核心功能完成并联调通过后，统一从项目根目录启动：

```bash
swipl
```

```prolog
?- [midnight_archive].
?- start.
```

可复现测试使用：

```prolog
?- start(42).
```

当前骨架尚未提供上述谓词的可运行实现。

## 已冻结的首版游戏约定

- 玩家从 `entrance` 出发，取得 `observatory` 中的 `star_core`，再从 `gatehouse` 撤离。
- 盗影从 `vault` 出发，默认目标是抢先取得星核并送回库房。
- 守夜人从 `archive` 出发，默认目标是前往 `gatehouse` 驻守。
- 玩家取得星核后，阶段由 `race` 改为 `recover`，对手目标改为封锁出口、标记携带者并协作抓捕。
- 玩家可使用 `ward_charm` 清除标记，使用 `brass_key` 打开或解除闸门封锁。
- 初始灯火为 10、上限为 12，物品栏容量为 4；`lamp_oil` 恢复 4 点灯火。
- 每个有效消耗回合有 20% 概率出现穿堂风，额外消耗 1 点灯火。
- 上述平衡数值只能通过全组联调共同修改。

详细接口以全组确认的设计规约为准。任何状态谓词、PDDL 动作名、目标或文件职责变更，都必须同步修改相关模块和测试。

## 分支与协作流程

默认分支为 `main`，四名成员分别使用：

- 甲：`feature/core-kb`
- 乙：`feature/pddl-adversaries`
- 丙：`feature/planner-integration`
- 丁：`feature/ui-docs`

工作流程：

1. 开始工作前执行 `git switch main && git pull`。
2. 从最新 `main` 创建或更新自己的功能分支。
3. 小步提交，提交信息使用 `feat:`、`fix:`、`test:`、`docs:` 或 `refactor:` 前缀。
4. 推送功能分支并创建 Pull Request，不自审后直接合并。
5. 至少一名组员审查；涉及共享接口时，所有受影响模块负责人都要确认。
6. 合并后删除已经完成的远端功能分支，并同步本地 `main`。
7. 禁止向 `main` 强制推送，禁止提交本机环境、账号信息或生成中的临时计划文件。

建议 Issue 标签：`core`、`pddl`、`planner`、`ui`、`testing`、`docs`、`integration`。

## 联调节点

1. **M0：环境一致**——四人都能运行 SWI-Prolog 与 Pyperplan，并加载项目骨架。
2. **M1：独立模块**——玩家核心、PDDL 测试、模拟状态集成和模拟界面分别可演示。
3. **M2：完整闭环**——从 `start.` 开始，能够实际产生一次胜利和一次失败。
4. **M3：评分功能**——目标变化、对手协作、非法动作拒绝、无解回退和动态重规划全部通过测试。
5. **M4：交付冻结**——停止新增功能，完成跨平台测试、通关记录、报告、展示与 ZIP 检查。

## 最终提交检查

最终课程提交与 GitHub 开发仓库分开处理。提交前共同检查：

- ZIP 文件名符合 `JC4002-[PROGRAMME]-Group-[GROUP NO].zip`；
- 包含游戏代码、领域文件、默认问题文件、`transcript.txt` 和 `report.pdf`；
- `start.` 能启动游戏并打印命令；
- 成功通关记录来自真实运行；
- 口头展示准备胜利与失败两条路线；
- 报告不超过 3000 词，并符合课程排版与引用要求；
- 不提交 `.venv`、本机配置、缓存、陈旧 `.soln` 或其他临时文件。
