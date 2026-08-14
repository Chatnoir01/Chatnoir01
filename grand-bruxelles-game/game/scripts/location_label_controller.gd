extends Label
class_name LocationLabelController

@export var player_path: NodePath = NodePath("../Player")
@export var vehicle_path: NodePath = NodePath("../PrototypeCar")
@export var refresh_interval_s: float = 0.25
@export var landmark_radius_m: float = 185.0

const LOCATIONS: Array[Dictionary] = [
    {
        "id": "midi",
        "label": "BRUXELLES-MIDI · BRUSSEL-ZUID",
        "position": Vector2(-668.5, 627.84),
    },
    {
        "id": "anneessens",
        "label": "ANNEESSENS",
        "position": Vector2(-272.04, -217.07),
    },
    {
        "id": "bourse",
        "label": "BOURSE · BEURS",
        "position": Vector2(81.54, -664.58),
    },
    {
        "id": "grand_place",
        "label": "GRAND-PLACE · GROTE MARKT",
        "position": Vector2(319.01, -535.20),
    },
]

var _player: Node3D = null
var _vehicle: Node3D = null
var _elapsed: float = 0.0
var _forced_label: String = ""

func _ready() -> void:
    _player = get_node_or_null(player_path) as Node3D
    _vehicle = get_node_or_null(vehicle_path) as Node3D
    _refresh_label()

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed < maxf(0.05, refresh_interval_s):
        return
    _elapsed = 0.0
    _refresh_label()

func _tracked_position() -> Vector3:
    if _vehicle != null and is_instance_valid(_vehicle) and _vehicle.has_method("has_driver"):
        if bool(_vehicle.call("has_driver")):
            return _vehicle.global_position
    if _player != null and is_instance_valid(_player):
        return _player.global_position
    if _vehicle != null and is_instance_valid(_vehicle):
        return _vehicle.global_position
    return Vector3.ZERO

func label_for_world_position(world_position: Vector3) -> String:
    var point := Vector2(world_position.x, world_position.z)
    var nearest_label := "BRUXELLES · BRUSSEL"
    var nearest_distance := INF
    for location: Dictionary in LOCATIONS:
        var anchor: Vector2 = location["position"]
        var distance := point.distance_to(anchor)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_label = str(location["label"])
    if nearest_distance <= maxf(1.0, landmark_radius_m):
        return nearest_label
    return "BRUXELLES · BRUSSEL"

func set_forced_label(value: String) -> void:
    _forced_label = value.strip_edges()
    _refresh_label()

func clear_forced_label() -> void:
    _forced_label = ""
    _refresh_label()

func _refresh_label() -> void:
    if not _forced_label.is_empty():
        text = _forced_label
        return
    text = label_for_world_position(_tracked_position())

func get_current_location_text() -> String:
    return text
