"""Deterministic three-actor teaching traces backed by the PDDL domain.

This runner is a study aid. It models only the player commands needed by the
traces. Every selected adversary action is grounded and applied through the
actual PDDL domain from this directory.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path
from typing import Iterable

from pyperplan.grounding import ground
from pyperplan.pddl.parser import Parser


WEIGHTS = {"brass_key": 1, "lamp_oil": 1, "ward_charm": 1, "star_core": 2}
CAPACITY = 4
INITIAL_LAMP = 10
LAMP_CAP = 12

ITEM_START = {
    "brass_key": "entrance",
    "lamp_oil": "atrium",
    "ward_charm": "gallery",
}

DIRECTIONS = {
    "vault": {"east": "archive"},
    "archive": {"west": "vault", "east": "atrium"},
    "atrium": {"west": "archive", "east": "observatory", "south": "entrance"},
    "observatory": {"west": "atrium", "south": "gallery"},
    "entrance": {"north": "atrium", "east": "gallery"},
    "gallery": {"west": "entrance", "north": "observatory", "east": "gatehouse"},
    "gatehouse": {"west": "gallery"},
}


@dataclass(frozen=True)
class GameState:
    player: str = "entrance"
    thief: str = "vault"
    warden: str = "archive"
    core: str = "ground"  # ground, player, thief, secured, recovered
    phase: str = "race"
    gate: str = "locked"  # locked, open, sealed
    marked: bool = False
    lamp: int = INITIAL_LAMP
    turn: int = 0
    inventory: frozenset[str] = frozenset()
    ground_items: tuple[tuple[str, str], ...] = tuple(ITEM_START.items())
    terminal: str = "running"
    captured: bool = False

    def item_locations(self) -> dict[str, str]:
        return dict(self.ground_items)


@dataclass(frozen=True)
class Choice:
    action: str | None
    reason: str
    other_reason: str


@dataclass(frozen=True)
class TimelineStep:
    command: str
    valid: bool
    consumes_turn: bool
    before: GameState
    after_player: GameState
    after: GameState
    opponent_action: str | None
    selection_reason: str
    other_adversary_reason: str
    pickup_snapshot: GameState | None
    pddl_validated: bool

    @property
    def opponent_action_count(self) -> int:
        return int(self.opponent_action is not None)


@dataclass(frozen=True)
class Trace:
    policy: str
    steps: tuple[TimelineStep, ...]
    terminal: str
    pickup_snapshot: GameState


class PddlAdapter:
    """Build a current PDDL snapshot and execute a grounded legal operator."""

    def __init__(self, root: Path):
        self.root = root
        self.domain_path = root / "adversary_domain.pddl"
        opening_parser = Parser(self.domain_path, root / "adversary_problem.pddl")
        self.domain = opening_parser.parse_domain()
        opening = opening_parser.parse_problem(self.domain)
        self.locations = tuple(opening.objects)
        self.static_facts = tuple(
            self._predicate_text(predicate)
            for predicate in opening.initial_state
            if predicate.name in {"link", "exit", "vault_room"}
        )
        self.graph = self._graph_from_opening(opening.initial_state)
        self._validate_player_directions()

    @staticmethod
    def _predicate_text(predicate) -> str:
        values = " ".join(value for value, _ in predicate.signature)
        return f"({predicate.name}{(' ' + values) if values else ''})"

    @staticmethod
    def _graph_from_opening(predicates) -> dict[str, tuple[str, ...]]:
        graph: dict[str, list[str]] = {}
        for predicate in predicates:
            if predicate.name == "link":
                source, destination = (value for value, _ in predicate.signature)
                graph.setdefault(source, []).append(destination)
        return {room: tuple(neighbours) for room, neighbours in graph.items()}

    def _snapshot_text(self, state: GameState) -> str:
        facts = list(self.static_facts)
        facts.extend(
            [
                f"(thief_at {state.thief})",
                f"(warden_at {state.warden})",
                f"(player_at {state.player})",
                f"(phase_{state.phase})",
                "(carrier_marked)" if state.marked else "(carrier_unmarked)",
                "(exit_sealed)" if state.gate == "sealed" else "(exit_unsealed)",
            ]
        )
        core_facts = {
            "ground": "(core_at observatory)",
            "player": "(player_has_core)",
            "thief": "(thief_holds_core)",
            "secured": "(core_secured)",
            "recovered": "(core_recovered)",
        }
        facts.append(core_facts[state.core])
        if state.captured:
            facts.append("(captured)")
        objects = " ".join(self.locations)
        initial = "\n    ".join(facts)
        goal = "(and (core_secured) (warden_at gatehouse))"
        if state.phase == "recover":
            goal = "(and (captured) (core_recovered))"
        return f"""(define (problem live_snapshot)
  (:domain midnight_archive_adversaries)
  (:objects {objects} - location)
  (:init
    {initial}
  )
  (:goal {goal})
)
"""

    def _validate_player_directions(self) -> None:
        direction_edges = {
            (room, destination)
            for room, exits in DIRECTIONS.items()
            for destination in exits.values()
        }
        pddl_edges = {
            (room, neighbour)
            for room, neighbours in self.graph.items()
            for neighbour in neighbours
        }
        if direction_edges != pddl_edges:
            raise AssertionError("Player compass directions do not match the opening PDDL map")

    def _task(self, state: GameState):
        parser = Parser(self.domain_path)
        parser.probInput = self._snapshot_text(state)
        problem = parser.parse_problem(self.domain, read_from_file=False)
        return ground(
            problem,
            remove_statics_from_initial_state=False,
            remove_irrelevant_operators=False,
        )

    def legal_actions(self, state: GameState) -> dict[str, object]:
        task = self._task(state)
        return {
            operator.name: operator
            for operator in task.operators
            if operator.applicable(task.initial_state)
        }

    def apply(self, state: GameState, action: str) -> GameState:
        legal = self.legal_actions(state)
        if action not in legal:
            raise ValueError(f"PDDL action is not legal in this snapshot: {action}")
        task = self._task(state)
        operator = next(candidate for candidate in task.operators if candidate.name == action)
        facts = operator.apply(task.initial_state)
        return self._state_from_facts(state, facts)

    @staticmethod
    def _location(facts: Iterable[str], predicate: str) -> str:
        prefix = f"({predicate} "
        return next(fact[len(prefix):-1] for fact in facts if fact.startswith(prefix))

    def _state_from_facts(self, prior: GameState, facts: Iterable[str]) -> GameState:
        fact_set = set(facts)
        if any(fact.startswith("(core_at ") for fact in fact_set):
            core = "ground"
        elif "(thief_holds_core)" in fact_set:
            core = "thief"
        elif "(player_has_core)" in fact_set:
            core = "player"
        elif "(core_secured)" in fact_set:
            core = "secured"
        else:
            core = "recovered"
        gate = "sealed" if "(exit_sealed)" in fact_set else prior.gate
        return replace(
            prior,
            player=self._location(fact_set, "player_at"),
            thief=self._location(fact_set, "thief_at"),
            warden=self._location(fact_set, "warden_at"),
            core=core,
            marked="(carrier_marked)" in fact_set,
            gate=gate,
            captured="(captured)" in fact_set,
            inventory=prior.inventory if core == "player" else prior.inventory - {"star_core"},
        )


class TimelineRunner:
    """Run one deterministic scheduling policy against current PDDL snapshots."""

    def __init__(self, root: Path, policy: str):
        if policy not in {"guard-first", "race-balanced"}:
            raise ValueError(f"Unknown policy: {policy}")
        self.policy = policy
        self.adapter = PddlAdapter(root)
        self.state = GameState()
        self.steps: list[TimelineStep] = []
        self.pickup_snapshot: GameState | None = None
        self._balanced_slot = 0
        self._defer_seal_once = False

    def perform(self, command: str) -> TimelineStep:
        before = self.state
        after_player, valid, consumes = self._apply_player_command(command)
        pickup = after_player if valid and before.core != "player" and after_player.core == "player" else None
        if pickup is not None:
            self.pickup_snapshot = pickup

        if not valid or not consumes or after_player.terminal != "running":
            step = TimelineStep(
                command, valid, consumes, before, after_player, after_player, None,
                "No opponent response because the command did not consume a running turn.",
                "Both adversaries retain their current state.", pickup, False,
            )
            self.state = after_player
            self.steps.append(step)
            return step

        choice = self._select_opponent_action(after_player)
        after = after_player
        pddl_validated = False
        if choice.action is not None:
            after = self.adapter.apply(after_player, choice.action)
            pddl_validated = True
        if after.captured:
            after = replace(after, terminal="lost_captured")
        elif after.core == "secured":
            after = replace(after, terminal="lost_secured")
        self._defer_seal_once = False
        step = TimelineStep(
            command, valid, consumes, before, after_player, after, choice.action,
            choice.reason, choice.other_reason, pickup, pddl_validated,
        )
        self.state = after
        self.steps.append(step)
        return step

    def run(self, commands: Iterable[str]) -> Trace:
        for command in commands:
            self.perform(command)
            if self.state.terminal != "running":
                break
        if self.pickup_snapshot is None:
            raise AssertionError("trace did not include player pickup of the star core")
        return Trace(self.policy, tuple(self.steps), self.state.terminal, self.pickup_snapshot)

    def _apply_player_command(self, command: str) -> tuple[GameState, bool, bool]:
        state = self.state
        if state.terminal != "running":
            return state, False, False
        if command in {"look", "map", "status", "inventory", "instructions"}:
            return state, True, False
        if command in {"north", "south", "east", "west"}:
            destination = DIRECTIONS[state.player].get(command)
            if destination is None:
                return state, False, False
            return self._spend_turn(replace(state, player=destination)), True, True
        if command.startswith("take_"):
            item = command.removeprefix("take_")
            return self._take_item(state, item)
        if command == "use_oil":
            if "lamp_oil" not in state.inventory:
                return state, False, False
            after_cost = replace(state, turn=state.turn + 1, lamp=max(0, state.lamp - 1))
            inventory = after_cost.inventory - {"lamp_oil"}
            return replace(after_cost, inventory=inventory, lamp=min(LAMP_CAP, after_cost.lamp + 4)), True, True
        if command == "use_key":
            if "brass_key" not in state.inventory or state.player != "gatehouse":
                return state, False, False
            if state.gate not in {"locked", "sealed"}:
                return state, False, False
            self._defer_seal_once = state.gate == "sealed"
            return self._spend_turn(replace(state, gate="open")), True, True
        if command == "escape":
            if state.player == "gatehouse" and state.core == "player" and state.gate == "open" and state.lamp > 0:
                return replace(state, terminal="won"), True, False
            return state, False, False
        return state, False, False

    def _take_item(self, state: GameState, item: str) -> tuple[GameState, bool, bool]:
        if item in {"core", "star_core"}:
            if state.player != "observatory" or state.core != "ground":
                return state, False, False
            item = "star_core"
        locations = state.item_locations()
        if item != "star_core" and locations.get(item) != state.player:
            return state, False, False
        if sum(WEIGHTS[held] for held in state.inventory) + WEIGHTS[item] > CAPACITY:
            return state, False, False
        after_cost = self._spend_turn(state)
        locations.pop(item, None)
        inventory = after_cost.inventory | {item}
        if item == "star_core":
            after_cost = replace(after_cost, core="player", phase="recover")
        return replace(after_cost, inventory=inventory, ground_items=tuple(locations.items())), True, True

    @staticmethod
    def _spend_turn(state: GameState) -> GameState:
        after = replace(state, turn=state.turn + 1, lamp=state.lamp - 1)
        return replace(after, terminal="lost_darkness") if after.lamp <= 0 else after

    def _select_opponent_action(self, state: GameState) -> Choice:
        legal = self.adapter.legal_actions(state)
        if state.phase == "race":
            return self._choose_race_action(state, legal)
        return self._choose_recover_action(state, legal)

    def _choose_race_action(self, state: GameState, legal: dict[str, object]) -> Choice:
        for urgent in (f"(take_core {state.thief})", f"(secure_core {state.thief})"):
            if urgent in legal:
                return Choice(urgent, "Urgent race action is already legal.", "The other adversary waits for its next shared slot.")
        if self.policy == "guard-first":
            if state.warden != "gatehouse":
                action = self._move_toward("warden", state.warden, "gatehouse", legal)
                return Choice(action, "Guard-first schedules the warden toward the exit before pickup.", "The thief waits while exit coverage is established.")
            action = self._move_toward("thief", state.thief, self._thief_race_target(state), legal)
            target = "the vault with the core" if state.core == "thief" else "the core"
            return Choice(action, f"The warden is guarding the exit, so the thief now advances toward {target}.", "The warden waits at the exit.")

        actor = "thief" if self._balanced_slot in {0, 1} else "warden"
        self._balanced_slot = (self._balanced_slot + 1) % 3
        target = self._thief_race_target(state) if actor == "thief" else "gatehouse"
        origin = state.thief if actor == "thief" else state.warden
        action = self._move_toward(actor, origin, target, legal)
        if action is None:
            actor = "warden" if actor == "thief" else "thief"
            target = self._thief_race_target(state) if actor == "thief" else "gatehouse"
            origin = state.thief if actor == "thief" else state.warden
            action = self._move_toward(actor, origin, target, legal)
        other = "warden" if actor == "thief" else "thief"
        return Choice(
            action,
            f"Race-balanced shared slot assigns progress to the {actor} in a two-thief, one-warden cycle.",
            f"The {other} waits until its next meaningful race slot.",
        )

    @staticmethod
    def _thief_race_target(state: GameState) -> str:
        return "vault" if state.core == "thief" else "observatory"

    def _choose_recover_action(self, state: GameState, legal: dict[str, object]) -> Choice:
        capture = f"(capture_carrier {state.player})"
        mark = f"(mark_carrier {state.player})"
        seal = f"(seal_exit gatehouse)"
        if capture in legal:
            return Choice(capture, "Capture has highest priority because every PDDL precondition now holds.", "The thief waits because the warden completes the shared objective.")
        if mark in legal:
            return Choice(mark, "Marking is immediate because the carrier is co-located and the window can close next turn.", "The warden waits while the thief establishes the capture prerequisite.")
        if seal in legal and not self._defer_seal_once:
            return Choice(seal, "Sealing is immediately legal at the exit and is required before capture.", "The thief waits while the warden denies escape.")

        predicted = self._predict_next_room(state.player)
        if state.marked and state.gate == "sealed":
            if state.warden == predicted:
                return Choice(None, f"The warden waits at predicted intercept {predicted}; capture needs the carrier to arrive.", "The thief holds position while the guard covers the intercept.")
            action = self._move_toward("warden", state.warden, predicted, legal)
            if action is not None:
                return Choice(action, f"After sealing, the warden moves toward predicted intercept {predicted} for capture.", "The thief waits while the warden closes on the marked carrier.")
        if state.warden != "gatehouse":
            action = self._move_toward("warden", state.warden, "gatehouse", legal)
            warden_distance = self._distance(state.warden, "gatehouse")
            player_distance = self._distance(state.player, "gatehouse")
            return Choice(
                action,
                f"The warden moves toward the exit. Current deadline comparison is {warden_distance + 1} warden responses including seal versus {player_distance} player edges.",
                f"The thief waits while the warden races the current exit deadline.",
            )
        action = self._move_toward("thief", state.thief, predicted, legal)
        if self._defer_seal_once:
            reason = f"The key reopened the exit, so this proposed policy defers resealing for one response and moves the thief toward predicted room {predicted}."
        else:
            reason = f"The warden guards the exit; the thief advances toward graph-predicted room {predicted}."
        return Choice(action, reason, "The warden remains at the gatehouse as guard.")

    def _move_toward(self, actor: str, origin: str, target: str, legal: dict[str, object]) -> str | None:
        next_room = self._next_hop(origin, target)
        if next_room is None:
            return None
        action = f"(move_{actor} {origin} {next_room})"
        return action if action in legal else None

    def _predict_next_room(self, player_room: str) -> str:
        return self._next_hop(player_room, "gatehouse") or "gatehouse"

    def _next_hop(self, source: str, target: str) -> str | None:
        if source == target:
            return None
        frontier = [(source, [])]
        visited = {source}
        while frontier:
            room, path = frontier.pop(0)
            for neighbour in self.adapter.graph[room]:
                if neighbour in visited:
                    continue
                candidate = path + [neighbour]
                if neighbour == target:
                    return candidate[0]
                visited.add(neighbour)
                frontier.append((neighbour, candidate))
        return None

    def _distance(self, source: str, target: str) -> int:
        if source == target:
            return 0
        frontier = [(source, 0)]
        visited = {source}
        while frontier:
            room, distance = frontier.pop(0)
            for neighbour in self.adapter.graph[room]:
                if neighbour == target:
                    return distance + 1
                if neighbour not in visited:
                    visited.add(neighbour)
                    frontier.append((neighbour, distance + 1))
        raise AssertionError(f"No route from {source} to {target}")


FAST_ROUTE = ("take_brass_key", "north", "take_lamp_oil", "east", "take_core", "south", "east", "use_key", "escape")
SLOW_ROUTE = ("take_brass_key", "north", "take_lamp_oil", "use_oil", "south", "north", "east", "take_core", "south", "east")


def run_reference_traces(root: Path) -> dict[str, Trace]:
    guard_fast = TimelineRunner(root, "guard-first").run(FAST_ROUTE)
    balanced_fast = TimelineRunner(root, "race-balanced").run(FAST_ROUTE)
    guard_slow = TimelineRunner(root, "guard-first").run(SLOW_ROUTE)
    return {
        "guard_first_fast": guard_fast,
        "race_balanced_fast": balanced_fast,
        "guard_first_slow": guard_slow,
    }


def format_trace(name: str, trace: Trace) -> str:
    lines = [f"{name} | policy={trace.policy} | terminal={trace.terminal}"]
    for step in trace.steps:
        action = step.opponent_action or "wait"
        lines.append(
            f"T{step.after.turn} {step.command}: P={step.after.player} Th={step.after.thief} W={step.after.warden} "
            f"phase={step.after.phase} core={step.after.core} gate={step.after.gate} marked={step.after.marked} "
            f"lamp={step.after.lamp} | enemy={action} | {step.selection_reason} | other={step.other_adversary_reason}"
        )
        if step.pickup_snapshot is not None:
            snapshot = step.pickup_snapshot
            lines.append(
                f"  pickup-before-response: P={snapshot.player} Th={snapshot.thief} W={snapshot.warden} "
                f"phase={snapshot.phase} core={snapshot.core} gate={snapshot.gate} marked={snapshot.marked} lamp={snapshot.lamp}"
            )
    return "\n".join(lines)


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    for name, trace in run_reference_traces(root).items():
        print(format_trace(name, trace))
        print()


if __name__ == "__main__":
    main()
