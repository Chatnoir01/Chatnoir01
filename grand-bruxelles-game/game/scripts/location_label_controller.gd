extends Label
class_name LocationLabelController

@export var player_path: NodePath = NodePath("../Player")
@export var vehicle_path: NodePath = NodePath("../PrototypeCar")
@export var refresh_interval_s: float = 0.25
@export var landmark_radius_m: float = 185.0
@export var identity_plaque_enabled: bool = true

const IDENTITY_PANEL_NAME := "IdentityPlaquePanel"
const IDENTITY_PANEL_COLOR := Color(0.035, 0.16, 0.29, 0.94)
const IDENTITY_BORDER_COLOR := Color(0.86, 0.91, 0.95, 0.88)

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
var _identity_panel: Panel = null

func _ready() -> void:
    _player = get_node_or_null(player_path) as Node3D
    _vehicle = get_node_or_null(vehicle_path) as Node3D
    _ensure_identity_panel()
    set_identity_plaque_enabled(identity_plaque_enabled)
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

func set_identity_plaque_enabled(value: bool) -> void:
    identity_plaque_enabled = value
    _ensure_identity_panel()
    if _identity_panel != null:
        _identity_panel.visible = value

func get_identity_panel() -> Panel:
    _ensure_identity_panel()
    return _identity_panel

func _ensure_identity_panel() -> void:
    if _identity_panel != null and is_instance_valid(_identity_panel):
        return
    _identity_panel = get_node_or_null(IDENTITY_PANEL_NAME) as Panel
    if _identity_panel == null:
        _identity_panel = Panel.new()
        _identity_panel.name = IDENTITY_PANEL_NAME
        _identity_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _identity_panel.z_index = -1
        _identity_panel.anchor_left = 0.0
        _identity_panel.anchor_top = 0.0
        _identity_panel.anchor_right = 1.0
        _identity_panel.anchor_bottom = 1.0
        _identity_panel.offset_left = -8.0
        _identity_panel.offset_top = -3.0
        _identity_panel.offset_right = 6.0
        _identity_panel.offset_bottom = 1.0
        var plaque_style := StyleBoxFlat.new()
        plaque_style.bg_color = IDENTITY_PANEL_COLOR
        plaque_style.border_color = IDENTITY_BORDER_COLOR
        plaque_style.set_border_width_all(1)
        plaque_style.set_corner_radius_all(2)
        _identity_panel.add_theme_stylebox_override("panel", plaque_style)
        add_child(_identity_panel)
        move_child(_identity_panel, 0)

func _refresh_label() -> void:
    if not _forced_label.is_empty():
        text = _forced_label
        return
    text = label_for_world_position(_tracked_position())

func get_current_location_text() -> String:
    return text
