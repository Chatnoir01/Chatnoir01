extends Node3D

var speed_kmh: float = 0.0
var body_damage: float = 40.0
var mechanical_damage: float = 60.0
var health: float = 47.0
var repair_calls: int = 0


func get_speed_kmh() -> float:
    return speed_kmh


func get_vehicle_health() -> float:
    return health


func get_vehicle_body_damage() -> float:
    return body_damage


func get_vehicle_mechanical_damage() -> float:
    return mechanical_damage


func repair_vehicle(_amount: float = 100.0) -> Dictionary:
    body_damage = 0.0
    mechanical_damage = 0.0
    health = 100.0
    repair_calls += 1
    return {"health": health}
