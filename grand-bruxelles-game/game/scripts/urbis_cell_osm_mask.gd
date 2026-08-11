extends Node
class_name UrbisCellOSMMask

@export var streamer_path: NodePath = NodePath("../RemainingBrusselsStreamer")
@export var osm_path: NodePath = NodePath("../BrusselsOSM")

var _streamer: Node = null
var _osm: Node = null
var _bounds_by_cell: Dictionary = {}
var _masked_nodes_by_cell: Dictionary = {}


func _ready() -> void:
    call_deferred("_bind_and_sync")


func _bind_and_sync() -> void:
    _streamer = get_node_or_null(streamer_path)
    _osm = get_node_or_null(osm_path)
    if _streamer == null:
        push_warning("UrbIS OSM mask: streamer not found at %s" % streamer_path)
        return
    if _osm == null:
        push_warning("UrbIS OSM mask: OSM root not found at %s" % osm_path)
        return

    var index_path := str(_streamer.get("index_path"))
    if not _load_index_bounds(index_path):
        return

    if not _streamer.is_connected("cell_loaded", Callable(self, "_on_cell_loaded")):
        _streamer.connect("cell_loaded", Callable(self, "_on_cell_loaded"))
    if not _streamer.is_connected("cell_unloaded", Callable(self, "_on_cell_unloaded")):
        _streamer.connect("cell_unloaded", Callable(self, "_on_cell_unloaded"))

    var loaded_ids: Variant = _streamer.call("loaded_cell_ids")
    if typeof(loaded_ids) == TYPE_ARRAY:
        for raw_id: Variant in loaded_ids:
            _on_cell_loaded(str(raw_id))


func _load_index_bounds(path: String) -> bool:
    if not FileAccess.file_exists(path):
        push_warning("UrbIS OSM mask: runtime index missing: %s" % path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("UrbIS OSM mask: invalid runtime index JSON")
        return false
    var data := parsed as Dictionary
    var index_format := str(data.get("format", ""))
    if index_format != "grand-bruxelles-urbis-runtime-index-v1" and index_format != "grand-bruxelles-urbis-runtime-index-v2":
        push_error("UrbIS OSM mask: unsupported runtime index format %s" % index_format)
        return false

    _bounds_by_cell.clear()
    for raw_cell: Variant in data.get("cells", []):
        if typeof(raw_cell) != TYPE_DICTIONARY:
            continue
        var cell := raw_cell as Dictionary
        var cell_id := str(cell.get("cell_id", ""))
        var bounds: Variant = cell.get("world_bounds", [])
        if cell_id.is_empty() or typeof(bounds) != TYPE_ARRAY or bounds.size() != 4:
            continue
        _bounds_by_cell[cell_id] = bounds
    return true


func _inside_bounds(position: Vector3, bounds: Array) -> bool:
    if bounds.size() != 4:
        return false
    var min_x := float(bounds[0])
    var min_z := float(bounds[1])
    var max_x := float(bounds[2])
    var max_z := float(bounds[3])
    return position.x >= min_x and position.x < max_x and position.z >= min_z and position.z < max_z


func _mask_root(root: Node, bounds: Array, changes: Array) -> int:
    var hidden := 0
    for child: Node in root.get_children():
        if child is GeometryInstance3D:
            var geometry := child as GeometryInstance3D
            if _inside_bounds(geometry.global_position, bounds):
                changes.append({"node": geometry, "was_visible": geometry.visible})
                geometry.visible = false
                hidden += 1
    return hidden


func _on_cell_loaded(cell_id: String) -> void:
    if _osm == null or not _bounds_by_cell.has(cell_id) or _masked_nodes_by_cell.has(cell_id):
        return
    var bounds := _bounds_by_cell[cell_id] as Array
    var changes: Array = []
    var hidden := 0

    var roads := _osm.get_node_or_null("GeneratedRoads")
    if roads != null:
        hidden += _mask_root(roads, bounds, changes)
    var buildings := _osm.get_node_or_null("GeneratedBuildings")
    if buildings != null:
        hidden += _mask_root(buildings, bounds, changes)

    _masked_nodes_by_cell[cell_id] = changes
    print("Grand Bruxelles streaming mask %s: %d OSM greybox nodes hidden" % [cell_id, hidden])


func _on_cell_unloaded(cell_id: String) -> void:
    if not _masked_nodes_by_cell.has(cell_id):
        return
    var changes := _masked_nodes_by_cell[cell_id] as Array
    var restored := 0
    for raw_change: Variant in changes:
        if typeof(raw_change) != TYPE_DICTIONARY:
            continue
        var change := raw_change as Dictionary
        var node := change.get("node") as GeometryInstance3D
        if node != null and is_instance_valid(node):
            node.visible = bool(change.get("was_visible", true))
            restored += 1
    _masked_nodes_by_cell.erase(cell_id)
    print("Grand Bruxelles streaming mask %s: %d OSM greybox nodes restored" % [cell_id, restored])


func masked_cell_count() -> int:
    return _masked_nodes_by_cell.size()
