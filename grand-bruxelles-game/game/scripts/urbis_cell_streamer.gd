extends Node3D
class_name UrbisCellStreamer

signal cell_loaded(cell_id: String)
signal cell_unloaded(cell_id: String)

@export_file("*.json") var index_path: String = "res://data/urbis/remaining_brussels/runtime_index.json"
@export var fallback_target_path: NodePath = NodePath("../Player")
@export_range(250.0, 4000.0, 50.0) var load_radius_m: float = 900.0
@export_range(300.0, 5000.0, 50.0) var unload_radius_m: float = 1250.0
@export_range(0.05, 2.0, 0.05) var update_interval_s: float = 0.35
@export var build_collisions: bool = false

var _cells: Array[Dictionary] = []
var _loaded: Dictionary = {}
var _elapsed: float = 0.0
var _index_ready: bool = false


func _ready() -> void:
    if unload_radius_m < load_radius_m:
        unload_radius_m = load_radius_m + 250.0
    _index_ready = _load_index()
    set_process(_index_ready)
    if _index_ready:
        _refresh_streaming()


func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed < update_interval_s:
        return
    _elapsed = 0.0
    _refresh_streaming()


func _load_index() -> bool:
    if not FileAccess.file_exists(index_path):
        push_warning("UrbIS runtime index missing: %s" % index_path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid UrbIS runtime index JSON: %s" % index_path)
        return false
    var data := parsed as Dictionary
    var index_format := str(data.get("format", ""))
    if index_format != "grand-bruxelles-urbis-runtime-index-v1" and index_format != "grand-bruxelles-urbis-runtime-index-v2":
        push_error("Unsupported UrbIS runtime index format: %s" % index_format)
        return false

    _cells.clear()
    for raw_cell: Variant in data.get("cells", []):
        if typeof(raw_cell) != TYPE_DICTIONARY:
            continue
        var cell := raw_cell as Dictionary
        var bounds: Variant = cell.get("world_bounds", [])
        if typeof(bounds) != TYPE_ARRAY or bounds.size() != 4:
            continue
        if str(cell.get("cell_id", "")).is_empty():
            continue
        if str(cell.get("geometry_path", "")).is_empty():
            continue
        _cells.append(cell)

    var excluded_count := int(data.get("excluded_cell_count", 0))
    print(
        "Grand Bruxelles streamer index: %d streamable cells, %d ownership exclusions" % [
            _cells.size(), excluded_count
        ]
    )
    return true


func _stream_position() -> Vector2:
    var camera := get_viewport().get_camera_3d()
    if camera != null:
        return Vector2(camera.global_position.x, camera.global_position.z)
    if not fallback_target_path.is_empty():
        var target := get_node_or_null(fallback_target_path) as Node3D
        if target != null:
            return Vector2(target.global_position.x, target.global_position.z)
    return Vector2(global_position.x, global_position.z)


func _distance_to_bounds(point: Vector2, raw_bounds: Array) -> float:
    var min_x := float(raw_bounds[0])
    var min_z := float(raw_bounds[1])
    var max_x := float(raw_bounds[2])
    var max_z := float(raw_bounds[3])
    var nearest_x := clampf(point.x, min_x, max_x)
    var nearest_z := clampf(point.y, min_z, max_z)
    return point.distance_to(Vector2(nearest_x, nearest_z))


func _refresh_streaming() -> void:
    var point := _stream_position()
    var should_load: Dictionary = {}

    for cell: Dictionary in _cells:
        var cell_id := str(cell["cell_id"])
        var bounds := cell.get("world_bounds", []) as Array
        var distance := _distance_to_bounds(point, bounds)
        if distance <= load_radius_m:
            should_load[cell_id] = true
            if not _loaded.has(cell_id):
                _load_cell(cell)

    var loaded_ids: Array = _loaded.keys()
    for raw_id: Variant in loaded_ids:
        var cell_id := str(raw_id)
        if should_load.has(cell_id):
            continue
        var cell: Dictionary = _loaded[cell_id]["metadata"]
        var bounds := cell.get("world_bounds", []) as Array
        if _distance_to_bounds(point, bounds) > unload_radius_m:
            _unload_cell(cell_id)


func _load_cell(cell: Dictionary) -> void:
    var cell_id := str(cell["cell_id"])
    var geometry_path := str(cell["geometry_path"])
    if not FileAccess.file_exists(geometry_path):
        push_warning("UrbIS geometry missing for %s: %s" % [cell_id, geometry_path])
        return

    var builder := UrbisCellBuilder.new()
    builder.name = "Cell_%s" % cell_id
    builder.data_path = geometry_path
    builder.expected_cell_id = cell_id
    builder.build_collisions = build_collisions
    add_child(builder)
    _loaded[cell_id] = {
        "node": builder,
        "metadata": cell,
    }
    cell_loaded.emit(cell_id)


func _unload_cell(cell_id: String) -> void:
    if not _loaded.has(cell_id):
        return
    var entry: Dictionary = _loaded[cell_id]
    var node := entry.get("node") as Node
    if node != null and is_instance_valid(node):
        node.queue_free()
    _loaded.erase(cell_id)
    cell_unloaded.emit(cell_id)


func loaded_cell_count() -> int:
    return _loaded.size()


func loaded_cell_ids() -> Array[String]:
    var result: Array[String] = []
    for raw_id: Variant in _loaded.keys():
        result.append(str(raw_id))
    result.sort()
    return result
