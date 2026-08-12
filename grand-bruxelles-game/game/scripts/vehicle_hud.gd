extends Label

@export var car_path: NodePath = NodePath("../PrototypeCar")
@export var traffic_manager_path: NodePath = NodePath("../TrafficManager")
@export var vehicle_service_system_path: NodePath = NodePath("../VehicleServiceSystem")

var car: Node = null
var traffic_manager: Node = null
var vehicle_service_system: Node = null


func _ready() -> void:
    car = get_node_or_null(car_path)
    traffic_manager = get_node_or_null(traffic_manager_path)
    vehicle_service_system = get_node_or_null(vehicle_service_system_path)
    _refresh()


func _process(_delta: float) -> void:
    _refresh()


func _refresh() -> void:
    var traffic_count := 0
    var parked_count := 0
    var delivery_count := 0
    var wreck_count := 0
    var default_limit := 30.0
    var mix := {"car": 0, "scooter": 0, "motorcycle": 0}
    if traffic_manager != null:
        if traffic_manager.has_method("get_active_vehicle_count"):
            traffic_count = int(traffic_manager.call("get_active_vehicle_count"))
        if traffic_manager.has_method("get_parked_vehicle_count"):
            parked_count = int(traffic_manager.call("get_parked_vehicle_count"))
        if traffic_manager.has_method("get_delivery_vehicle_count"):
            delivery_count = int(traffic_manager.call("get_delivery_vehicle_count"))
        if traffic_manager.has_method("get_wreck_count"):
            wreck_count = int(traffic_manager.call("get_wreck_count"))
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
    var activity_text := "%d garé · %d livraison · %d accident" % [
        parked_count,
        delivery_count,
        wreck_count,
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
        var action_line := _recovery_line(disabled)
        var service_line := _service_line(health)

        text = (
            "VÉHICULE · %03d km/h · ÉTAT %s%s%s\nTRAFIC · %d · %s · %s" %
            [
                int(round(speed)),
                state,
                action_line,
                service_line,
                traffic_count,
                mix_text,
                activity_text,
            ]
        )
        return

    text = "TRAFIC · %d · %s · %s · Bruxelles %.0f km/h par défaut" % [
        traffic_count,
        mix_text,
        activity_text,
        default_limit,
    ]


func _recovery_line(disabled: bool) -> String:
    if not disabled or car == null or not car.has_method("get_recovery_state"):
        return ""
    var recovery_state := str(car.call("get_recovery_state"))
    if recovery_state == "requested":
        var remaining := 0.0
        var quote := 0.0
        if car.has_method("get_recovery_remaining_seconds"):
            remaining = float(car.call("get_recovery_remaining_seconds"))
        if car.has_method("get_recovery_quote_eur"):
            quote = float(car.call("get_recovery_quote_eur"))
        return "\nDÉPANNEUSE · %.1fs · devis %.0f €" % [remaining, quote]
    return "\nR · appeler la dépanneuse"


func _service_line(health: float) -> String:
    if vehicle_service_system == null:
        return ""

    if vehicle_service_system.has_method("get_service_state"):
        var service_state := str(vehicle_service_system.call("get_service_state"))
        if service_state == "requested":
            var remaining := 0.0
            var quote := 0.0
            var service_name := "Garage"
            if vehicle_service_system.has_method("get_service_remaining_seconds"):
                remaining = float(vehicle_service_system.call("get_service_remaining_seconds"))
            if vehicle_service_system.has_method("get_service_quote_eur"):
                quote = float(vehicle_service_system.call("get_service_quote_eur"))
            if vehicle_service_system.has_method("get_service_name"):
                service_name = str(vehicle_service_system.call("get_service_name"))
            return "\nGARAGE · %s · %.1fs · devis %.0f €" % [service_name, remaining, quote]

    if not vehicle_service_system.has_method("get_nearest_service_for_vehicle"):
        return ""
    var nearest_variant: Variant = vehicle_service_system.call("get_nearest_service_for_vehicle")
    if typeof(nearest_variant) != TYPE_DICTIONARY:
        return ""
    var nearest: Dictionary = nearest_variant
    if nearest.is_empty():
        return ""
    var distance := float(nearest.get("distance_m", INF))
    if distance > 80.0:
        return ""

    var name := str(nearest.get("name", "Service auto"))
    var kind := str(nearest.get("kind", ""))
    if kind == "garage":
        if distance <= 14.0 and health < 99.99:
            return "\nGARAGE · %s · %.0fm · G pour demander réparation" % [name, distance]
        return "\nGARAGE · %s · %.0fm" % [name, distance]
    if kind == "tyres":
        return "\nPNEUS · %s · %.0fm" % [name, distance]
    return "\nSERVICE AUTO · %s · %.0fm" % [name, distance]
