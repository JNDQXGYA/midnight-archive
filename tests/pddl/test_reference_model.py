"""Executable acceptance checks for the isolated PDDL study reference."""

from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "pddl_cases" / "tools"
sys.path.insert(0, str(TOOLS))


class ReferenceModelContractTests(unittest.TestCase):
    def test_domain_declares_the_seven_agreed_actions(self):
        domain = (ROOT / "adversary_domain.pddl").read_text(encoding="utf-8")
        expected = [
            "move_thief", "move_warden", "take_core", "secure_core",
            "mark_carrier", "seal_exit", "capture_carrier",
        ]
        self.assertEqual(domain.count("(:action"), len(expected))
        for name in expected:
            self.assertIn(f"(:action {name}", domain)

    def test_every_required_scenario_exists(self):
        for filename in [
            "default_race_problem.pddl",
            "recover_goal_problem.pddl",
            "cooperation_problem.pddl",
        ]:
            self.assertTrue((ROOT / "pddl_cases" / filename).is_file())

    def test_study_notes_record_runtime_revalidation_cases(self):
        readme = (ROOT / "pddl_cases" / "README.md").read_text(encoding="utf-8")
        for phrase in ["take_core", "capture_carrier", "ward_charm", "brass_key"]:
            self.assertIn(phrase, readme)

    def test_validator_solves_and_replays_all_cases(self):
        from verify_reference import verify_all_cases

        reports = verify_all_cases(ROOT)
        self.assertEqual(set(reports), {
            "default_race_problem.pddl",
            "recover_goal_problem.pddl",
            "cooperation_problem.pddl",
        })
        self.assertTrue(all(report.goal_reached for report in reports.values()))
        self.assertIn("take_core", reports["default_race_problem.pddl"].action_names)
        self.assertIn("capture_carrier", reports["cooperation_problem.pddl"].action_names)
        self.assertTrue(
            reports["default_race_problem.pddl"].plan_lines[0].startswith("(")
        )

    def test_checked_plan_artifacts_replay_to_each_case_goal(self):
        from verify_reference import _build_task

        plan_files = {
            "default_race_problem.pddl": "default_race.plan.txt",
            "recover_goal_problem.pddl": "recover_goal.plan.txt",
            "cooperation_problem.pddl": "cooperation.plan.txt",
        }
        for case_name, plan_file in plan_files.items():
            task = _build_task(ROOT, ROOT / "pddl_cases" / case_name)
            operators = {operator.name: operator for operator in task.operators}
            saved_lines = [
                line.strip()
                for line in (ROOT / "pddl_cases" / plan_file).read_text(encoding="utf-8").splitlines()
                if line and not line.startswith(";")
            ]
            state = task.initial_state
            for line in saved_lines:
                self.assertIn(line, operators)
                self.assertTrue(operators[line].applicable(state), line)
                state = operators[line].apply(state)
            self.assertTrue(task.goal_reached(state), case_name)

    def test_continuous_three_actor_traces_compare_guard_timing(self):
        from timeline_runner import run_reference_traces

        traces = run_reference_traces(ROOT)
        guard_fast = traces["guard_first_fast"]
        balanced_fast = traces["race_balanced_fast"]
        slow_capture = traces["guard_first_slow"]

        self.assertEqual(guard_fast.terminal, "won")
        self.assertEqual(balanced_fast.terminal, "won")
        self.assertEqual(slow_capture.terminal, "lost_captured")
        self.assertEqual(guard_fast.pickup_snapshot.warden, "gatehouse")
        self.assertEqual(balanced_fast.pickup_snapshot.warden, "atrium")
        self.assertEqual(guard_fast.pickup_snapshot.thief, "vault")
        self.assertEqual(balanced_fast.pickup_snapshot.thief, "observatory")
        self.assertEqual(
            [step.command for step in guard_fast.steps],
            [step.command for step in balanced_fast.steps],
        )
        early_seal = next(index for index, step in enumerate(guard_fast.steps) if step.after.gate == "sealed")
        gatehouse_entry = next(index for index, step in enumerate(guard_fast.steps) if step.command == "east" and step.after.player == "gatehouse")
        self.assertLess(early_seal, gatehouse_entry)
        self.assertFalse(any(step.after.gate == "sealed" for step in balanced_fast.steps))
        self.assertTrue(any(step.opponent_action == "(capture_carrier gatehouse)" for step in slow_capture.steps))
        self.assertTrue(all(step.opponent_action_count <= 1 for trace in traces.values() for step in trace.steps))
        self.assertTrue(all(
            step.pddl_validated
            for trace in traces.values()
            for step in trace.steps
            if step.opponent_action is not None
        ))
        for fast_trace in (guard_fast, balanced_fast):
            self.assertEqual(fast_trace.steps[-1].command, "escape")
            self.assertIsNone(fast_trace.steps[-1].opponent_action)
            key_step = next(step for step in fast_trace.steps if step.command == "use_key")
            self.assertEqual(key_step.after.gate, "open")
            self.assertNotEqual(key_step.opponent_action, "(seal_exit gatehouse)")

    def test_timeline_info_and_invalid_commands_do_not_advance_opponents(self):
        from timeline_runner import TimelineRunner

        runner = TimelineRunner(ROOT, "guard-first")
        status = runner.perform("status")
        invalid = runner.perform("west")

        self.assertFalse(status.consumes_turn)
        self.assertFalse(invalid.consumes_turn)
        self.assertEqual(status.after.turn, 0)
        self.assertEqual(invalid.after.turn, 0)
        self.assertIsNone(status.opponent_action)
        self.assertIsNone(invalid.opponent_action)

    def test_timeline_handles_thief_core_delivery_and_player_action_edges(self):
        from dataclasses import replace
        from timeline_runner import GameState, TimelineRunner

        runner = TimelineRunner(ROOT, "race-balanced")
        runner.state = replace(runner.state, thief="observatory")
        first = runner.perform("north")
        self.assertEqual(first.after.core, "thief")
        self.assertEqual(first.opponent_action, "(take_core observatory)")
        runner.perform("south")
        runner.perform("north")
        runner.perform("east")
        runner.perform("south")
        secured = runner.perform("west")
        self.assertEqual(secured.after.terminal, "lost_secured")
        self.assertNotIn("star_core", secured.after.inventory)

        aliases = TimelineRunner(ROOT, "guard-first")
        self.assertFalse(aliases.perform("take_star_core").valid)
        aliases.state = replace(aliases.state, player="observatory")
        self.assertTrue(aliases.perform("take_star_core").valid)
        self.assertEqual(aliases.state.core, "player")
        self.assertIn("star_core", aliases.state.inventory)

        oil = TimelineRunner(ROOT, "guard-first")
        oil.state = GameState(player="atrium", lamp=1, inventory=frozenset({"lamp_oil"}), ground_items=())
        restored = oil.perform("use_oil")
        self.assertEqual(restored.after.lamp, 4)
        self.assertEqual(restored.after.terminal, "running")


if __name__ == "__main__":
    unittest.main()
