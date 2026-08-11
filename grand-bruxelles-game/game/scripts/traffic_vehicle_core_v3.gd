extends "res://game/scripts/traffic_vehicle_core_v2.gd"

var traffic_archetype: String = "car"


func configure_archetype(archetype: String) -> void:
    traffic_archetype = archetype
    match traffic_archetype:
        "scooter":
            acceleration_mps2 = 4.1
            braking_mps2 = 8.2
            emergency_braking_mps2 = 12.5
            steering_response = 7.0
            speed_factor = 0.88
            obstacle_min_lookahead_m = 5.5
        "motorcycle":
            acceleration_mps2 = 4.8
            braking_mps2 = 8.8
            emergency_braking_mps2 = 13.0
            steering_response = 7.5
            speed_factor = 0.94
            obstacle_min_lookahead_m = 6.0
        _:
            traffic_archetype = "car"
            acceleration_mps2 = 3.4
            braking_mps2 = 7.5
            emergency_braking_mps2 = 12.0
            steering_response = 5.5
            speed_factor = 0.90
            obstacle_min_lookahead_m = 7.0


func get_traffic_archetype() -> String:
    return traffic_archetype
