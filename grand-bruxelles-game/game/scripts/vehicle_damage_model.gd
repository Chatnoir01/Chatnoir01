extends RefCounted
class_name VehicleDamageModel

const MIN_DAMAGE_SPEED_KMH := 12.0
const DISABLE_DAMAGE := 100.0

var body_damage: float = 0.0
var mechanical_damage: float = 0.0
var last_impact_speed_kmh: float = 0.0
var last_impact_damage: float = 0.0

func register_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    var impact_speed: float = maxf(0.0, speed_kmh)
    var hit_alignment: float = clampf(alignment, 0.0, 1.0)
    last_impact_speed_kmh = impact_speed
    if impact_speed < MIN_DAMAGE_SPEED_KMH:
        last_impact_damage = 0.0
        return _snapshot()
    var excess: float = impact_speed - MIN_DAMAGE_SPEED_KMH
    var severity: float = pow(excess, 1.18) * 0.72
    var alignment_factor: float = lerpf(0.42, 1.0, hit_alignment)
    var damage: float = clampf(severity * alignment_factor, 0.0, 55.0)
    body_damage = clampf(body_damage + damage * 0.58, 0.0, DISABLE_DAMAGE)
    mechanical_damage = clampf(mechanical_damage + damage * 0.42, 0.0, DISABLE_DAMAGE)
    last_impact_damage = damage
    return _snapshot()

func repair(amount: float = 100.0) -> Dictionary:
    var value: float = maxf(0.0, amount)
    body_damage = maxf(0.0, body_damage - value)
    mechanical_damage = maxf(0.0, mechanical_damage - value)
    last_impact_damage = 0.0
    return _snapshot()

func get_health() -> float:
    return clampf(100.0 - body_damage * 0.35 - mechanical_damage * 0.65, 0.0, 100.0)

func get_performance_factor() -> float:
    if is_disabled():
        return 0.0
    return clampf(1.0 - mechanical_damage * 0.0065, 0.42, 1.0)

func is_disabled() -> bool:
    return mechanical_damage >= DISABLE_DAMAGE or get_health() <= 4.0

func _snapshot() -> Dictionary:
    return {
        "health": get_health(),
        "body_damage": body_damage,
        "mechanical_damage": mechanical_damage,
        "performance_factor": get_performance_factor(),
        "disabled": is_disabled(),
        "last_impact_speed_kmh": last_impact_speed_kmh,
        "last_impact_damage": last_impact_damage,
    }
