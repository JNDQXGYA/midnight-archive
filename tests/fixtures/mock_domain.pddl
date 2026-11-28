; mock_domain.pddl -- 集成测试用的替身领域。负责人：丙。
;
; 目的：在乙的真 adversary_domain.pddl 到位之前，先验证
;       "世界摘要 -> problem.pddl -> pyperplan -> Prolog 动作项" 整条链路。
; 形状与正式模型一致（typed、STRIPS、两个对手、无否定前置条件），
; 所以它也顺便是一份可以直接抄的模板。
;
; 不参与游戏运行，只用于 tests/integration/t_bridge.pl。

(define (domain mock_archive)
    (:requirements :strips :typing)

    (:types
        loc thing - object
    )

    (:predicates
        (link ?a ?b - loc)
        (thief_at ?l - loc)
        (warden_at ?l - loc)
        (at ?x - thing ?l - loc)
        (holding_thief ?x - thing)
    )

    (:action move_thief
        :parameters (?from ?to - loc)
        :precondition (and (thief_at ?from) (link ?from ?to))
        :effect (and (not (thief_at ?from)) (thief_at ?to))
    )

    (:action move_warden
        :parameters (?from ?to - loc)
        :precondition (and (warden_at ?from) (link ?from ?to))
        :effect (and (not (warden_at ?from)) (warden_at ?to))
    )

    (:action take_core
        :parameters (?l - loc)
        :precondition (and (thief_at ?l) (at star_core ?l))
        :effect (and (not (at star_core ?l)) (holding_thief star_core))
    )
)
