"""Solve and replay the PDDL study cases with Pyperplan 2.1."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from pyperplan.grounding import ground
from pyperplan.planner import _parse
from pyperplan.search import breadth_first_search
from pyperplan.task import Task


CASE_NAMES = (
    "default_race_problem.pddl",
    "recover_goal_problem.pddl",
    "cooperation_problem.pddl",
)


@dataclass(frozen=True)
class CaseReport:
    plan_lines: tuple[str, ...]
    goal_reached: bool

    @property
    def action_names(self) -> tuple[str, ...]:
        return tuple(_action_name(line) for line in self.plan_lines)


def _build_task(root: Path, problem_path: Path):
    problem = _parse(root / "adversary_domain.pddl", problem_path)
    return ground(
        problem,
        remove_statics_from_initial_state=False,
        remove_irrelevant_operators=False,
    )


def _action_name(operator_name: str) -> str:
    return operator_name.removeprefix("(").split()[0]


def _find_operator(task, name: str):
    return next((operator for operator in task.operators if operator.name == name), None)


def _replay(task, plan: Iterable):
    state = task.initial_state
    for operator in plan:
        if not operator.applicable(state):
            raise AssertionError(f"Planner emitted an inapplicable operator: {operator.name}")
        state = operator.apply(state)
    return state


def _assert_runtime_revalidation(root: Path) -> None:
    default_task = _build_task(root, root / "adversary_problem.pddl")
    recover_task = _build_task(root, root / "pddl_cases" / "recover_goal_problem.pddl")
    stale_take = _find_operator(default_task, "(take_core observatory)")
    if stale_take is None:
        raise AssertionError("take_core must be groundable for the default snapshot")

    reached_observatory = set(default_task.initial_state)
    for operator_name in (
        "(move_thief vault archive)",
        "(move_thief archive atrium)",
        "(move_thief atrium observatory)",
        "(move_warden archive atrium)",
        "(move_warden atrium observatory)",
        "(move_warden observatory gallery)",
        "(move_warden gallery gatehouse)",
    ):
        operator = _find_operator(default_task, operator_name)
        if operator is None or not operator.applicable(reached_observatory):
            raise AssertionError(f"could not reach take_core state with {operator_name}")
        reached_observatory = operator.apply(reached_observatory)
    reached_observatory.discard("(player_at entrance)")
    reached_observatory.add("(player_at observatory)")
    if not stale_take.applicable(reached_observatory):
        raise AssertionError("take_core was not legal in its reachable race state")

    player_took_core = set(reached_observatory)
    player_took_core.discard("(core_at observatory)")
    player_took_core.discard("(phase_race)")
    player_took_core.add("(phase_recover)")
    player_took_core.add("(player_has_core)")
    if stale_take.applicable(player_took_core):
        raise AssertionError("take_core remained legal after the player owns the core")

    if frozenset(player_took_core) != recover_task.initial_state:
        raise AssertionError("player pickup snapshot does not match the recover fixture")
    if any(_action_name(operator.name) == "take_core" for operator in recover_task.operators):
        raise AssertionError("take_core was available in a freshly generated recover problem")

    wrong_vault = _find_operator(default_task, "(secure_core observatory)")
    if wrong_vault is not None:
        raise AssertionError("secure_core was groundable outside the vault")

    impossible_move = _find_operator(default_task, "(move_thief vault gatehouse)")
    if impossible_move is not None:
        raise AssertionError("a move without a map link was grounded")

    left_vault = _find_operator(default_task, "(move_thief vault archive)")
    if left_vault is None:
        raise AssertionError("expected map move was not groundable")
    displaced_thief = set(default_task.initial_state)
    displaced_thief.discard("(thief_at vault)")
    displaced_thief.add("(thief_at archive)")
    if left_vault.applicable(displaced_thief):
        raise AssertionError("a move was legal from a stale actor location")

    cooperation_task = _build_task(root, root / "pddl_cases" / "cooperation_problem.pddl")
    cooperation_plan = breadth_first_search(cooperation_task)
    if cooperation_plan is None:
        raise AssertionError("cooperation case has no plan")
    capture_index = next(
        index for index, operator in enumerate(cooperation_plan)
        if _action_name(operator.name) == "capture_carrier"
    )
    state_before_capture = _replay(cooperation_task, cooperation_plan[:capture_index])
    capture = cooperation_plan[capture_index]
    if not capture.applicable(state_before_capture):
        raise AssertionError("planned capture is unexpectedly illegal")

    charm_used = set(state_before_capture)
    charm_used.discard("(carrier_marked)")
    charm_used.add("(carrier_unmarked)")
    if capture.applicable(charm_used):
        raise AssertionError("capture remained legal after ward_charm cleared the mark")

    key_used = set(state_before_capture)
    key_used.discard("(exit_sealed)")
    key_used.add("(exit_unsealed)")
    if capture.applicable(key_used):
        raise AssertionError("capture remained legal after brass_key reopened the exit")

    for changed_state, required_action in (
        (charm_used, "mark_carrier"),
        (key_used, "seal_exit"),
    ):
        refreshed_task = Task(
            cooperation_task.name,
            cooperation_task.facts,
            frozenset(changed_state),
            cooperation_task.goals,
            cooperation_task.operators,
        )
        refreshed_plan = breadth_first_search(refreshed_task)
        if refreshed_plan is None:
            raise AssertionError(f"replanning failed after {required_action} invalidation")
        refreshed_names = {_action_name(operator.name) for operator in refreshed_plan}
        if required_action not in refreshed_names:
            raise AssertionError(f"fresh plan did not restore {required_action}")


def verify_all_cases(root: Path) -> dict[str, CaseReport]:
    reports: dict[str, CaseReport] = {}
    all_actions: set[str] = set()

    for case_name in CASE_NAMES:
        task = _build_task(root, root / "pddl_cases" / case_name)
        plan = breadth_first_search(task)
        if plan is None:
            raise AssertionError(f"Pyperplan found no plan for {case_name}")
        final_state = _replay(task, plan)
        plan_lines = tuple(operator.name for operator in plan)
        action_names = tuple(_action_name(line) for line in plan_lines)
        if not task.goal_reached(final_state):
            raise AssertionError(f"replay did not reach the goal for {case_name}")
        reports[case_name] = CaseReport(plan_lines, True)
        all_actions.update(action_names)

    required_actions = {
        "move_thief", "move_warden", "take_core", "secure_core",
        "mark_carrier", "seal_exit", "capture_carrier",
    }
    if not required_actions <= all_actions:
        raise AssertionError(f"missing action coverage: {required_actions - all_actions}")

    default_actions = reports["default_race_problem.pddl"].action_names
    cooperation_actions = reports["cooperation_problem.pddl"].action_names
    if not {"move_thief", "move_warden"} <= set(default_actions):
        raise AssertionError("default case did not use both adversaries")
    if not {"mark_carrier", "seal_exit", "capture_carrier"} <= set(cooperation_actions):
        raise AssertionError("cooperation case lacks its dependency chain")

    _assert_runtime_revalidation(root)
    return reports


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    reports = verify_all_cases(root)
    for case_name, report in reports.items():
        print(case_name)
        for action in report.plan_lines:
            print(f"  {action}")


if __name__ == "__main__":
    main()
