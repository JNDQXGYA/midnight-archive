; adversary_domain_snapshot.pddl -- 乙的领域模型快照（丙的测试夹具）
;
; 来源：分支 feature/pddl-adversaries 的 adversary_domain.pddl，逐字复制。
; 为什么复制而不是直接用根目录那份：乙的分支还没合并到 main，而丙的集成测试
; 现在就要跑真实模型。等合并之后，把 tests 里的路径改成 'adversary_domain.pddl'
; 并删掉这个文件（t_domain.pl 会自动检查两边的动作签名是否一致）。
;
; 命名以这份为准：thief_at / warden_at / player_at / core_at，
; phase_race / phase_recover，carrier_marked / carrier_unmarked，
; exit_unsealed / exit_sealed，player_has_core / thief_holds_core。

(define (domain midnight_archive_adversaries)
  (:requirements :strips :typing)

  (:types location)

  (:predicates
    (link ?from ?to - location)
    (exit ?place - location)
    (vault_room ?place - location)
    (thief_at ?place - location)
    (warden_at ?place - location)
    (player_at ?place - location)
    (core_at ?place - location)
    (thief_holds_core)
    (player_has_core)
    (core_secured)
    (core_recovered)
    (phase_race)
    (phase_recover)
    (carrier_marked)
    (carrier_unmarked)
    (exit_unsealed)
    (exit_sealed)
    (captured)
  )

  (:action move_thief
    :parameters (?from ?to - location)
    :precondition (and (thief_at ?from) (link ?from ?to))
    :effect (and (not (thief_at ?from)) (thief_at ?to))
  )

  (:action move_warden
    :parameters (?from ?to - location)
    :precondition (and (warden_at ?from) (link ?from ?to))
    :effect (and (not (warden_at ?from)) (warden_at ?to))
  )

  (:action take_core
    :parameters (?loc - location)
    :precondition (and (phase_race) (thief_at ?loc) (core_at ?loc))
    :effect (and (not (core_at ?loc)) (thief_holds_core))
  )

  (:action secure_core
    :parameters (?loc - location)
    :precondition (and (phase_race) (thief_at ?loc) (thief_holds_core)
                       (vault_room ?loc))
    :effect (and (not (thief_holds_core)) (core_secured))
  )

  (:action mark_carrier
    :parameters (?loc - location)
    :precondition (and (phase_recover) (thief_at ?loc) (player_at ?loc)
                       (player_has_core) (carrier_unmarked))
    :effect (and (not (carrier_unmarked)) (carrier_marked))
  )

  (:action seal_exit
    :parameters (?loc - location)
    :precondition (and (phase_recover) (warden_at ?loc) (exit ?loc)
                       (exit_unsealed))
    :effect (and (not (exit_unsealed)) (exit_sealed))
  )

  (:action capture_carrier
    :parameters (?loc - location)
    :precondition (and (phase_recover) (warden_at ?loc) (player_at ?loc)
                       (player_has_core) (carrier_marked) (exit_sealed))
    :effect (and (not (player_has_core)) (captured) (core_recovered))
  )
)
