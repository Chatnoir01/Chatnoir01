extends Label

@export var car_path: NodePath = NodePath("../PrototypeCar")
@export var traffic_manager_path: NodePath = NodePath("../TrafficManager")

var car: Node = null
var traffic_manager: Node = null


func _ready() -> void:
    car = get_node_or_null(car_path)
    traffic_manager = get_node_or_null(traffic_manager_path)
    _refresh()


func _process(_delta: float) -> void:
    _refresh()


func _refresh() -> void:
    var traffic_count := 0
    var default_limit := 30.0
    var mix := {"car": 0, "scooter": 0, "motorcycle": 0}
    if traffic_manager != null:
        if traffic_manager.has_method("get_active_vehicle_count"):
            traffic_count = int(traffic_manager.call("get_active_vehicle_count"))
        if traffic_manager.has_method("get_default_speed_kmh"):
            default_limit = float(traffic_manager.call("get_default_speed_kmh"))
        if traffic_manager.has_method("get_active_archetype_counts"):
            var raw_mix: Variant = traffic_manager.call("get_active_archetype_counts")
            if typeof(raw_mix) == TYPE_DICTIONARY:
                mix = raw_mix

    var mix_text := "%d auto · %d scooter · %d moto" % [
        int(mix.get("car", 0)),
        int(mix.get("scooter", 0)),
        int(mix.get("motorcycle", 0)),
    ]

    if car != null and car.has_method("has_driver") and bool(car.call("has_driver")):
        var speed := 0.0
        var health := 100.0
        var disabled := false
        if car.has_method("get_speed_kmh"):
            speed = float(car.call("get_speed_kmh"))
        if car.has_method("get_vehicle_health"):
            health = float(car.call("get_vehicle_health"))
        if car.has_method("is_vehicle_disabled"):
            disabled = bool(car.call("is_vehicle_disabled"))
        var state := "IMMOBILISÉ" if disabled else "%d%%" % int(round(health))
        text = (
            "VÉHICULE · %03d km/h · ÉTAT %s\nTRAFIC · %d · %s" %
            [int(round(speed)), state, traffic_count, mix_text]
        )
        return

    text = "TRAFIC · %d · %s · Bruxelles %.0f km/h par défaut" % [
        traffic_count,
        mix_text,
        default_limit,
    ]
