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
    if traffic_manager != null:
        if traffic_manager.has_method("get_active_vehicle_count"):
            traffic_count = int(traffic_manager.call("get_active_vehicle_count"))
        if traffic_manager.has_method("get_default_speed_kmh"):
            default_limit = float(traffic_manager.call("get_default_speed_kmh"))

    if car != null and car.has_method("has_driver") and bool(car.call("has_driver")):
        var speed := 0.0
        if car.has_method("get_speed_kmh"):
            speed = float(car.call("get_speed_kmh"))
        text = (
            "VÉHICULE · %03d km/h\nTRAFIC CIVIL · %d · Bruxelles %.0f par défaut" %
            [int(round(speed)), traffic_count, default_limit]
        )
        return

    text = "TRAFIC CIVIL · %d véhicules IA · Bruxelles %.0f km/h par défaut" % [
        traffic_count,
        default_limit,
    ]
