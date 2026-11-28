; mock_domain.pddl -- 集成测试用的替身领域。负责人：丙。
;
; 目的：在乙的真 adversary_domain.pddl 到位之前，先验证
;       "世界摘要 -> problem.pddl -> pyperplan -> Prolog 动作项" 整条链路，
;       以及 adversary_execution.pl 的前置条件表。
; 命名与 INTERFACE.md 第 2 节完全一致，所以它也是一份可以直接抄的模板。
;
; 不参与游戏运行，只用于 tests/。

(define (domain mock_archive)
    (:requirements :strips :typing)

    (:types
        loc mode - object
    )

    (:predicates
        (link ?a ?b - loc)
        (at_player ?l - loc)
        (at_thief ?l - loc)
        (at_warden ?l - loc)
        (at_core ?l - loc)
        (phase ?m - mode)
        (gate ?m - mode)
        (carrier ?m - mode)
        (thief_holds_core)
        (core_secured)
        (core_recovered)
    )

    (:action move_thief
        :parameters (?from ?to - loc)
        :precondition (and (at_thief ?from) (link ?from ?to))
        :effect (and (not (at_thief ?from)) (at_thief ?to))
    )

    (:action move_warden
        :parameters (?from ?to - loc)
        :precondition (and (at_warden ?from) (link ?from ?to))
        :effect (and (not (at_warden ?from)) (at_warden ?to))
    )

    (:action take_core
        :parameters (?l - loc)
        :precondition (and (phase race) (at_thief ?l) (at_core ?l))
        :effect (and (not (at_core ?l)) (thief_holds_core))
    )
)
