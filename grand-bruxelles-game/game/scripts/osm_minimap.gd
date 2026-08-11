extends Control

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var padding: float = 12.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var car: CharacterBody3D = get_node("../PrototypeCar")
@onready var mission: Node = get_node("../MissionDriveToCenter")

var _roads: Array = []
var _bounds: Vector4 = Vector4(-900.0, -900.0, 350.0, 950.0)
var _major_color: Color = Color(0.75, 0.75, 0.79, 0.72)
var _minor_color: Color = Color(0.43, 0.44, 0.48, 0.62)
var _background_color: Color = Color(0.035, 0.038, 0.048, 0.92)
var _player_color: Color = Color(1.0, 0.82, 0.16, 1.0)
var _checkpoint_color: Color = Color(1.0, 0.33, 0.12, 1.0)

const MISSION_TARGETS: Array[Vector3] = [
    Vector3(-272.04, 0.0, -217.07),
    Vector3(81.54, 0.0, -664.58),
    Vector3(319.01, 0.0, -535.20),
]


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _load_map_data()
    queue_redraw()


func _process(_delta: float) -> void:
    queue_redraw()


func _load_map_data() -> void:
    if not FileAccess.file_exists(data_path):
        push_warning("Minimap OSM data missing: %s" % data_path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("Minimap could not parse OSM data")
        return
    var data: Dictionary = parsed
    _roads = data.get("roads", [])
    var raw_bounds: Array = data.get("bounds_m", [])
    if raw_bounds.size() == 4:
        _bounds = Vector4(
            float(raw_bounds[0]),
            float(raw_bounds[1]),
            float(raw_bounds[2]),
            float(raw_bounds[3])
        )


func _world_to_map(world_x: float, world_z: float) -> Vector2:
    var usable_width: float = maxf(size.x - padding * 2.0, 1.0)
    var usable_height: float = maxf(size.y - padding * 2.0, 1.0)
    var span_x: float = maxf(_bounds.z - _bounds.x, 1.0)
    var span_z: float = maxf(_bounds.w - _bounds.y, 1.0)
    var normalized_x: float = (world_x - _bounds.x) / span_x
    var normalized_z: float = (world_z - _bounds.y) / span_z
    return Vector2(
        padding + normalized_x * usable_width,
        padding + normalized_z * usable_height
    )


func _draw() -> void:
    draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))

    for road_variant: Variant in _roads:
        var road: Dictionary = road_variant
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        var class_name: String = str(road.get("class", ""))
        var is_major: bool = class_name in ["primary", "secondary", "tertiary"]
        var color: Color = _major_color if is_major else _minor_color
        var width: float = 1.8 if is_major else 1.0
        for index: int in range(points.size() - 1):
            var start: Variant = points[index]
            var finish: Variant = points[index + 1]
            draw_line(
                _world_to_map(float(start[0]), float(start[1])),
                _world_to_map(float(finish[0]), float(finish[1])),
                color,
                width,
                true
            )

    var actor: Node3D = car if bool(car.call("has_driver")) else player
    var actor_point: Vector2 = _world_to_map(actor.global_position.x, actor.global_position.z)
    draw_circle(actor_point, 5.5, _player_color)
    draw_circle(actor_point, 8.5, Color(1.0, 0.82, 0.16, 0.25), false, 1.5)

    var stage: int = int(mission.call("get_stage"))
    if stage >= 1 and stage <= MISSION_TARGETS.size():
        var checkpoint: Vector3 = MISSION_TARGETS[stage - 1]
        var checkpoint_point: Vector2 = _world_to_map(checkpoint.x, checkpoint.z)
        draw_circle(checkpoint_point, 6.0, _checkpoint_color, false, 2.0)
        draw_circle(checkpoint_point, 2.3, _checkpoint_color)


func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = _background_color
    style.border_color = Color(1.0, 1.0, 1.0, 0.16)
    style.set_border_width_all(1)
    style.set_corner_radius_all(18)
    return style
